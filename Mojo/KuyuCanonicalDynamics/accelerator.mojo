from std.collections import List
from std.ffi import external_call
from std.gpu import global_idx
from std.math import ceildiv
from std.memory import OpaquePointer, Pointer
from std.sys import has_accelerator, size_of

from max.gpu.host import DeviceBuffer, DeviceContext, HostBuffer

from KuyuCanonicalDynamics import _execute_graph_plan


comptime _FLOAT32_PLAN_MAGIC = 4937049
comptime _ACCELERATOR_REQUEST_MAGIC = 4937050
comptime _ACCELERATOR_REQUEST_SCHEMA = 1
comptime _ACCELERATOR_REQUEST_HEADER_COUNT = 6
comptime _EXECUTION_BLOCK_SIZE = 64
comptime _MAXIMUM_BATCH_COUNT = 4096
comptime _MAXIMUM_BUFFER_ELEMENT_COUNT = 16777216


struct AcceleratorBuffers:
    var plan_host: HostBuffer[DType.float32]
    var runtime_host: HostBuffer[DType.float32]
    var workspace_host: HostBuffer[DType.float32]
    var status_host: HostBuffer[DType.int32]
    var plan_device: DeviceBuffer[DType.float32]
    var runtime_device: DeviceBuffer[DType.float32]
    var workspace_device: DeviceBuffer[DType.float32]
    var status_device: DeviceBuffer[DType.int32]

    def __init__(
        out self,
        context: DeviceContext,
        plan_capacity: Int,
        runtime_capacity: Int,
        workspace_capacity: Int,
        status_capacity: Int,
    ) raises:
        self.plan_host = context.enqueue_create_host_buffer[DType.float32](
            plan_capacity
        )
        self.runtime_host = context.enqueue_create_host_buffer[DType.float32](
            runtime_capacity
        )
        self.workspace_host = context.enqueue_create_host_buffer[DType.float32](
            workspace_capacity
        )
        self.status_host = context.enqueue_create_host_buffer[DType.int32](
            status_capacity
        )
        self.plan_device = context.enqueue_create_buffer[DType.float32](
            plan_capacity
        )
        self.runtime_device = context.enqueue_create_buffer[DType.float32](
            runtime_capacity
        )
        self.workspace_device = context.enqueue_create_buffer[DType.float32](
            workspace_capacity
        )
        self.status_device = context.enqueue_create_buffer[DType.int32](
            status_capacity
        )


struct AcceleratorSession:
    var context: DeviceContext
    var buffers_address: UInt
    var plan_capacity: Int
    var runtime_capacity: Int
    var workspace_capacity: Int
    var status_capacity: Int

    def __init__(out self) raises:
        self.context = DeviceContext()
        self.buffers_address = 0
        self.plan_capacity = 0
        self.runtime_capacity = 0
        self.workspace_capacity = 0
        self.status_capacity = 0


def _is_exact_request_integer(
    value: Float32,
    minimum: Int,
    maximum: Int,
) -> Bool:
    var parsed = Int(value)
    return parsed >= minimum and parsed <= maximum and Float32(parsed) == value


# AcceleratorSession owns exactly one malloc allocation for its buffer set.
# The pointer never escapes this module. Every replacement deinitializes all
# HostBuffer and DeviceBuffer fields before freeing their aligned storage, and
# shutdown releases that buffer set before destroying the DeviceContext.
def _release_accelerator_buffers(
    session: Pointer[AcceleratorSession, MutUntrackedOrigin]
):
    if session[].buffers_address == 0:
        return
    var buffers = Pointer[AcceleratorBuffers, MutUntrackedOrigin](
        unsafe_from_address=Int(session[].buffers_address)
    )
    buffers.unsafe_deinit_pointee()
    external_call["free", NoneType](buffers.unsafe_bitcast[NoneType]())
    session[].buffers_address = 0
    session[].plan_capacity = 0
    session[].runtime_capacity = 0
    session[].workspace_capacity = 0
    session[].status_capacity = 0


