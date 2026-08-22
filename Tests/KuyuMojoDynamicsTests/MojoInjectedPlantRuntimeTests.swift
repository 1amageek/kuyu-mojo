import KuyuCore
import KuyuMojoCore
import KuyuMojoDynamics
import KuyuPhysics
import simd
import Testing

@Suite("Mojo-injected plant runtime")
struct MojoInjectedPlantRuntimeTests {
    @Test(
        arguments: [
            (MojoNumericType.float64, 1e-11),
            (MojoNumericType.float32, 1e-5),
        ]
    )
    func plantAndIMUMatchScalarRuntime(
        numericType: MojoNumericType,
        tolerance: Double
    ) throws {
        let parameters = ReferenceQuadrotorParameters.baseline
        let mixer = ReferenceQuadrotorMixer(
            armLength: parameters.armLength,
            yawCoefficient: parameters.yawCoefficient
        )
        let initialState = try ReferenceQuadrotorState(
            position: SIMD3<Double>(0.1, -0.2, 1.3),
            velocity: SIMD3<Double>(0.2, -0.1, 0.05),
            orientation: simd_quatd(
                angle: 0.08,
                axis: SIMD3<Double>(0, 1, 0)
            ),
            angularVelocity: SIMD3<Double>(0.03, -0.02, 0.01)
        )
        let thrusts = try MotorThrusts(
            f1: 1.2,
            f2: 1.3,
            f3: 1.1,
            f4: 1.4
        )
        let disturbances = DisturbanceState(
            torqueBody: SIMD3<Double>(0.01, -0.02, 0.03),
            forceWorld: SIMD3<Double>(0.2, -0.1, 0.05)
        )
        let scalarStore = ReferenceQuadrotorWorldStore(
            state: initialState,
            motorThrusts: thrusts,
            disturbances: disturbances
        )
        let mojoStore = ReferenceQuadrotorWorldStore(
            state: initialState,
            motorThrusts: thrusts,
            disturbances: disturbances
        )
        let timeStep = try TimeStep(delta: 0.0025)
        let mojoExecutor = try MojoScalarDynamicsExecutor(
            program: ReferenceQuadrotorCanonicalProgram.make(),
            numericType: numericType
        )
        var scalarPlant = try ReferenceQuadrotorPlantEngine(
            parameters: parameters,
            mixer: mixer,
            store: scalarStore,
            timeStep: timeStep
        )
        var mojoPlant = try ReferenceQuadrotorPlantEngine(
            parameters: parameters,
            mixer: mixer,
            store: mojoStore,
            timeStep: timeStep,
            canonicalExecutor: mojoExecutor
        )
        var scalarSensor = try sensor(
            parameters: parameters,
            mixer: mixer,
            store: scalarStore,
            timeStep: timeStep
        )
        var mojoSensor = try sensor(
            parameters: parameters,
            mixer: mixer,
            store: mojoStore,
            timeStep: timeStep,
            canonicalExecutor: mojoExecutor
        )

        for stepIndex in 1...8 {
            let time = try WorldTime(
                stepIndex: UInt64(stepIndex),
                time: Double(stepIndex) * timeStep.delta
            )
            try scalarPlant.integrate(time: time)
            try mojoPlant.integrate(time: time)
            expectStateClose(
                mojoStore.state,
                scalarStore.state,
                tolerance: tolerance
            )
            let scalarSamples = try scalarSensor.sample(time: time)
            let mojoSamples = try mojoSensor.sample(time: time)
            #expect(mojoSamples.count == scalarSamples.count)
            for (actual, expected) in zip(mojoSamples, scalarSamples) {
                #expect(actual.channelIndex == expected.channelIndex)
                #expect(actual.timestamp == expected.timestamp)
                #expect(abs(actual.value - expected.value) <= tolerance)
            }
        }
    }

    private func sensor(
        parameters: ReferenceQuadrotorParameters,
        mixer: ReferenceQuadrotorMixer,
        store: ReferenceQuadrotorWorldStore,
        timeStep: TimeStep,
        canonicalExecutor: any ReferenceQuadrotorCanonicalExecuting =
            ReferenceQuadrotorScalarDynamicsExecutor()
    ) throws -> IMU6SensorField {
        try IMU6SensorField(
            parameters: parameters,
            mixer: mixer,
            store: store,
            timeStep: timeStep,
            noiseSeed: 11,
            gyroNoiseStdDev: 0,
            gyroBias: 0,
            gyroRandomWalkSigma: 0,
            accelNoiseStdDev: 0,
            accelBias: 0,
            accelRandomWalkSigma: 0,
            canonicalExecutor: canonicalExecutor
        )
    }

    private func expectStateClose(
        _ actual: ReferenceQuadrotorState,
        _ expected: ReferenceQuadrotorState,
        tolerance: Double
    ) {
        for (actualValue, expectedValue) in zip(
            stateValues(actual),
            stateValues(expected)
        ) {
            #expect(abs(actualValue - expectedValue) <= tolerance)
        }
    }

    private func stateValues(
        _ state: ReferenceQuadrotorState
    ) -> [Double] {
        [
            state.position.x,
            state.position.y,
            state.position.z,
            state.velocity.x,
            state.velocity.y,
            state.velocity.z,
            state.orientation.vector.x,
            state.orientation.vector.y,
            state.orientation.vector.z,
            state.orientation.vector.w,
            state.angularVelocity.x,
            state.angularVelocity.y,
            state.angularVelocity.z,
        ]
    }
}
