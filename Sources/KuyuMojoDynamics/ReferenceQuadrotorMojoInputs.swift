import KuyuCore
import KuyuPhysics

struct ReferenceQuadrotorMojoInputs {
    static func availableValues(
        program: CanonicalDynamicsProgram,
        state: ReferenceQuadrotorState,
        parameters: ReferenceQuadrotorParameters,
        mixer: ReferenceQuadrotorMixer?,
        motorThrusts: MotorThrusts?,
        disturbances: DisturbanceState?,
        environment: WorldEnvironment?,
        force: QuadrotorGeneralizedForce?
    ) throws -> [CanonicalValueID: MojoCanonicalValue] {
        let bindings = program.content.layoutBindings
        var values: [CanonicalValueID: MojoCanonicalValue] = [:]

        try bind(&values, layoutID: bindings.state, fieldID: "position", value: .vector3(state.position))
        try bind(&values, layoutID: bindings.state, fieldID: "velocity", value: .vector3(state.velocity))
        try bind(
            &values,
            layoutID: bindings.state,
            fieldID: "orientation",
            value: .quaternion(state.orientation.vector)
        )
        try bind(
            &values,
            layoutID: bindings.state,
            fieldID: "angular_velocity",
            value: .vector3(state.angularVelocity)
        )

        let aerodynamics = parameters.aerodynamics
        try bind(&values, layoutID: bindings.parameters, fieldID: "mass", value: .scalar(parameters.mass))
        try bind(&values, layoutID: bindings.parameters, fieldID: "inertia", value: .vector3(parameters.inertiaSIMD))
        try bind(&values, layoutID: bindings.parameters, fieldID: "arm_length", value: .scalar(parameters.armLength))
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "motor_time_constant",
            value: .scalar(parameters.motorTimeConstant)
        )
        try bind(&values, layoutID: bindings.parameters, fieldID: "max_thrust", value: .scalar(parameters.maxThrust))
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "yaw_coefficient",
            value: .scalar(parameters.yawCoefficient)
        )
        try bind(&values, layoutID: bindings.parameters, fieldID: "gravity", value: .scalar(parameters.gravity))
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "drag_coefficient",
            value: .scalar(aerodynamics.dragCoefficient)
        )
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "reference_area",
            value: .scalar(aerodynamics.referenceArea)
        )
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "lift_coefficient",
            value: .scalar(aerodynamics.liftCoefficient)
        )
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "body_volume",
            value: .scalar(aerodynamics.bodyVolume)
        )
        try bind(
            &values,
            layoutID: bindings.parameters,
            fieldID: "angular_drag",
            value: .vector3(
                SIMD3<Double>(
                    aerodynamics.angularDrag.x,
                    aerodynamics.angularDrag.y,
                    aerodynamics.angularDrag.z
                )
            )
        )

        if let mixer {
            try bind(&values, layoutID: bindings.mixer, fieldID: "arm_length", value: .scalar(mixer.armLength))
            try bind(
                &values,
                layoutID: bindings.mixer,
                fieldID: "yaw_coefficient",
                value: .scalar(mixer.yawCoefficient)
            )
            try bind(
                &values,
                layoutID: bindings.mixer,
                fieldID: "spin_directions",
                value: .vector4(mixer.spinDirections)
            )
            try bind(&values, layoutID: bindings.mixer, fieldID: "layout_code", value: .scalar(0))
        }

        if let motorThrusts {
            try bind(
                &values,
                layoutID: bindings.control,
                fieldID: "motor_thrusts",
                value: .vector4(
                    SIMD4<Double>(
                        motorThrusts.f1,
                        motorThrusts.f2,
                        motorThrusts.f3,
                        motorThrusts.f4
                    )
                )
            )
        }

        if let disturbances {
            try bind(
                &values,
                layoutID: bindings.disturbance,
                fieldID: "body_torque",
                value: .vector3(disturbances.torqueBody)
            )
            try bind(
                &values,
                layoutID: bindings.disturbance,
                fieldID: "world_force",
                value: .vector3(disturbances.forceWorld)
            )
        }

        if let environment {
            try bind(&values, layoutID: bindings.environment, fieldID: "gravity", value: .scalar(environment.gravity))
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "wind_velocity_world",
                value: .vector3(
                    SIMD3<Double>(
                        environment.windVelocityWorld.x,
                        environment.windVelocityWorld.y,
                        environment.windVelocityWorld.z
                    )
                )
            )
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "air_pressure",
                value: .scalar(environment.airPressure)
            )
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "air_temperature",
                value: .scalar(environment.airTemperature)
            )
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "use_gravity",
                value: .scalar(environment.usage.useGravity ? 1 : 0)
            )
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "use_wind",
                value: .scalar(environment.usage.useWind ? 1 : 0)
            )
            try bind(
                &values,
                layoutID: bindings.environment,
                fieldID: "use_atmosphere",
                value: .scalar(environment.usage.useAtmosphere ? 1 : 0)
            )
        }

        if let force {
            try bind(
                &values,
                layoutID: bindings.generalizedForce,
                fieldID: "body_force",
                value: .vector3(force.bodyForce)
            )
            try bind(
                &values,
                layoutID: bindings.generalizedForce,
                fieldID: "body_torque",
                value: .vector3(force.bodyTorque)
            )
            try bind(
                &values,
                layoutID: bindings.generalizedForce,
                fieldID: "world_force",
                value: .vector3(force.worldForce)
            )
        }
        return values
    }

    static func requiredValues(
        for graph: MojoCompiledGraph,
        available: [CanonicalValueID: MojoCanonicalValue]
    ) throws -> [CanonicalValueID: MojoCanonicalValue] {
        var required: [CanonicalValueID: MojoCanonicalValue] = [:]
        for binding in graph.inputs {
            guard let value = available[binding.valueID] else {
                throw MojoProgramExecutionError.missingInput(binding.valueID)
            }
            required[binding.valueID] = value
        }
        return required
    }

    private static func bind(
        _ values: inout [CanonicalValueID: MojoCanonicalValue],
        layoutID: String,
        fieldID: String,
        value: MojoCanonicalValue
    ) throws {
        values[try CanonicalValueID("\(layoutID).\(fieldID)")] = value
    }
}
