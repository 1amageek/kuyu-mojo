import Foundation
import KuyuCore
import KuyuMojoCore
import KuyuPhysics
import KuyuMojoDynamics
import simd
import Testing

@Suite("Mojo CPU performance")
struct MojoScalarDynamicsPerformanceTests {
    @Test(.timeLimit(.minutes(1)))
    func canonicalRK4SustainsRealTimeControlBudget() throws {
        let parameters = ReferenceQuadrotorParameters.baseline
        let program = try ReferenceQuadrotorCanonicalProgram.make()
        let integrator = ReferenceQuadrotorCanonicalIntegrator()
        let thrusts = try MotorThrusts(f1: 1.3, f2: 1.4, f3: 1.5, f4: 1.6)
        for numericType in [MojoNumericType.float32, .float64] {
            let model = ReferenceQuadrotorPhysicsModel(
                parameters: parameters,
                mixer: ReferenceQuadrotorMixer(
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient
                ),
                program: program,
                executor: try MojoScalarDynamicsExecutor(
                    program: program,
                    numericType: numericType
                )
            )
            var state = try ReferenceQuadrotorState(
                position: .zero,
                velocity: .zero,
                orientation: simd_quatd(
                    angle: 0,
                    axis: SIMD3<Double>(0, 0, 1)
                ),
                angularVelocity: .zero
            )

            for _ in 0..<5 {
                state = try integrator.step(
                    state: state,
                    model: model,
                    motorThrusts: thrusts,
                    disturbances: .zero,
                    fidelity: .full,
                    delta: 0.0025
                )
            }

            let stepCount = 200
            let started = Date()
            for _ in 0..<stepCount {
                state = try integrator.step(
                    state: state,
                    model: model,
                    motorThrusts: thrusts,
                    disturbances: .zero,
                    fidelity: .full,
                    delta: 0.0025
                )
            }
            let seconds = max(
                Date().timeIntervalSince(started),
                Double.leastNonzeroMagnitude
            )
            let stepsPerSecond = Double(stepCount) / seconds
            print(
                "Kuyu Mojo CPU \(numericType.rawValue) RK4: "
                    + "\(stepsPerSecond) steps/s"
            )

            if ProcessInfo.processInfo.environment[
                "KUYU_MOJO_STRICT_PERFORMANCE_BUDGETS"
            ] == "1" {
                #expect(stepsPerSecond >= 400)
            }
        }
    }
}