def _ensure_accelerator_buffers(
    session: Pointer[AcceleratorSession, MutUntrackedOrigin],
    plan_count: Int,
    runtime_count: Int,
    workspace_count: Int,
    status_count: Int,
) raises -> Int32:
    if (
        session[].buffers_address != 0
        and session[].plan_capacity >= plan_count
        and session[].runtime_capacity >= runtime_count
        and session[].workspace_capacity >= workspace_count
        and session[].status_capacity >= status_count
    ):
        return 0

    _release_accelerator_buffers(session)
    var created = AcceleratorBuffers(
        session[].context,
        plan_count,
        runtime_count,
        workspace_count,
        status_count,
    )
    session[].context.synchronize()
    var address = external_call["malloc", UInt](
        UInt(size_of[AcceleratorBuffers]())
    )
    if address == 0:
        return 11
    var buffers = Pointer[AcceleratorBuffers, MutUntrackedOrigin](
        unsafe_from_address=Int(address)
    )
    buffers.unsafe_write(created^)
    session[].buffers_address = address
    session[].plan_capacity = plan_count
    session[].runtime_capacity = runtime_count
    session[].workspace_capacity = workspace_count
    session[].status_capacity = status_count
    return 0


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


def create_accelerator_session(
    request_schema: UInt32,
    requested_device: UInt32,
    requested_ordinal: UInt32,
    required_capabilities: UInt64,
    session_out: Pointer[
        OpaquePointer[MutUntrackedOrigin], MutUntrackedOrigin
    ],
    response_schema_out: Pointer[UInt32, MutUntrackedOrigin],
    actual_device_out: Pointer[UInt32, MutUntrackedOrigin],
    actual_ordinal_out: Pointer[UInt32, MutUntrackedOrigin],
    available_capabilities_out: Pointer[UInt64, MutUntrackedOrigin],
) -> Int32:
    comptime assert has_accelerator(), "A supported accelerator is required"
    if (
        request_schema != 1
        or requested_device != 1
        or requested_ordinal != 0
    ):
        return 10
    var available_capabilities = UInt64(29)
    if required_capabilities & available_capabilities != required_capabilities:
        return 12

    try:
        var created = AcceleratorSession()
        # AcceleratorSession is the sole owner of this allocation. The
        # generated Swift owner calls shutdown exactly once after all
        # synchronous borrows end. Shutdown deinitializes the DeviceContext
        # before the allocation is freed.
        var address = external_call["malloc", UInt](
            UInt(size_of[AcceleratorSession]())
        )
        if address == 0:
            return 11
        var session = Pointer[AcceleratorSession, MutUntrackedOrigin](
            unsafe_from_address=Int(address)
        )
        session.unsafe_write(created^)

        session_out[] = session.unsafe_bitcast[NoneType]()
        response_schema_out[] = 1
        actual_device_out[] = requested_device
        actual_ordinal_out[] = requested_ordinal
        available_capabilities_out[] = available_capabilities
        return 0
    except:
        return 14


def shutdown_accelerator_session(
    handle: OpaquePointer[MutUntrackedOrigin]
):
    var session = handle.unsafe_bitcast[AcceleratorSession]()
    # The generated owner permits shutdown only after every synchronous borrow
    # has returned, and every execution borrow synchronizes before returning.
    # Therefore no queued device work exists at this lifetime boundary.
    _release_accelerator_buffers(session)
    session.unsafe_deinit_pointee()
    external_call["free", NoneType](handle)


