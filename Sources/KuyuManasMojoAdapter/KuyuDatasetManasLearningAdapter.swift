import Foundation
import KuyuTrainingContracts
import KuyuTrainingValidation
import ManasLearningContracts

public struct KuyuDatasetManasLearningAdapter<Encoder: ManasLearningInputEncoding>: Sendable {
    public enum AdapterError: Error, Sendable, Equatable {
        case invalidMaximumTransitions(UInt64)
        case invalidMaximumScalars(Int)
        case unsupportedRecordKind(KuyuDatasetRecord.Kind)
        case missingPolicyMetadata
        case tooManyTransitions(maximum: UInt64)
        case tooManyScalars(maximum: Int)
        case nonFiniteFloatConversion(field: String, index: UInt64)
        case unsupportedDistribution(String)
    }

    private let reader: KuyuDatasetReader
    private let encoder: Encoder
    private let evidenceVerifier: KuyuExactOnPolicyEvidenceVerifier
    private let maximumTransitions: UInt64
    private let maximumScalars: Int

    public init(
        encoder: Encoder,
        reader: KuyuDatasetReader = KuyuDatasetReader(),
        maximumTransitions: UInt64 = 100_000,
        maximumScalars: Int = 8_000_000
    ) throws {
        guard maximumTransitions > 0, maximumTransitions <= UInt64(Int.max) else {
            throw AdapterError.invalidMaximumTransitions(maximumTransitions)
        }
        guard maximumScalars > 0 else {
            throw AdapterError.invalidMaximumScalars(maximumScalars)
        }
        self.reader = reader
        self.encoder = encoder
        self.evidenceVerifier = KuyuExactOnPolicyEvidenceVerifier()
        self.maximumTransitions = maximumTransitions
        self.maximumScalars = maximumScalars
    }

    public func trajectory(from directory: URL) throws -> ManasOnPolicyTrajectory {
        let declaredManifest = try reader.manifest(in: directory)
        guard declaredManifest.descriptor.recordKind == .onPolicyTransition else {
            throw AdapterError.unsupportedRecordKind(declaredManifest.descriptor.recordKind)
        }
        guard let policy = declaredManifest.descriptor.policy,
              let sourcePolicyContext = declaredManifest.descriptor.policyContext else {
            throw AdapterError.missingPolicyMetadata
        }
        guard declaredManifest.recordCount <= maximumTransitions else {
            throw AdapterError.tooManyTransitions(maximum: maximumTransitions)
        }

        let policyContext = try makePolicyContext(sourcePolicyContext)
        var totalScalars = policyContext.initialScalarCount
        guard totalScalars <= maximumScalars else {
            throw AdapterError.tooManyScalars(maximum: maximumScalars)
        }
        var transitions: [ManasOnPolicyTransition] = []
        transitions.reserveCapacity(Int(declaredManifest.recordCount))
        let summary = try reader.read(directory) { [self] record in
            let index = transitions.count
            guard UInt64(index) < maximumTransitions else {
                throw AdapterError.tooManyTransitions(maximum: maximumTransitions)
            }
            let transition = try makeTransition(
                record: record,
                index: index,
                manifest: declaredManifest,
                policyContext: sourcePolicyContext
            )
            let transitionScalarCount = try scalarCount(of: transition)
            guard totalScalars <= maximumScalars - transitionScalarCount else {
                throw AdapterError.tooManyScalars(maximum: maximumScalars)
            }
            totalScalars += transitionScalarCount
            transitions.append(transition)
        }
        guard summary.manifest == declaredManifest else {
            throw KuyuDatasetArtifactError.manifestChangedDuringRead
        }
        let identity = ManasLearningSourceIdentity(
            datasetID: declaredManifest.descriptor.identity.datasetID,
            recordsDigest: declaredManifest.recordsDigest,
            episodeID: declaredManifest.descriptor.identity.episodeID,
            segmentID: declaredManifest.descriptor.identity.segmentID,
            segmentIndex: declaredManifest.descriptor.identity.segmentIndex,
            policyID: policy.policyID,
            checkpointDigest: policy.checkpointDigest,
            sourceObservationSpaceDigest: declaredManifest.descriptor.spaces.observation.digest,
            sourceCriticStateSpaceDigest: declaredManifest.descriptor.spaces.criticState?.digest,
            policyActionSpaceDigest: declaredManifest.descriptor.spaces.policyAction.digest,
            distributionContractDigest: policy.distributionContractDigest,
            actorInputContractDigest: encoder.actorInputContractDigest,
            criticInputContractDigest: encoder.criticInputContractDigest
        )
        return try ManasOnPolicyTrajectory(
            identity: identity,
            policyContext: policyContext,
            transitions: transitions
        )
    }

