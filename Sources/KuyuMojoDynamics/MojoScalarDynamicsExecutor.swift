import KuyuCore
import KuyuMojoCore
import KuyuPhysics

public struct MojoScalarDynamicsExecutor: ReferenceQuadrotorCanonicalExecuting, Sendable {
    public var executorVersion: String {
        compiledProgram.identity.executorVersion
    }

    public let compiledProgram: MojoCompiledDynamicsProgram
    private let graphExecutor: any MojoGraphExecuting

    public init(
        program: CanonicalDynamicsProgram,
        numericType: MojoNumericType = .float64
    ) throws {
        let graphExecutor: any MojoGraphExecuting
        switch numericType {
        case .float32:
            graphExecutor = MojoFloat32GraphExecutor()
        case .float64:
            graphExecutor = MojoFloat64GraphExecutor()
        }
        try self.init(
            program: program,
            compiler: KuyuMojoProgramCompiler(numericType: numericType),
            graphExecutor: graphExecutor
        )
    }

    public init(
        program: CanonicalDynamicsProgram,
        compiler: any MojoDynamicsProgramCompiling,
        graphExecutor: any MojoGraphExecuting
    ) throws {
        let compiledProgram = try compiler.compile(program)
        guard compiledProgram.identity.numericType
                == graphExecutor.numericType else {
            throw MojoProgramExecutionError.numericTypeMismatch(
                expected: compiledProgram.identity.numericType,
                actual: graphExecutor.numericType
            )
        }
        self.compiledProgram = compiledProgram
        self.graphExecutor = graphExecutor
    }

    public func executionIdentity(
        program: CanonicalDynamicsProgram,
        fidelity: ReferenceQuadrotorFidelity,
        mixer: ReferenceQuadrotorMixer
    ) throws -> MojoDynamicsExecutionIdentity {
        try validateProgram(program)
        let active = try canonicalTermIDs(fidelity.active)
        let worldModelTargets = try canonicalTermIDs(
            fidelity.worldModelTargets
        )
        let ignored = try canonicalTermIDs(
            fidelity.ignoredByNegligibilityPolicy
        )
        let projection = canonicalProjection(fidelity.constraint)
        guard let declaration = program.content.fidelities.first(where: {
            Set($0.active) == active
                && Set($0.worldModelTargets) == worldModelTargets
                && Set($0.ignored) == ignored
                && $0.projection == projection
        }) else {
            throw MojoProgramExecutionError.fidelityNotDeclared(
                activeTermIDs: active.map(\.rawValue).sorted(),
                projection: projection.rawValue
            )
        }
        return try MojoDynamicsExecutionIdentity(
            compiledProgram: compiledProgram.identity,
            fidelityID: declaration.id,
            constraintProjection: declaration.projection,
            controlSemantics: program.content.controlSemantics,
            mixerLayout: mixer.layout,
            mixerArmLength: mixer.armLength,
            mixerYawCoefficient: mixer.yawCoefficient,
            rotorSpinDirections: [
                mixer.spinDirections.x,
                mixer.spinDirections.y,
                mixer.spinDirections.z,
                mixer.spinDirections.w,
            ]
        )
    }

    public func generalizedForce(
        program: CanonicalDynamicsProgram,
        state: ReferenceQuadrotorState,
        parameters: ReferenceQuadrotorParameters,
        mixer: ReferenceQuadrotorMixer,
        motorThrusts: MotorThrusts,
        disturbances: DisturbanceState,
        environment: WorldEnvironment,
        activeTerms: Set<QuadrotorForceTermID>
    ) throws -> QuadrotorGeneralizedForce {
        try validateProgram(program)
        let activeCanonicalTerms = try Set(activeTerms.map(canonicalTermID))
        for term in activeTerms {
            let canonicalID = try canonicalTermID(term)
            guard compiledProgram.forceTerms[canonicalID] != nil else {
                throw MojoProgramExecutionError.unknownForceTerm(term)
            }
        }
        let available = try ReferenceQuadrotorMojoInputs.availableValues(
            program: program,
            state: state,
            parameters: parameters,
            mixer: mixer,
            motorThrusts: motorThrusts,
            disturbances: disturbances,
            environment: environment,
            force: nil
        )
        var total = QuadrotorGeneralizedForce.zero
        for termID in compiledProgram.forceTermIDs
        where activeCanonicalTerms.contains(termID) {
            guard let graph = compiledProgram.forceTerms[termID] else {
                throw MojoProgramExecutionError.compiledForceTermMissing(
                    termID
                )
            }
            let inputs = try ReferenceQuadrotorMojoInputs.requiredValues(
                for: graph,
                available: available
            )
            let outputs = try graphExecutor.execute(graph, inputs: inputs)
            total += QuadrotorGeneralizedForce(
                bodyForce: try vector3Output(
                    "body_force",
                    graph: graph,
                    outputs: outputs
                ),
                bodyTorque: try vector3Output(
                    "body_torque",
                    graph: graph,
                    outputs: outputs
                ),
                worldForce: try vector3Output(
                    "world_force",
                    graph: graph,
                    outputs: outputs
                )
            )
        }
        return total
    }

