import KuyuCore
import KuyuMojoCore
import KuyuPhysics
@testable import KuyuMojoDynamics
import simd
import Testing

@Suite("Mojo CPU differential dynamics")
struct MojoScalarDynamicsDifferentialTests {
    @Test(.timeLimit(.minutes(1)))
    func matchesForceDerivativeAndObservableReferenceTraces() throws {
        let fixture = try Fixture()
        let reference = ReferenceQuadrotorScalarDynamicsExecutor()
        for numericType in [MojoNumericType.float32, .float64] {
            var forceResidual = ResidualEnvelope()
            var derivativeResidual = ResidualEnvelope()
            var observableResidual = ResidualEnvelope()
            let mojo = try MojoScalarDynamicsExecutor(
                program: fixture.program,
                numericType: numericType
            )

            let fullIdentity = try mojo.executionIdentity(
                program: fixture.program,
                fidelity: .full,
                mixer: fixture.mixer
            )
            #expect(fullIdentity.compiledProgram.numericType == numericType)
            #expect(fullIdentity.fidelityID == "full")
            #expect(fullIdentity.constraintProjection == .identity)
            #expect(fullIdentity.controlSemantics == .realizedMotorThrust)
            #expect(fullIdentity.mixerLayout == .plus)
            #expect(fullIdentity.rotorSpinDirections == [1, -1, 1, -1])
            let tolerances = ReferenceQuadrotorMojoParityContract.tolerances(
                for: numericType
            )

            for fidelity in [ReferenceQuadrotorFidelity.full, .singleProp] {
                let expectedForce = try reference.generalizedForce(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    mixer: fixture.mixer,
                    motorThrusts: fixture.thrusts,
                    disturbances: fixture.disturbances,
                    environment: fixture.environment,
                    activeTerms: fidelity.active
                )
                let actualForce = try mojo.generalizedForce(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    mixer: fixture.mixer,
                    motorThrusts: fixture.thrusts,
                    disturbances: fixture.disturbances,
                    environment: fixture.environment,
                    activeTerms: fidelity.active
                )
                assertForceClose(
                    actualForce,
                    expectedForce,
                    tolerance: tolerances.generalizedForce
                )
                forceResidual.record(actualForce, reference: expectedForce)

                let expectedDerivative = try reference.derivative(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    force: expectedForce
                )
                let actualDerivative = try mojo.derivative(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    force: actualForce
                )
                assertDerivativeClose(
                    actualDerivative,
                    expectedDerivative,
                    tolerance: tolerances.derivative
                )
                derivativeResidual.record(
                    actualDerivative,
                    reference: expectedDerivative
                )

                let expectedObservables = try reference.observables(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    environment: fixture.environment,
                    force: expectedForce
                )
                let actualObservables = try mojo.observables(
                    program: fixture.program,
                    state: fixture.state,
                    parameters: fixture.parameters,
                    environment: fixture.environment,
                    force: actualForce
                )
                assertVectorClose(
                    actualObservables.angularVelocityBody,
                    expectedObservables.angularVelocityBody,
                    tolerance: tolerances.observables
                )
                assertVectorClose(
                    actualObservables.specificForceBody,
                    expectedObservables.specificForceBody,
                    tolerance: tolerances.observables
                )
                observableResidual.record(
                    actualObservables.angularVelocityBody,
                    reference: expectedObservables.angularVelocityBody
                )
                observableResidual.record(
                    actualObservables.specificForceBody,
                    reference: expectedObservables.specificForceBody
                )
            }
            if numericType == .float32 {
                print("Kuyu Mojo CPU Float32 force residual: \(forceResidual)")
                print("Kuyu Mojo CPU Float32 derivative residual: \(derivativeResidual)")
                print("Kuyu Mojo CPU Float32 observable residual: \(observableResidual)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matchesReferenceRK4TracesAndProjectionBoundaries() throws {
        let fixture = try Fixture()
        let referenceModel = ReferenceQuadrotorPhysicsModel(
            parameters: fixture.parameters,
            mixer: fixture.mixer,
            environment: fixture.environment,
            program: fixture.program
        )
        let integrator = ReferenceQuadrotorCanonicalIntegrator()
        for numericType in [MojoNumericType.float32, .float64] {
            var integratedStateResidual = ResidualEnvelope()
            let mojoModel = ReferenceQuadrotorPhysicsModel(
                parameters: fixture.parameters,
                mixer: fixture.mixer,
                environment: fixture.environment,
                program: fixture.program,
                executor: try MojoScalarDynamicsExecutor(
                    program: fixture.program,
                    numericType: numericType
                )
            )
            let tolerances = ReferenceQuadrotorMojoParityContract.tolerances(
                for: numericType
            )
            for fidelity in [ReferenceQuadrotorFidelity.full, .singleProp] {
                var expected = fixture.state
                var actual = fixture.state

                for _ in 0..<20 {
                    expected = try integrator.step(
                        state: expected,
                        model: referenceModel,
                        motorThrusts: fixture.thrusts,
                        disturbances: fixture.disturbances,
                        fidelity: fidelity,
                        delta: 0.0025
                    )
                    actual = try integrator.step(
                        state: actual,
                        model: mojoModel,
                        motorThrusts: fixture.thrusts,
                        disturbances: fixture.disturbances,
                        fidelity: fidelity,
                        delta: 0.0025
                    )
                }
                assertStateClose(
                    actual,
                    expected,
                    tolerance: tolerances.integratedState
                )
                integratedStateResidual.record(actual, reference: expected)
            }
            if numericType == .float32 {
                print(
                    "Kuyu Mojo CPU Float32 RK4 state residual: "
                        + "\(integratedStateResidual)"
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matchesReferenceAtZeroNormBoundary() throws {
        let fixture = try Fixture()
        let zeroState = try ReferenceQuadrotorState(
            position: .zero,
            velocity: .zero,
            orientation: simd_quatd(angle: 0, axis: SIMD3<Double>(0, 0, 1)),
            angularVelocity: .zero
        )
        let zeroEnvironment = try WorldEnvironment(
            gravity: fixture.environment.gravity,
            windVelocityWorld: Axis3(x: 0, y: 0, z: 0),
            airPressure: fixture.environment.airPressure,
            airTemperature: fixture.environment.airTemperature,
            usage: fixture.environment.usage
        )
        let reference = ReferenceQuadrotorScalarDynamicsExecutor()
        let expected = try reference.generalizedForce(
            program: fixture.program,
            state: zeroState,
            parameters: fixture.parameters,
            mixer: fixture.mixer,
            motorThrusts: fixture.thrusts,
            disturbances: .zero,
            environment: zeroEnvironment,
            activeTerms: ReferenceQuadrotorFidelity.full.active
        )
        for numericType in [MojoNumericType.float32, .float64] {
            var zeroResidual = ResidualEnvelope()
            let mojo = try MojoScalarDynamicsExecutor(
                program: fixture.program,
                numericType: numericType
            )
            let actual = try mojo.generalizedForce(
                program: fixture.program,
                state: zeroState,
                parameters: fixture.parameters,
                mixer: fixture.mixer,
                motorThrusts: fixture.thrusts,
                disturbances: .zero,
                environment: zeroEnvironment,
                activeTerms: ReferenceQuadrotorFidelity.full.active
            )
            assertForceClose(
                actual,
                expected,
                tolerance: ReferenceQuadrotorMojoParityContract.tolerances(
                    for: numericType
                ).zeroBoundary
            )
            zeroResidual.record(actual, reference: expected)
            if numericType == .float32 {
                print("Kuyu Mojo CPU Float32 zero residual: \(zeroResidual)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsProgramDigestMismatchAndCorruptPlan() throws {
        let fixture = try Fixture()
        let executor = try MojoScalarDynamicsExecutor(program: fixture.program)
        let content = fixture.program.content
        let altered = try CanonicalDynamicsProgram(
            content: CanonicalDynamicsProgramContent(
                id: "reference_quadrotor_dynamics_altered",
                schemaVersion: content.schemaVersion,
                layouts: content.layouts,
                layoutBindings: content.layoutBindings,
                controlSemantics: content.controlSemantics,
                forceTerms: content.forceTerms,
                derivativeGraph: content.derivativeGraph,
                observableGraph: content.observableGraph,
                fidelities: content.fidelities,
                integration: content.integration
            )
        )
        #expect(
            throws: MojoProgramExecutionError.programDigestMismatch(
                expected: fixture.program.digest,
                actual: altered.digest
            )
        ) {
            _ = try executor.generalizedForce(
                program: altered,
                state: fixture.state,
                parameters: fixture.parameters,
                mixer: fixture.mixer,
                motorThrusts: fixture.thrusts,
                disturbances: fixture.disturbances,
                environment: fixture.environment,
                activeTerms: ReferenceQuadrotorFidelity.full.active
            )
        }

        let compiled = executor.compiledProgram.derivative
        var corruptPlan = compiled.encodedPlan
        corruptPlan[0] = 0
        let corrupt = MojoCompiledGraph(
            identity: compiled.identity,
            graphID: compiled.graphID,
            workspaceElementCount: compiled.workspaceElementCount,
            encodedPlan: corruptPlan,
            inputs: compiled.inputs,
            outputs: compiled.outputs
        )
        let available = try ReferenceQuadrotorMojoInputs.availableValues(
            program: fixture.program,
            state: fixture.state,
            parameters: fixture.parameters,
            mixer: nil,
            motorThrusts: nil,
            disturbances: nil,
            environment: nil,
            force: .zero
        )
        #expect(throws: MojoProgramExecutionError.backendFailure(status: 1)) {
            _ = try MojoFloat64GraphExecutor().execute(
                corrupt,
                inputs: try ReferenceQuadrotorMojoInputs.requiredValues(
                    for: corrupt,
                    available: available
                )
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAnUndeclaredFidelityIdentity() throws {
        let fixture = try Fixture()
        let executor = try MojoScalarDynamicsExecutor(program: fixture.program)
        let undeclared = try ReferenceQuadrotorFidelity(
            active: [.gravity],
            ignoredByNegligibilityPolicy: Set(QuadrotorForceTermID.allCases)
                .subtracting([.gravity]),
            constraint: .free
        )
        #expect(
            throws: MojoProgramExecutionError.fidelityNotDeclared(
                activeTermIDs: ["gravity"],
                projection: "identity"
            )
        ) {
            _ = try executor.executionIdentity(
                program: fixture.program,
                fidelity: undeclared,
                mixer: fixture.mixer
            )
        }
    }
}

private struct Fixture {
    let parameters = ReferenceQuadrotorParameters.baseline
    let environment: WorldEnvironment
    let mixer: ReferenceQuadrotorMixer
    let state: ReferenceQuadrotorState
    let thrusts: MotorThrusts
    let disturbances: DisturbanceState
    let program: CanonicalDynamicsProgram

    init() throws {
        environment = try WorldEnvironment(
            gravity: 9.73,
            windVelocityWorld: Axis3(x: 0.8, y: -0.2, z: 0.15),
            airPressure: 94_500,
            airTemperature: 281,
            usage: .full
        )
        mixer = ReferenceQuadrotorMixer(
            armLength: parameters.armLength,
            yawCoefficient: parameters.yawCoefficient
        )
        state = try ReferenceQuadrotorState(
            position: SIMD3<Double>(0.1, -0.2, 1.3),
            velocity: SIMD3<Double>(1.1, -0.4, 0.3),
            orientation: simd_quatd(
                angle: 0.22,
                axis: simd_normalize(SIMD3<Double>(0.5, -1, 2))
            ),
            angularVelocity: SIMD3<Double>(0.3, -0.5, 0.2)
        )
        thrusts = try MotorThrusts(f1: 1.3, f2: 1.4, f3: 1.5, f4: 1.6)
        disturbances = DisturbanceState(
            torqueBody: SIMD3<Double>(0.01, 0.02, -0.03),
            forceWorld: SIMD3<Double>(-0.1, 0.2, 0.05)
        )
        program = try ReferenceQuadrotorCanonicalProgram.make()
    }
}

private func assertForceClose(
    _ lhs: QuadrotorGeneralizedForce,
    _ rhs: QuadrotorGeneralizedForce,
    tolerance: MojoParityTolerance
) {
    assertVectorClose(lhs.bodyForce, rhs.bodyForce, tolerance: tolerance)
    assertVectorClose(lhs.bodyTorque, rhs.bodyTorque, tolerance: tolerance)
    assertVectorClose(lhs.worldForce, rhs.worldForce, tolerance: tolerance)
}

private func assertDerivativeClose(
    _ lhs: ReferenceQuadrotorStateDerivative,
    _ rhs: ReferenceQuadrotorStateDerivative,
    tolerance: MojoParityTolerance
) {
    assertVectorClose(lhs.position, rhs.position, tolerance: tolerance)
    assertVectorClose(lhs.velocity, rhs.velocity, tolerance: tolerance)
    assertVector4Close(lhs.orientation, rhs.orientation, tolerance: tolerance)
    assertVectorClose(
        lhs.angularVelocity,
        rhs.angularVelocity,
        tolerance: tolerance
    )
}

private func assertStateClose(
    _ lhs: ReferenceQuadrotorState,
    _ rhs: ReferenceQuadrotorState,
    tolerance: MojoParityTolerance
) {
    assertVectorClose(lhs.position, rhs.position, tolerance: tolerance)
    assertVectorClose(lhs.velocity, rhs.velocity, tolerance: tolerance)
    assertVectorClose(
        lhs.angularVelocity,
        rhs.angularVelocity,
        tolerance: tolerance
    )
    assertVector4Close(
        lhs.orientation.vector,
        rhs.orientation.vector,
        tolerance: tolerance
    )
}

private func assertVectorClose(
    _ lhs: SIMD3<Double>,
    _ rhs: SIMD3<Double>,
    tolerance: MojoParityTolerance
) {
    #expect(tolerance.accepts(candidate: lhs.x, reference: rhs.x))
    #expect(tolerance.accepts(candidate: lhs.y, reference: rhs.y))
    #expect(tolerance.accepts(candidate: lhs.z, reference: rhs.z))
}

private func assertVector4Close(
    _ lhs: SIMD4<Double>,
    _ rhs: SIMD4<Double>,
    tolerance: MojoParityTolerance
) {
    #expect(tolerance.accepts(candidate: lhs.x, reference: rhs.x))
    #expect(tolerance.accepts(candidate: lhs.y, reference: rhs.y))
    #expect(tolerance.accepts(candidate: lhs.z, reference: rhs.z))
    #expect(tolerance.accepts(candidate: lhs.w, reference: rhs.w))
}

private struct ResidualEnvelope: CustomStringConvertible {
    private(set) var maximumAbsolute = 0.0
    private(set) var maximumRelative = 0.0

    var description: String {
        "absolute=\(maximumAbsolute), relative=\(maximumRelative)"
    }

    mutating func record(_ candidate: Double, reference: Double) {
        let absolute = abs(candidate - reference)
        maximumAbsolute = max(maximumAbsolute, absolute)
        if reference != 0 {
            maximumRelative = max(maximumRelative, absolute / abs(reference))
        }
    }

    mutating func record(
        _ candidate: SIMD3<Double>,
        reference: SIMD3<Double>
    ) {
        record(candidate.x, reference: reference.x)
        record(candidate.y, reference: reference.y)
        record(candidate.z, reference: reference.z)
    }

    mutating func record(
        _ candidate: SIMD4<Double>,
        reference: SIMD4<Double>
    ) {
        record(candidate.x, reference: reference.x)
        record(candidate.y, reference: reference.y)
        record(candidate.z, reference: reference.z)
        record(candidate.w, reference: reference.w)
    }

    mutating func record(
        _ candidate: QuadrotorGeneralizedForce,
        reference: QuadrotorGeneralizedForce
    ) {
        record(candidate.bodyForce, reference: reference.bodyForce)
        record(candidate.bodyTorque, reference: reference.bodyTorque)
        record(candidate.worldForce, reference: reference.worldForce)
    }

    mutating func record(
        _ candidate: ReferenceQuadrotorStateDerivative,
        reference: ReferenceQuadrotorStateDerivative
    ) {
        record(candidate.position, reference: reference.position)
        record(candidate.velocity, reference: reference.velocity)
        record(candidate.orientation, reference: reference.orientation)
        record(candidate.angularVelocity, reference: reference.angularVelocity)
    }

    mutating func record(
        _ candidate: ReferenceQuadrotorState,
        reference: ReferenceQuadrotorState
    ) {
        record(candidate.position, reference: reference.position)
        record(candidate.velocity, reference: reference.velocity)
        record(candidate.orientation.vector, reference: reference.orientation.vector)
        record(candidate.angularVelocity, reference: reference.angularVelocity)
    }
}
