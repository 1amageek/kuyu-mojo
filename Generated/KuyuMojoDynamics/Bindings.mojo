from std.memory import Pointer
from KuyuCanonicalDynamics import execute_graph as __swift_mojo_external_1653368010419799125
from KuyuCanonicalDynamics import execute_graph_float32 as __swift_mojo_external_2322419702346763180


@export("swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_static_abi_version")
def swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_static_abi_version() abi("C") -> UInt32:
    return 1


@export("swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_input_graph_identifier")
def swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_input_graph_identifier() abi("C") -> UInt64:
    return 8430527529833384517


@export("swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_has_binding")
def swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_has_binding(binding_id: UInt64) abi("C") -> UInt32:
    if binding_id == 1653368010419799125:
        return 1
    if binding_id == 2322419702346763180:
        return 1
    return 0


# Both pointers are valid only for the synchronous Swift call scope.
@export("swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_call_f32_buffer_f32_buffer_i32")
def swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_call_f32_buffer_f32_buffer_i32(
    binding_id: UInt64,
    input: Pointer[Float32, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float32, MutUntrackedOrigin],
    output_count: UInt64,
) abi("C") -> Int32:
    if binding_id == 2322419702346763180:
        return __swift_mojo_external_2322419702346763180(input, input_count, output, output_count)
    return -1


# Both Float64 pointers are valid only for the synchronous Swift call scope.
@export("swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_call_f64_buffer_f64_buffer_i32")
def swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_call_f64_buffer_f64_buffer_i32(
    binding_id: UInt64,
    input: Pointer[Float64, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float64, MutUntrackedOrigin],
    output_count: UInt64,
) abi("C") -> Int32:
    if binding_id == 1653368010419799125:
        return __swift_mojo_external_1653368010419799125(input, input_count, output, output_count)
    return -1