    private func makeTransition(
        record: KuyuDatasetRecord,
        index: Int,
        manifest: KuyuDatasetManifest,
        policyContext: KuyuPolicyContextContract
    ) throws -> ManasOnPolicyTransition {
        guard case .onPolicyTransition(let sample) = record else {
            throw AdapterError.unsupportedRecordKind(record.kind)
        }
        let transition = sample.transition
        let behavior = sample.behavior
        try evidenceVerifier.verify(
            behavior,
            action: transition.policyAction.values,
            actionSpace: manifest.descriptor.spaces.policyAction
        )
        let sourceActorInput = try encoder.actorInput(
            observation: transition.sourceObservation.values,
            stateFacts: transition.sourceStateFacts.values
        )
        let outcomeActorInput = try encoder.actorInput(
            observation: transition.outcomeObservation.values,
            stateFacts: transition.outcomeStateFacts.values
        )
        let sourceCriticInput = try encoder.criticInput(
            observation: transition.sourceObservation.values,
            stateFacts: transition.sourceStateFacts.values
        )
        let outcomeCriticInput = try encoder.criticInput(
            observation: transition.outcomeObservation.values,
            stateFacts: transition.outcomeStateFacts.values
        )
        let recurrent = policyContext.recurrentValue
        let contributesToLoss = recurrent.map {
            index >= $0.lossStartTransitionIndex
        } ?? true
        return ManasOnPolicyTransition(
            transitionIndex: index,
            decisionID: transition.coordinate.decisionID,
            sourceActorInput: try validatedFloats(sourceActorInput, field: "sourceActorInput", index: UInt64(index)),
            outcomeActorInput: try validatedFloats(outcomeActorInput, field: "outcomeActorInput", index: UInt64(index)),
            sourceCriticInput: try validatedFloats(sourceCriticInput, field: "sourceCriticInput", index: UInt64(index)),
            outcomeCriticInput: try validatedFloats(outcomeCriticInput, field: "outcomeCriticInput", index: UInt64(index)),
            policyAction: try floats(transition.policyAction.values, field: "policyAction", index: UInt64(index)),
            reward: try float(transition.reward, field: "reward", index: UInt64(index)),
            safetyCost: try float(transition.safetyCost, field: "safetyCost", index: UInt64(index)),
            behavior: try makeBehavior(behavior, index: UInt64(index)),
            boundary: makeBoundary(transition.boundary),
            contributesToLoss: contributesToLoss
        )
    }

    private func makeBehavior(
        _ behavior: KuyuBehaviorPolicyEvidence,
        index: UInt64
    ) throws -> ManasLearningBehaviorEvidence {
        let kinds = try behavior.distributionKinds.map { kind in
            guard let mapped = ManasLearningDistributionKind(rawValue: kind.rawValue) else {
                throw AdapterError.unsupportedDistribution(kind.rawValue)
            }
            return mapped
        }
        return ManasLearningBehaviorEvidence(
            policyID: behavior.policyID,
            checkpointDigest: behavior.checkpointDigest,
            distributionKinds: kinds,
            distributionVersion: behavior.distributionVersion,
            distributionContractDigest: behavior.distributionContractDigest,
            baseMean: try floats(behavior.baseMean, field: "baseMean", index: index),
            transformedMean: try floats(behavior.transformedMean, field: "transformedMean", index: index),
            baseLogStandardDeviation: try floats(
                behavior.baseLogStandardDeviation,
                field: "baseLogStandardDeviation",
                index: index
            ),
            preTransformSample: try floats(
                behavior.preTransformSample,
                field: "preTransformSample",
                index: index
            ),
            transformedAction: try floats(
                behavior.transformedAction,
                field: "transformedAction",
                index: index
            ),
            logProbability: try float(behavior.logProbability, field: "logProbability", index: index),
            rewardValue: try behavior.rewardValue.map {
                try float($0, field: "behavior.rewardValue", index: index)
            },
            costValue: try behavior.costValue.map {
                try float($0, field: "behavior.costValue", index: index)
            },
            inputRecurrentStateDigest: behavior.inputRecurrentStateDigest,
            outputRecurrentStateDigest: behavior.outputRecurrentStateDigest
        )
    }

