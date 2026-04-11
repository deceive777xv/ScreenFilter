#pragma once

#ifdef SHADER_ENGINE_EXPORTS
#define SHADER_API __declspec(dllexport)
#else
#define SHADER_API __declspec(dllimport)
#endif

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

/// Initialize the DirectX 11 device and context.
/// Returns 0 on success, non-zero on failure.
SHADER_API int32_t engine_init();

/// Compile an HLSL pixel shader from source code.
/// @param hlsl_code    Null-terminated HLSL source code.
/// @param code_length  Length of the source code in bytes.
/// @param error_buf    Output buffer for error messages (caller-allocated).
/// @param error_buf_size  Size of the error buffer in bytes.
/// @return 0 on success, 1 on compilation error (message in error_buf), -1 on fatal error.
SHADER_API int32_t engine_compile_shader(
    const char* hlsl_code,
    int32_t code_length,
    char* error_buf,
    int32_t error_buf_size
);

/// Set uniform values for the next render call.
/// @param time          Elapsed time in seconds.
/// @param resolution_x  Viewport width.
/// @param resolution_y  Viewport height.
/// @param mouse_x       Mouse X position (normalized 0-1).
/// @param mouse_y       Mouse Y position (normalized 0-1).
/// @param accent_r      Accent color red (0-1).
/// @param accent_g      Accent color green (0-1).
/// @param accent_b      Accent color blue (0-1).
/// @param accent_a      Accent color alpha (0-1).
SHADER_API void engine_set_uniforms(
    float time,
    float resolution_x, float resolution_y,
    float mouse_x, float mouse_y,
    float accent_r, float accent_g, float accent_b, float accent_a
);

/// Render one frame to an internal render target.
/// @param width   Render target width in pixels.
/// @param height  Render target height in pixels.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_render_frame(int32_t width, int32_t height);

/// Copy the rendered frame data into a caller-provided RGBA buffer.
/// @param out_pixels  Caller-allocated buffer (width * height * 4 bytes).
/// @param buffer_size Size of the buffer in bytes.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_get_frame_pixels(uint8_t* out_pixels, int32_t buffer_size);

/// Release all DirectX resources.
SHADER_API void engine_shutdown();

#ifdef __cplusplus
}
#endif