    public func derivative(
        program: CanonicalDynamicsProgram,
        state: ReferenceQuadrotorState,
        parameters: ReferenceQuadrotorParameters,
        force: QuadrotorGeneralizedForce
    ) throws -> ReferenceQuadrotorStateDerivative {
        try validateProgram(program)
        let graph = compiledProgram.derivative
        let available = try ReferenceQuadrotorMojoInputs.availableValues(
            program: program,
            state: state,
            parameters: parameters,
            mixer: nil,
            motorThrusts: nil,
            disturbances: nil,
            environment: nil,
            force: force
        )
        let outputs = try graphExecutor.execute(
            graph,
            inputs: try ReferenceQuadrotorMojoInputs.requiredValues(
                for: graph,
                available: available
            )
        )
        return ReferenceQuadrotorStateDerivative(
            position: try vector3Output(
                "position_rate",
                graph: graph,
                outputs: outputs
            ),
            velocity: try vector3Output(
                "linear_acceleration",
                graph: graph,
                outputs: outputs
            ),
            orientation: try vector4Output(
                "orientation_rate",
                graph: graph,
                outputs: outputs
            ),
            angularVelocity: try vector3Output(
                "angular_acceleration",
                graph: graph,
                outputs: outputs
            )
        )
    }

    public func observables(
        program: CanonicalDynamicsProgram,
        state: ReferenceQuadrotorState,
        parameters: ReferenceQuadrotorParameters,
        environment: WorldEnvironment,
        force: QuadrotorGeneralizedForce
    ) throws -> ReferenceQuadrotorCanonicalObservables {
        try validateProgram(program)
        let graph = compiledProgram.observables
        let available = try ReferenceQuadrotorMojoInputs.availableValues(
            program: program,
            state: state,
            parameters: parameters,
            mixer: nil,
            motorThrusts: nil,
            disturbances: nil,
            environment: environment,
            force: force
        )
        let outputs = try graphExecutor.execute(
            graph,
            inputs: try ReferenceQuadrotorMojoInputs.requiredValues(
                for: graph,
                available: available
            )
        )
        return ReferenceQuadrotorCanonicalObservables(
            angularVelocityBody: try vector3Output(
                "angular_velocity_body",
                graph: graph,
                outputs: outputs
            ),
            specificForceBody: try vector3Output(
                "specific_force_body",
                graph: graph,
                outputs: outputs
            )
        )
    }

    private func validateProgram(
        _ program: CanonicalDynamicsProgram
    ) throws {
        let expected = try CanonicalProgramDigest(
            compiledProgram.identity.programDigest
        )
        guard expected == program.digest else {
            throw MojoProgramExecutionError.programDigestMismatch(
                expected: expected,
                actual: program.digest
            )
        }
    }

    private func canonicalTermID(
        _ term: QuadrotorForceTermID
    ) throws -> CanonicalForceTermID {
        let rawValue: String
        switch term {
        case .gravity:
            rawValue = "gravity"
        case .propulsion:
            rawValue = "propulsion"
        case .thrustDensityScaling:
            rawValue = "thrust_density_scaling"
        case .disturbance:
            rawValue = "disturbance"
        case .aerodynamicDrag:
            rawValue = "aerodynamic_drag"
        case .aerodynamicLift:
            rawValue = "aerodynamic_lift"
        case .buoyancy:
            rawValue = "buoyancy"
        case .angularDrag:
            rawValue = "angular_drag"
        case .gyroscopic:
            rawValue = "gyroscopic"
        }
        return try CanonicalForceTermID(rawValue)
    }

    private func canonicalTermIDs(
        _ terms: Set<QuadrotorForceTermID>
    ) throws -> Set<CanonicalForceTermID> {
        try Set(terms.map(canonicalTermID))
    }

    private func canonicalProjection(
        _ projection: QuadrotorConstraintProjection
    ) -> CanonicalConstraintProjectionKind {
        switch projection {
        case .free:
            .identity
        case .verticalOnly:
            .referenceQuadrotorVerticalOnly
        }
    }

    private func vector3Output(
        _ outputID: String,
        graph: MojoCompiledGraph,
        outputs: [String: MojoCanonicalValue]
    ) throws -> SIMD3<Double> {
        guard case let .vector3(value) = outputs[outputID] else {
            throw MojoProgramExecutionError.invalidBackendOutput(
                graphID: graph.graphID,
                outputID: outputID
            )
        }
        return value
    }

    private func vector4Output(
        _ outputID: String,
        graph: MojoCompiledGraph,
        outputs: [String: MojoCanonicalValue]
    ) throws -> SIMD4<Double> {
        guard case let .vector4(value) = outputs[outputID] else {
            throw MojoProgramExecutionError.invalidBackendOutput(
                graphID: graph.graphID,
                outputID: outputID
            )
        }
        return value
    }
}