    private func makePolicyContext(
        _ context: KuyuPolicyContextContract
    ) throws -> ManasLearningPolicyContext {
        switch context {
        case .fixedHistory(let value):
            return .fixedHistory(.init(
                historyLength: value.historyLength,
                featureOrderDigest: value.featureOrderDigest,
                paddingRule: value.paddingRule.rawValue,
                previousActionRule: value.previousActionRule.rawValue
            ))
        case .recurrent(let value):
            return .recurrent(.init(
                stateSpaceDigest: value.stateSpaceDigest,
                resetRule: value.resetRule,
                initialState: try floats(value.initialState, field: "initialState", index: 0),
                initialStateDigest: value.initialStateDigest,
                burnInCount: value.burnInCount,
                lossStartTransitionIndex: value.lossStartTransitionIndex
            ))
        }
    }

    private func makeBoundary(_ boundary: KuyuTrajectoryBoundary) -> ManasLearningBoundary {
        switch boundary {
        case .continues:
            .continues
        case .terminal:
            .terminal
        case .truncated(let value):
            .truncated(bootstrapAllowed: value.bootstrapAllowed)
        case .segmentEnd(let value):
            .segmentEnd(bootstrapAllowed: value.bootstrapAllowed)
        }
    }

    private func scalarCount(of transition: ManasOnPolicyTransition) throws -> Int {
        let counts = [
            transition.sourceActorInput.count,
            transition.outcomeActorInput.count,
            transition.sourceCriticInput.count,
            transition.outcomeCriticInput.count,
            transition.policyAction.count,
            transition.behavior.baseMean.count,
            transition.behavior.transformedMean.count,
            transition.behavior.baseLogStandardDeviation.count,
            transition.behavior.preTransformSample.count,
            transition.behavior.transformedAction.count,
            3,
            transition.behavior.rewardValue == nil ? 0 : 1,
            transition.behavior.costValue == nil ? 0 : 1,
        ]
        var result = 0
        for count in counts {
            guard result <= maximumScalars - count else {
                throw AdapterError.tooManyScalars(maximum: maximumScalars)
            }
            result += count
        }
        return result
    }

    private func floats(
        _ values: [Double],
        field: String,
        index: UInt64
    ) throws -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(values.count)
        for value in values {
            result.append(try float(value, field: field, index: index))
        }
        return result
    }

    private func validatedFloats(
        _ values: [Float],
        field: String,
        index: UInt64
    ) throws -> [Float] {
        guard values.allSatisfy(\.isFinite) else {
            throw AdapterError.nonFiniteFloatConversion(field: field, index: index)
        }
        return values
    }

    private func float(_ value: Double, field: String, index: UInt64) throws -> Float {
        let converted = Float(value)
        guard value.isFinite, converted.isFinite else {
            throw AdapterError.nonFiniteFloatConversion(field: field, index: index)
        }
        return converted
    }
}

private extension KuyuPolicyContextContract {
    var recurrentValue: KuyuPolicyContextContract.Recurrent? {
        if case .recurrent(let value) = self { return value }
        return nil
    }
}

private extension ManasLearningPolicyContext {
    var initialScalarCount: Int {
        if case .recurrent(let value) = self { return value.initialState.count }
        return 0
    }
}
