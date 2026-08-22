from std.math import sqrt
from std.memory import Pointer
from std.utils.numerics import isfinite


def _valid_range(offset: Int, count: Int, limit: Int) -> Bool:
    if offset < 0 or count < 0 or offset > limit:
        return False
    return count <= limit - offset


def _cross_component[
    dtype: DType, origin: MutOrigin
](
    values: Pointer[Scalar[dtype], origin],
    lhs_offset: Int,
    rhs_offset: Int,
    component: Int,
) -> Scalar[dtype]:
    if component == 0:
        return (
            values[unsafe_offset=lhs_offset + 1]
            * values[unsafe_offset=rhs_offset + 2]
            - values[unsafe_offset=lhs_offset + 2]
            * values[unsafe_offset=rhs_offset + 1]
        )
    if component == 1:
        return (
            values[unsafe_offset=lhs_offset + 2]
            * values[unsafe_offset=rhs_offset]
            - values[unsafe_offset=lhs_offset]
            * values[unsafe_offset=rhs_offset + 2]
        )
    return (
        values[unsafe_offset=lhs_offset] * values[unsafe_offset=rhs_offset + 1]
        - values[unsafe_offset=lhs_offset + 1]
        * values[unsafe_offset=rhs_offset]
    )


def _execute_graph_plan[
    dtype: DType,
    plan_origin: ImmOrigin,
    runtime_origin: ImmOrigin,
    output_origin: MutOrigin,
](
    plan: Pointer[Scalar[dtype], plan_origin],
    plan_count: UInt64,
    runtime_input: Pointer[Scalar[dtype], runtime_origin],
    runtime_input_count: UInt64,
    output: Pointer[Scalar[dtype], output_origin],
    output_count: UInt64,
    expected_magic: Int,
) -> Int32:
    var encoded_plan_count = Int(plan_count)
    var provided_runtime_input_count = Int(runtime_input_count)
    var workspace_count = Int(output_count)
    if encoded_plan_count < 8:
        return Int32(1)

    var magic = Int(plan[unsafe_offset=0])
    var schema = Int(plan[unsafe_offset=1])
    var instruction_count = Int(plan[unsafe_offset=2])
    var declared_workspace_count = Int(plan[unsafe_offset=3])
    var declared_runtime_input_count = Int(plan[unsafe_offset=4])
    var instruction_width = Int(plan[unsafe_offset=5])
    var instruction_start = Int(plan[unsafe_offset=6])
    var runtime_start = Int(plan[unsafe_offset=7])

    if magic != expected_magic or schema != 1:
        return Int32(1)
    if instruction_count < 0 or declared_runtime_input_count < 0:
        return Int32(1)
    if instruction_width != 16 or instruction_start != 8:
        return Int32(1)
    if (
        runtime_start
        != instruction_start + instruction_count * instruction_width
    ):
        return Int32(1)
    if encoded_plan_count != runtime_start:
        return Int32(1)
    if declared_runtime_input_count != provided_runtime_input_count:
        return Int32(1)
    if declared_workspace_count != workspace_count or workspace_count <= 0:
        return Int32(2)
    if declared_runtime_input_count > workspace_count:
        return Int32(2)

    for index in range(workspace_count):
        output[unsafe_offset=index] = Scalar[dtype](0)
    for index in range(declared_runtime_input_count):
        var value = runtime_input[unsafe_offset=index]
        if not isfinite(value):
            return Int32(5)
        output[unsafe_offset=index] = value

    for instruction_index in range(instruction_count):
        var base = instruction_start + instruction_index * instruction_width
        var opcode = Int(plan[unsafe_offset=base])
        var result_offset = Int(plan[unsafe_offset=base + 1])
        var result_count = Int(plan[unsafe_offset=base + 2])
        var operand_count = Int(plan[unsafe_offset=base + 3])
        var operand0_offset = Int(plan[unsafe_offset=base + 4])
        var operand0_count = Int(plan[unsafe_offset=base + 5])
        var operand1_offset = Int(plan[unsafe_offset=base + 6])
        var operand1_count = Int(plan[unsafe_offset=base + 7])
        var operand2_offset = Int(plan[unsafe_offset=base + 8])
        var operand2_count = Int(plan[unsafe_offset=base + 9])
        var component_index = Int(plan[unsafe_offset=base + 10])
        var constant_count = Int(plan[unsafe_offset=base + 11])

        if not _valid_range(result_offset, result_count, workspace_count):
            return Int32(3)
        if result_count <= 0 or operand_count < 0 or operand_count > 3:
            return Int32(3)
        if constant_count < 0 or constant_count > 4:
            return Int32(3)
        if operand_count > 0 and not _valid_range(
            operand0_offset, operand0_count, workspace_count
        ):
            return Int32(3)
        if operand_count > 1 and not _valid_range(
            operand1_offset, operand1_count, workspace_count
        ):
            return Int32(3)
        if operand_count > 2 and not _valid_range(
            operand2_offset, operand2_count, workspace_count
        ):
            return Int32(3)

        if opcode == 0:
            if operand_count != 0 or constant_count != result_count:
                return Int32(3)
            for component in range(result_count):
                output[unsafe_offset=result_offset + component] = plan[
                    unsafe_offset=base + 12 + component
                ]
        elif opcode == 1 or opcode == 2:
            if (
                operand_count != 2
                or operand0_count != result_count
                or operand1_count != result_count
            ):
                return Int32(3)
            for component in range(result_count):
                var lhs = output[unsafe_offset=operand0_offset + component]
                var rhs = output[unsafe_offset=operand1_offset + component]
                if opcode == 1:
                    output[unsafe_offset=result_offset + component] = lhs + rhs
                else:
                    output[unsafe_offset=result_offset + component] = lhs - rhs
        elif opcode == 3:
            if operand_count != 2:
                return Int32(3)
            if (operand0_count != 1 and operand0_count != result_count) or (
                operand1_count != 1 and operand1_count != result_count
            ):
                return Int32(3)
            for component in range(result_count):
                var lhs_index = operand0_offset
                if operand0_count != 1:
                    lhs_index += component
                var rhs_index = operand1_offset
                if operand1_count != 1:
                    rhs_index += component
                output[unsafe_offset=result_offset + component] = (
                    output[unsafe_offset=lhs_index]
                    * output[unsafe_offset=rhs_index]
                )
        elif opcode == 4 or opcode == 6:
            if (
                operand_count != 2
                or result_count != 3
                or operand0_count != 3
                or operand1_count != 3
            ):
                return Int32(3)
            for component in range(3):
                var lhs = output[unsafe_offset=operand0_offset + component]
                var rhs = output[unsafe_offset=operand1_offset + component]
                if opcode == 6 and rhs == 0:
                    return Int32(4)
                if opcode == 4:
                    output[unsafe_offset=result_offset + component] = lhs * rhs
                else:
                    output[unsafe_offset=result_offset + component] = lhs / rhs
        elif opcode == 5:
            if (
                operand_count != 2
                or operand0_count != result_count
                or operand1_count != 1
            ):
                return Int32(3)
            var denominator = output[unsafe_offset=operand1_offset]
            if denominator == 0:
                return Int32(4)
            for component in range(result_count):
                output[unsafe_offset=result_offset + component] = (
                    output[unsafe_offset=operand0_offset + component]
                    / denominator
                )
        elif opcode == 7:
            if operand_count != 1 or operand0_count != result_count:
                return Int32(3)
            for component in range(result_count):
                output[unsafe_offset=result_offset + component] = -output[
                    unsafe_offset=operand0_offset + component
                ]
        elif opcode == 8:
            if (
                operand_count != 1
                or result_count != 1
                or component_index < 0
                or component_index >= operand0_count
            ):
                return Int32(3)
            output[unsafe_offset=result_offset] = output[
                unsafe_offset=operand0_offset + component_index
            ]
        elif opcode == 9:
            if (
                operand_count != 3
                or result_count != 3
                or operand0_count != 1
                or operand1_count != 1
                or operand2_count != 1
            ):
                return Int32(3)
            output[unsafe_offset=result_offset] = output[
                unsafe_offset=operand0_offset
            ]
            output[unsafe_offset=result_offset + 1] = output[
                unsafe_offset=operand1_offset
            ]
            output[unsafe_offset=result_offset + 2] = output[
                unsafe_offset=operand2_offset
            ]
        elif opcode == 10:
            if (
                operand_count != 2
                or result_count != 3
                or operand0_count != 3
                or operand1_count != 3
            ):
                return Int32(3)
            for component in range(3):
                output[
                    unsafe_offset=result_offset + component
                ] = _cross_component[dtype](
                    output,
                    operand0_offset,
                    operand1_offset,
                    component,
                )
        elif opcode == 11 or opcode == 12:
            if operand_count != 1 or operand0_count != 3:
                return Int32(3)
            var x = output[unsafe_offset=operand0_offset]
            var y = output[unsafe_offset=operand0_offset + 1]
            var z = output[unsafe_offset=operand0_offset + 2]
            var length = sqrt(x * x + y * y + z * z)
            if opcode == 11:
                if result_count != 1:
                    return Int32(3)
                output[unsafe_offset=result_offset] = length
            else:
                if result_count != 3:
                    return Int32(3)
                if length == 0:
                    for component in range(3):
                        output[
                            unsafe_offset=result_offset + component
                        ] = Scalar[dtype](0)
                else:
                    output[unsafe_offset=result_offset] = x / length
                    output[unsafe_offset=result_offset + 1] = y / length
                    output[unsafe_offset=result_offset + 2] = z / length
        elif opcode == 13 or opcode == 14:
            if (
                operand_count != 2
                or result_count != 3
                or operand0_count != 4
                or operand1_count != 3
            ):
                return Int32(3)
            var qx = output[unsafe_offset=operand0_offset]
            var qy = output[unsafe_offset=operand0_offset + 1]
            var qz = output[unsafe_offset=operand0_offset + 2]
            var qw = output[unsafe_offset=operand0_offset + 3]
            var vx = output[unsafe_offset=operand1_offset]
            var vy = output[unsafe_offset=operand1_offset + 1]
            var vz = output[unsafe_offset=operand1_offset + 2]
            var tx = Scalar[dtype](2) * (qy * vz - qz * vy)
            var ty = Scalar[dtype](2) * (qz * vx - qx * vz)
            var tz = Scalar[dtype](2) * (qx * vy - qy * vx)
            if opcode == 13:
                output[unsafe_offset=result_offset] = (
                    vx + qw * tx + (qy * tz - qz * ty)
                )
                output[unsafe_offset=result_offset + 1] = (
                    vy + qw * ty + (qz * tx - qx * tz)
                )
                output[unsafe_offset=result_offset + 2] = (
                    vz + qw * tz + (qx * ty - qy * tx)
                )
            else:
                output[unsafe_offset=result_offset] = (
                    vx - qw * tx + (qy * tz - qz * ty)
                )
                output[unsafe_offset=result_offset + 1] = (
                    vy - qw * ty + (qz * tx - qx * tz)
                )
                output[unsafe_offset=result_offset + 2] = (
                    vz - qw * tz + (qx * ty - qy * tx)
                )
        elif opcode == 15:
            if (
                operand_count != 2
                or result_count != 4
                or operand0_count != 4
                or operand1_count != 3
            ):
                return Int32(3)
            var qx = output[unsafe_offset=operand0_offset]
            var qy = output[unsafe_offset=operand0_offset + 1]
            var qz = output[unsafe_offset=operand0_offset + 2]
            var qw = output[unsafe_offset=operand0_offset + 3]
            var wx = output[unsafe_offset=operand1_offset]
            var wy = output[unsafe_offset=operand1_offset + 1]
            var wz = output[unsafe_offset=operand1_offset + 2]
            output[unsafe_offset=result_offset] = Scalar[dtype](0.5) * (
                qw * wx + qy * wz - qz * wy
            )
            output[unsafe_offset=result_offset + 1] = Scalar[dtype](0.5) * (
                qw * wy + qz * wx - qx * wz
            )
            output[unsafe_offset=result_offset + 2] = Scalar[dtype](0.5) * (
                qw * wz + qx * wy - qy * wx
            )
            output[unsafe_offset=result_offset + 3] = Scalar[dtype](-0.5) * (
                qx * wx + qy * wy + qz * wz
            )
        else:
            return Int32(3)

        for component in range(result_count):
            if not isfinite(output[unsafe_offset=result_offset + component]):
                return Int32(5)

    return Int32(0)


