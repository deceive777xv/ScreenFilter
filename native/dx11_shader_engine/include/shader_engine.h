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

/// Compile an HLSL pixel shader for sandbox preview rendering.
/// Does not replace the fullscreen filter shader.
SHADER_API int32_t engine_compile_preview_shader(
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

/// Render one sandbox preview frame to the internal render target.
/// @param width   Render target width in pixels.
/// @param height  Render target height in pixels.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_render_preview_frame(int32_t width, int32_t height);

/// Copy the rendered frame data into a caller-provided RGBA buffer.
/// @param out_pixels  Caller-allocated buffer (width * height * 4 bytes).
/// @param buffer_size Size of the buffer in bytes.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_get_frame_pixels(uint8_t* out_pixels, int32_t buffer_size);

/// Show the native GPU overlay window and prepare it for rendering.
/// @param width   Overlay render width in physical pixels.
/// @param height  Overlay render height in physical pixels.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_show_overlay(int32_t width, int32_t height);

/// Render the current shader directly into the native GPU overlay.
/// @param width   Overlay render width in physical pixels.
/// @param height  Overlay render height in physical pixels.
/// @return 0 on success, non-zero on failure.
SHADER_API int32_t engine_render_overlay_frame(int32_t width, int32_t height);

/// Update global fullscreen visual controls applied by the overlay compositor.
/// @param opacity    Overall filter opacity, clamped to 0..1.
/// @param brightness Brightness adjustment, clamped to -1..1.
SHADER_API void engine_set_filter_visuals(float opacity, float brightness);

/// Select a built-in screen post-processing effect.
/// effect: 0 = none, 1 = mosaic.
/// intensity controls effect strength; for mosaic it is the block size in pixels.
SHADER_API void engine_set_post_process_effect(int32_t effect, float intensity);

/// Hide and release native overlay resources.
SHADER_API void engine_hide_overlay();

/// Returns 1 when the native overlay window is active, otherwise 0.
SHADER_API int32_t engine_is_overlay_active();

/// Upload a polygon mask for native overlay composition.
/// Points are flattened physical-pixel xy pairs. Each region count is a number
/// of points, not float values.
SHADER_API int32_t engine_set_region_mask(
    int32_t enabled,
    int32_t inverted,
    int32_t width,
    int32_t height,
    const float* points,
    const int32_t* region_point_counts,
    int32_t region_count
);

/// Release all DirectX resources.
SHADER_API void engine_shutdown();

#ifdef __cplusplus
}
#endif
