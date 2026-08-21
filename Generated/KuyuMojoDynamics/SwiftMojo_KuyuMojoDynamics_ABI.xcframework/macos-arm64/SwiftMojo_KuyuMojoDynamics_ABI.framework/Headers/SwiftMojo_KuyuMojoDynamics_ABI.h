#ifndef SWIFTMOJO_KUYUMOJODYNAMICS_ABI_H
#define SWIFTMOJO_KUYUMOJODYNAMICS_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_static_abi_version(void);
uint64_t swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_input_graph_identifier(void);
uint32_t swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_has_binding(uint64_t binding_id);
int32_t swift_mojo_f02a731c3b1b167be2708c289ebef05b89c003f83ae61bf3d3cb65b8d89601f1_call_f64_buffer_f64_buffer_i32(
    uint64_t binding_id,
    const double *input,
    uint64_t input_count,
    double *output,
    uint64_t output_count
);

#ifdef __cplusplus
}
#endif

#endif