def _execute_graph[
    dtype: DType,
    input_origin: ImmOrigin,
    output_origin: MutOrigin,
](
    input: Pointer[Scalar[dtype], input_origin],
    input_count: UInt64,
    output: Pointer[Scalar[dtype], output_origin],
    output_count: UInt64,
    expected_magic: Int,
) -> Int32:
    var encoded_count = Int(input_count)
    if encoded_count < 8:
        return Int32(1)
    var runtime_start = Int(input[unsafe_offset=7])
    if not _valid_range(
        runtime_start, encoded_count - runtime_start, encoded_count
    ):
        return Int32(1)
    return _execute_graph_plan[dtype](
        input,
        UInt64(runtime_start),
        input.unsafe_offset(runtime_start),
        UInt64(encoded_count - runtime_start),
        output,
        output_count,
        expected_magic,
    )


def execute_graph(
    input: Pointer[Float64, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float64, MutUntrackedOrigin],
    output_count: UInt64,
) -> Int32:
    return _execute_graph[DType.float64](
        input,
        input_count,
        output,
        output_count,
        1263883861,
    )


def execute_graph_float32(
    input: Pointer[Float32, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float32, MutUntrackedOrigin],
    output_count: UInt64,
) -> Int32:
    return _execute_graph[DType.float32](
        input,
        input_count,
        output,
        output_count,
        4937049,
    )
