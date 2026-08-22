from std.collections import List
from std.gpu import global_idx
from std.math import ceildiv
from std.sys import has_accelerator

from max.gpu.host import DeviceContext

from KuyuCanonicalDynamics import _execute_graph_plan


comptime _FLOAT32_PLAN_MAGIC = 4937049
comptime _EXECUTION_BLOCK_SIZE = 64
comptime _MAXIMUM_BATCH_COUNT = 4096
comptime _MAXIMUM_BUFFER_ELEMENT_COUNT = 16777216


def execute_graph_float32_accelerator_kernel(
    plan: Pointer[Float32, ImmutAnyOrigin],
    plan_count: Int32,
    runtime_inputs: Pointer[Float32, ImmutAnyOrigin],
    runtime_input_count: Int32,
    workspaces: Pointer[Float32, MutAnyOrigin],
    workspace_count: Int32,
    statuses: Pointer[Int32, MutAnyOrigin],
    batch_count: Int32,
):
    var batch_index = global_idx.x
    if batch_index < Int(batch_count):
        var runtime_input = runtime_inputs.unsafe_offset(
            batch_index * Int(runtime_input_count)
        )
        var workspace = workspaces.unsafe_offset(
            batch_index * Int(workspace_count)
        )
        statuses[unsafe_offset=batch_index] = _execute_graph_plan[
            DType.float32
        ](
            plan,
            UInt64(plan_count),
            runtime_input,
            UInt64(runtime_input_count),
            workspace,
            UInt64(workspace_count),
            _FLOAT32_PLAN_MAGIC,
        )


def execute_graph_float32_accelerator(
    plan: List[Float32],
    runtime_inputs: List[Float32],
    workspace_count: Int,
    batch_count: Int,
) raises -> Tuple[List[Float32], List[Int32]]:
    comptime assert has_accelerator(), "A supported accelerator is required"
    if len(plan) < 8 or len(plan) > _MAXIMUM_BUFFER_ELEMENT_COUNT:
        raise Error(
            "canonical plan element count is outside the supported range"
        )
    if batch_count <= 0 or batch_count > _MAXIMUM_BATCH_COUNT:
        raise Error(
            "canonical graph batch count is outside the supported range"
        )
    if workspace_count <= 0 or workspace_count > _MAXIMUM_BUFFER_ELEMENT_COUNT:
        raise Error(
            "canonical workspace element count is outside the supported range"
        )
    if len(runtime_inputs) == 0 or len(runtime_inputs) % batch_count != 0:
        raise Error("canonical runtime input batch shape is invalid")
    var runtime_input_count = len(runtime_inputs) // batch_count
    if runtime_input_count > _MAXIMUM_BUFFER_ELEMENT_COUNT:
        raise Error(
            "canonical runtime input element count is outside the supported"
            " range"
        )
    if workspace_count > _MAXIMUM_BUFFER_ELEMENT_COUNT // batch_count:
        raise Error("canonical workspace batch shape is too large")
    var total_workspace_count = workspace_count * batch_count

    var context = DeviceContext()
    var plan_host = context.enqueue_create_host_buffer[DType.float32](len(plan))
    var runtime_host = context.enqueue_create_host_buffer[DType.float32](
        len(runtime_inputs)
    )
    var workspace_host = context.enqueue_create_host_buffer[DType.float32](
        total_workspace_count
    )
    var status_host = context.enqueue_create_host_buffer[DType.int32](
        batch_count
    )
    context.synchronize()

    for index in range(len(plan)):
        plan_host[index] = plan[index]
    for index in range(len(runtime_inputs)):
        runtime_host[index] = runtime_inputs[index]

    var plan_device = context.enqueue_create_buffer[DType.float32](len(plan))
    var runtime_device = context.enqueue_create_buffer[DType.float32](
        len(runtime_inputs)
    )
    var workspace_device = context.enqueue_create_buffer[DType.float32](
        total_workspace_count
    )
    var status_device = context.enqueue_create_buffer[DType.int32](batch_count)
    context.enqueue_copy(plan_device, plan_host)
    context.enqueue_copy(runtime_device, runtime_host)

    var block_count = ceildiv(batch_count, _EXECUTION_BLOCK_SIZE)
    context.enqueue_function[execute_graph_float32_accelerator_kernel](
        plan_device,
        Int32(len(plan)),
        runtime_device,
        Int32(runtime_input_count),
        workspace_device,
        Int32(workspace_count),
        status_device,
        Int32(batch_count),
        grid_dim=block_count,
        block_dim=_EXECUTION_BLOCK_SIZE,
    )
    context.enqueue_copy(workspace_host, workspace_device)
    context.enqueue_copy(status_host, status_device)
    context.synchronize()

    var workspaces = List[Float32](capacity=total_workspace_count)
    for index in range(total_workspace_count):
        workspaces.append(workspace_host[index])
    var statuses = List[Int32](capacity=batch_count)
    for index in range(batch_count):
        statuses.append(status_host[index])
    return workspaces^, statuses^
