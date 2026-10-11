#ifndef IMAGEPRO_INPAINTING_TOOLS_H
#define IMAGEPRO_INPAINTING_TOOLS_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Input/output: premultiplied RGBA. Only nonzero coverage pixels may change.
// MI-GAN official uint8 NCHW ONNX pipeline.
// Returns zero on success; failures leave the caller's input unchanged.
int imagepro_inpaint(uint8_t *rgba, const uint8_t *coverage, size_t width, size_t height,
                     float opacity, const char *model_path,
                     const char *runtime_path, char *error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