def _execute_graph_float32_accelerator_session(
    handle: OpaquePointer[MutUntrackedOrigin],
    input: Pointer[Float32, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float32, MutUntrackedOrigin],
    output_count: UInt64,
) raises -> Int32:
    if (
        input_count < UInt64(_ACCELERATOR_REQUEST_HEADER_COUNT + 8)
        or input_count > UInt64(_MAXIMUM_BUFFER_ELEMENT_COUNT)
        or output_count == 0
        or output_count > UInt64(_MAXIMUM_BUFFER_ELEMENT_COUNT)
    ):
        return 20
    if (
        not _is_exact_request_integer(
            input[unsafe_offset=0],
            _ACCELERATOR_REQUEST_MAGIC,
            _ACCELERATOR_REQUEST_MAGIC,
        )
        or not _is_exact_request_integer(
            input[unsafe_offset=1],
            _ACCELERATOR_REQUEST_SCHEMA,
            _ACCELERATOR_REQUEST_SCHEMA,
        )
        or not _is_exact_request_integer(
            input[unsafe_offset=2], 1, _MAXIMUM_BATCH_COUNT
        )
        or not _is_exact_request_integer(
            input[unsafe_offset=3], 8, _MAXIMUM_BUFFER_ELEMENT_COUNT
        )
        or not _is_exact_request_integer(
            input[unsafe_offset=4], 1, _MAXIMUM_BUFFER_ELEMENT_COUNT
        )
        or not _is_exact_request_integer(
            input[unsafe_offset=5], 1, _MAXIMUM_BUFFER_ELEMENT_COUNT
        )
    ):
        return 20

    var batch_count = Int(input[unsafe_offset=2])
    var plan_count = Int(input[unsafe_offset=3])
    var runtime_input_count = Int(input[unsafe_offset=4])
    var workspace_count = Int(input[unsafe_offset=5])
    if runtime_input_count > _MAXIMUM_BUFFER_ELEMENT_COUNT // batch_count:
        return 20
    if workspace_count > _MAXIMUM_BUFFER_ELEMENT_COUNT // batch_count:
        return 20
    var total_runtime_count = runtime_input_count * batch_count
    var total_workspace_count = workspace_count * batch_count
    if (
        plan_count
        > _MAXIMUM_BUFFER_ELEMENT_COUNT
        - _ACCELERATOR_REQUEST_HEADER_COUNT
        - total_runtime_count
    ):
        return 20
    if (
        Int(input_count)
        != _ACCELERATOR_REQUEST_HEADER_COUNT
        + plan_count
        + total_runtime_count
        or Int(output_count) != total_workspace_count
    ):
        return 20

    var plan = input.unsafe_offset(_ACCELERATOR_REQUEST_HEADER_COUNT)
    if (
        not _is_exact_request_integer(
            plan[unsafe_offset=0], _FLOAT32_PLAN_MAGIC, _FLOAT32_PLAN_MAGIC
        )
        or not _is_exact_request_integer(
            plan[unsafe_offset=3], workspace_count, workspace_count
        )
        or not _is_exact_request_integer(
            plan[unsafe_offset=4], runtime_input_count, runtime_input_count
        )
        or not _is_exact_request_integer(
            plan[unsafe_offset=7], plan_count, plan_count
        )
    ):
        return 20
    var runtime_inputs = plan.unsafe_offset(plan_count)
    var session = handle.unsafe_bitcast[AcceleratorSession]()
    var allocation_status = _ensure_accelerator_buffers(
        session,
        plan_count,
        total_runtime_count,
        total_workspace_count,
        batch_count,
    )
    if allocation_status != 0:
        return allocation_status
    var buffers = Pointer[AcceleratorBuffers, MutUntrackedOrigin](
        unsafe_from_address=Int(session[].buffers_address)
    )

    for index in range(plan_count):
        buffers[].plan_host[index] = plan[unsafe_offset=index]
    for index in range(total_runtime_count):
        buffers[].runtime_host[index] = runtime_inputs[unsafe_offset=index]
    session[].context.enqueue_copy(
        buffers[].plan_device,
        buffers[].plan_host,
    )
    session[].context.enqueue_copy(
        buffers[].runtime_device,
        buffers[].runtime_host,
    )
    var block_count = ceildiv(batch_count, _EXECUTION_BLOCK_SIZE)
    session[].context.enqueue_function[
        execute_graph_float32_accelerator_kernel
    ](
        buffers[].plan_device,
        Int32(plan_count),
        buffers[].runtime_device,
        Int32(runtime_input_count),
        buffers[].workspace_device,
        Int32(workspace_count),
        buffers[].status_device,
        Int32(batch_count),
        grid_dim=block_count,
        block_dim=_EXECUTION_BLOCK_SIZE,
    )
    session[].context.enqueue_copy(
        buffers[].workspace_host,
        buffers[].workspace_device,
    )
    session[].context.enqueue_copy(
        buffers[].status_host,
        buffers[].status_device,
    )
    session[].context.synchronize()
    for index in range(batch_count):
        var status = buffers[].status_host[index]
        if status != 0:
            return status
    for index in range(total_workspace_count):
        output[unsafe_offset=index] = buffers[].workspace_host[index]
    return 0


def execute_graph_float32_accelerator_session(
    handle: OpaquePointer[MutUntrackedOrigin],
    input: Pointer[Float32, ImmUntrackedOrigin],
    input_count: UInt64,
    output: Pointer[Float32, MutUntrackedOrigin],
    output_count: UInt64,
) -> Int32:
    try:
        return _execute_graph_float32_accelerator_session(
            handle,
            input,
            input_count,
            output,
            output_count,
        )
    except:
        return 21
