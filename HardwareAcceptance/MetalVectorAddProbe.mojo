from std.gpu import global_idx
from std.math import ceildiv
from std.sys import has_accelerator

from max.gpu.host import DeviceContext


def add_kernel(
    left: Pointer[Float32, ImmutAnyOrigin],
    right: Pointer[Float32, ImmutAnyOrigin],
    output: Pointer[Float32, MutAnyOrigin],
    element_count: Int32,
):
    var index = global_idx.x
    if index < Int(element_count):
        output[unsafe_offset=index] = (
            left[unsafe_offset=index] + right[unsafe_offset=index]
        )


def main() raises:
    comptime assert has_accelerator(), "A supported accelerator is required"
    comptime element_count = 257
    comptime block_size = 64
    comptime block_count = ceildiv(element_count, block_size)

    var context = DeviceContext(api="metal")
    var left_host = context.enqueue_create_host_buffer[DType.float32](
        element_count
    )
    var right_host = context.enqueue_create_host_buffer[DType.float32](
        element_count
    )
    var output_host = context.enqueue_create_host_buffer[DType.float32](
        element_count
    )
    context.synchronize()

    for index in range(element_count):
        left_host[index] = Float32(index) * 0.5
        right_host[index] = Float32(index) * 1.5

    var left_device = context.enqueue_create_buffer[DType.float32](
        element_count
    )
    var right_device = context.enqueue_create_buffer[DType.float32](
        element_count
    )
    var output_device = context.enqueue_create_buffer[DType.float32](
        element_count
    )
    context.enqueue_copy(left_device, left_host)
    context.enqueue_copy(right_device, right_host)

    context.enqueue_function[add_kernel](
        left_device,
        right_device,
        output_device,
        Int32(element_count),
        grid_dim=block_count,
        block_dim=block_size,
    )
    context.enqueue_copy(output_host, output_device)
    context.synchronize()

    for index in range(element_count):
        var expected = Float32(index) * 2.0
        if output_host[index] != expected:
            raise Error("Metal vector-add probe produced an incorrect result")

    print("gpu_kernel_launch=ok")
    print("gpu_transfer=ok")
    print("gpu_synchronization=ok")
