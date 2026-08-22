import Foundation
import KuyuTrainingContracts

public struct KuyuExactOnPolicyEvidenceVerifier: KuyuOnPolicyEvidenceVerifying {
    public enum VerificationError: Error, Sendable, Equatable {
        case invalidTolerance(Double)
        case unsupportedDistributionVersion(Int)
        case distributionSpaceMismatch(index: Int)
        case nonFiniteDistributionValue(index: Int)
        case invalidStandardDeviation(index: Int)
        case transformedActionMismatch(index: Int)
        case transformedMeanMismatch(index: Int)
        case nonFiniteLogProbability
        case logProbabilityMismatch(expected: Double, actual: Double)
    }

    public let tolerance: Double

    public init() {
        self.tolerance = 1e-6
    }

    public init(tolerance: Double) throws {
        guard tolerance.isFinite, tolerance > 0 else {
            throw VerificationError.invalidTolerance(tolerance)
        }
        self.tolerance = tolerance
    }

    public func verify(
        _ behavior: KuyuBehaviorPolicyEvidence,
        action: [Double],
        actionSpace: KuyuDatasetDescriptor.Space
    ) throws {
        guard behavior.distributionVersion == KuyuBehaviorPolicyEvidence.currentDistributionVersion else {
            throw VerificationError.unsupportedDistributionVersion(behavior.distributionVersion)
        }
        guard !action.isEmpty,
              action.count == actionSpace.channels.count,
              behavior.baseMean.count == action.count,
              behavior.transformedMean.count == action.count,
              behavior.distributionKinds.count == action.count,
              behavior.baseLogStandardDeviation.count == action.count,
              behavior.preTransformSample.count == action.count,
              behavior.transformedAction.count == action.count else {
            throw VerificationError.distributionSpaceMismatch(index: 0)
        }

        var logProbability = 0.0
        for index in action.indices {
            let channel = actionSpace.channels[index]
            let mean = behavior.baseMean[index]
            let transformedMeanEvidence = behavior.transformedMean[index]
            let logStandardDeviation = behavior.baseLogStandardDeviation[index]
            let sample = behavior.preTransformSample[index]
            let actionValue = action[index]
            let transformedActionEvidence = behavior.transformedAction[index]
            guard mean.isFinite,
                  transformedMeanEvidence.isFinite,
                  logStandardDeviation.isFinite,
                  sample.isFinite,
                  actionValue.isFinite,
                  transformedActionEvidence.isFinite else {
                throw VerificationError.nonFiniteDistributionValue(index: index)
            }
            let standardDeviation = exp(logStandardDeviation)
            guard standardDeviation.isFinite, standardDeviation > 0 else {
                throw VerificationError.invalidStandardDeviation(index: index)
            }
            let baseLogProbability = -0.5 * pow((sample - mean) / standardDeviation, 2)
                - logStandardDeviation
                - 0.5 * log(2 * Double.pi)
            guard baseLogProbability.isFinite else {
                throw VerificationError.nonFiniteDistributionValue(index: index)
            }

            let transformed: Double
            let transformedMean: Double
            let logJacobian: Double
            switch behavior.distributionKinds[index] {
            case .identityGaussian:
                guard channel.transform == .identity,
                      channel.lowerBound == nil,
                      channel.upperBound == nil else {
                    throw VerificationError.distributionSpaceMismatch(index: index)
                }
                transformed = sample
                transformedMean = mean
                logJacobian = 0
            case .affineTanhGaussian:
                let bounds = try validatedBounds(channel: channel, expectedTransform: .affineTanh, index: index)
                let squashed = tanh(sample)
                transformed = bounds.lower + ((squashed + 1) * 0.5 * bounds.span)
                transformedMean = bounds.lower + ((tanh(mean) + 1) * 0.5 * bounds.span)
                let logTanhDerivative = 2 * (log(2) - sample - softplus(-2 * sample))
                logJacobian = log(bounds.span * 0.5) + logTanhDerivative
            case .affineSigmoidGaussian:
                let bounds = try validatedBounds(channel: channel, expectedTransform: .affineSigmoid, index: index)
                let sigmoid = stableSigmoid(sample)
                transformed = bounds.lower + sigmoid * bounds.span
                transformedMean = bounds.lower + stableSigmoid(mean) * bounds.span
                logJacobian = log(bounds.span) - softplus(-sample) - softplus(sample)
            }
            guard transformed.isFinite, transformedMean.isFinite, logJacobian.isFinite else {
                throw VerificationError.nonFiniteDistributionValue(index: index)
            }
            guard approximatelyEqual(transformed, actionValue),
                  approximatelyEqual(transformed, transformedActionEvidence) else {
                throw VerificationError.transformedActionMismatch(index: index)
            }
            guard approximatelyEqual(transformedMean, transformedMeanEvidence) else {
                throw VerificationError.transformedMeanMismatch(index: index)
            }
            logProbability += baseLogProbability - logJacobian
            guard logProbability.isFinite else {
                throw VerificationError.nonFiniteDistributionValue(index: index)
            }
        }

        guard behavior.logProbability.isFinite else {
            throw VerificationError.nonFiniteLogProbability
        }
        guard approximatelyEqual(logProbability, behavior.logProbability) else {
            throw VerificationError.logProbabilityMismatch(
                expected: logProbability,
                actual: behavior.logProbability
            )
        }
    }

    private func validatedBounds(
        channel: KuyuDatasetDescriptor.Channel,
        expectedTransform: KuyuDatasetDescriptor.ChannelTransform,
        index: Int
    ) throws -> (lower: Double, span: Double) {
        guard channel.transform == expectedTransform,
              let lower = channel.lowerBound,
              let upper = channel.upperBound,
              lower.isFinite,
              upper.isFinite,
              lower < upper else {
            throw VerificationError.distributionSpaceMismatch(index: index)
        }
        let span = upper - lower
        guard span.isFinite else {
            throw VerificationError.distributionSpaceMismatch(index: index)
        }
        return (lower, span)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= tolerance * max(1, abs(lhs), abs(rhs))
    }

    private func stableSigmoid(_ value: Double) -> Double {
        value >= 0
            ? 1 / (1 + exp(-value))
            : exp(value) / (1 + exp(value))
    }

    private func softplus(_ value: Double) -> Double {
        max(value, 0) + log1p(exp(-abs(value)))
    }
}
