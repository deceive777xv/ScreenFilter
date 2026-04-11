#include "shader_engine.h"

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>

// ── Internal state ──────────────────────────────────────────────────────────
static ID3D11Device*           g_device       = nullptr;
static ID3D11DeviceContext*    g_context      = nullptr;
static ID3D11PixelShader*      g_pixelShader  = nullptr;
static ID3D11VertexShader*     g_vertexShader = nullptr;
static ID3D11InputLayout*      g_inputLayout  = nullptr;
static ID3D11Buffer*           g_vertexBuffer = nullptr;
static ID3D11Buffer*           g_cbuffer      = nullptr;
static ID3D11Texture2D*        g_renderTarget = nullptr;
static ID3D11RenderTargetView* g_rtv          = nullptr;
static ID3D11Texture2D*        g_staging      = nullptr;
static int32_t                 g_rtWidth      = 0;
static int32_t                 g_rtHeight     = 0;
static std::mutex              g_mutex;

// ── Constant buffer layout (must match the HLSL cbuffer) ────────────────────
struct alignas(16) ShaderUniforms {
    float u_Time;
    float _pad0[3];
    float u_Resolution[2];
    float u_Mouse[2];
    float u_AccentColor[4];
};

static ShaderUniforms g_uniforms = {};

// ── Full-screen triangle vertex shader (compiled at init) ──────────────────
static const char* kVertexShaderCode = R"(
struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

VS_OUTPUT main(uint vertexID : SV_VertexID) {
    VS_OUTPUT o;
    // Full-screen triangle trick: 3 vertices covering the entire screen
    o.uv  = float2((vertexID << 1) & 2, vertexID & 2);
    o.pos = float4(o.uv * float2(2, -2) + float2(-1, 1), 0, 1);
    return o;
}
)";

// ── Helper: safe release ────────────────────────────────────────────────────
template<typename T>
static void SafeRelease(T*& p) {
    if (p) { p->Release(); p = nullptr; }
}

// ── Helper: create render target of given size ──────────────────────────────
static bool CreateRenderTarget(int32_t w, int32_t h) {
    SafeRelease(g_rtv);
    SafeRelease(g_renderTarget);
    SafeRelease(g_staging);

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width              = w;
    desc.Height             = h;
    desc.MipLevels          = 1;
    desc.ArraySize          = 1;
    desc.Format             = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count   = 1;
    desc.Usage              = D3D11_USAGE_DEFAULT;
    desc.BindFlags          = D3D11_BIND_RENDER_TARGET;

    HRESULT hr = g_device->CreateTexture2D(&desc, nullptr, &g_renderTarget);
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(g_renderTarget, nullptr, &g_rtv);
    if (FAILED(hr)) return false;

    // Staging texture for CPU readback
    desc.Usage          = D3D11_USAGE_STAGING;
    desc.BindFlags      = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = g_device->CreateTexture2D(&desc, nullptr, &g_staging);
    if (FAILED(hr)) return false;

    g_rtWidth  = w;
    g_rtHeight = h;
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════════════

SHADER_API int32_t engine_init() {
    std::lock_guard<std::mutex> lock(g_mutex);

    D3D_FEATURE_LEVEL featureLevel = D3D_FEATURE_LEVEL_11_0;
    UINT flags = 0;
#ifdef _DEBUG
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
        &featureLevel, 1, D3D11_SDK_VERSION,
        &g_device, nullptr, &g_context
    );
    if (FAILED(hr)) return -1;

    // Compile the built-in full-screen vertex shader
    ID3DBlob* vsBlob  = nullptr;
    ID3DBlob* vsError = nullptr;
    hr = D3DCompile(
        kVertexShaderCode, strlen(kVertexShaderCode),
        "BuiltinVS", nullptr, nullptr,
        "main", "vs_5_0", 0, 0,
        &vsBlob, &vsError
    );
    if (vsError) vsError->Release();
    if (FAILED(hr)) return -1;

    hr = g_device->CreateVertexShader(
        vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(),
        nullptr, &g_vertexShader
    );
    vsBlob->Release();
    if (FAILED(hr)) return -1;

    // Create constant buffer
    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.ByteWidth      = sizeof(ShaderUniforms);
    cbDesc.Usage           = D3D11_USAGE_DYNAMIC;
    cbDesc.BindFlags       = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags  = D3D11_CPU_ACCESS_WRITE;
    hr = g_device->CreateBuffer(&cbDesc, nullptr, &g_cbuffer);
    if (FAILED(hr)) return -1;

    return 0;
}

SHADER_API int32_t engine_compile_shader(
    const char* hlsl_code,
    int32_t code_length,
    char* error_buf,
    int32_t error_buf_size
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device) return -1;

    if (error_buf && error_buf_size > 0) error_buf[0] = '\0';

    ID3DBlob* psBlob  = nullptr;
    ID3DBlob* psError = nullptr;

    HRESULT hr = D3DCompile(
        hlsl_code, static_cast<SIZE_T>(code_length),
        "UserShader", nullptr, nullptr,
        "main", "ps_5_0",
        D3DCOMPILE_ENABLE_STRICTNESS,
        0, &psBlob, &psError
    );

    if (FAILED(hr)) {
        if (psError && error_buf && error_buf_size > 0) {
            const char* msg = static_cast<const char*>(psError->GetBufferPointer());
            size_t len = psError->GetBufferSize();
            if (len > static_cast<size_t>(error_buf_size - 1))
                len = static_cast<size_t>(error_buf_size - 1);
            memcpy(error_buf, msg, len);
            error_buf[len] = '\0';
        }
        if (psError) psError->Release();
        if (psBlob)  psBlob->Release();
        return 1; // compilation error
    }
    if (psError) psError->Release();

    // Create new pixel shader, replace old one
    ID3D11PixelShader* newPS = nullptr;
    hr = g_device->CreatePixelShader(
        psBlob->GetBufferPointer(), psBlob->GetBufferSize(),
        nullptr, &newPS
    );
    psBlob->Release();
    if (FAILED(hr)) return -1;

    SafeRelease(g_pixelShader);
    g_pixelShader = newPS;
    return 0;
}

SHADER_API void engine_set_uniforms(
    float time,
    float resolution_x, float resolution_y,
    float mouse_x, float mouse_y,
    float accent_r, float accent_g, float accent_b, float accent_a
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_uniforms.u_Time          = time;
    g_uniforms.u_Resolution[0] = resolution_x;
    g_uniforms.u_Resolution[1] = resolution_y;
    g_uniforms.u_Mouse[0]      = mouse_x;
    g_uniforms.u_Mouse[1]      = mouse_y;
    g_uniforms.u_AccentColor[0] = accent_r;
    g_uniforms.u_AccentColor[1] = accent_g;
    g_uniforms.u_AccentColor[2] = accent_b;
    g_uniforms.u_AccentColor[3] = accent_a;
}

SHADER_API int32_t engine_render_frame(int32_t width, int32_t height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device || !g_context || !g_pixelShader || !g_vertexShader)
        return -1;

    // Recreate render target if size changed
    if (width != g_rtWidth || height != g_rtHeight) {
        if (!CreateRenderTarget(width, height))
            return -1;
    }

    // Update constant buffer
    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(g_cbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr)) return -1;
    memcpy(mapped.pData, &g_uniforms, sizeof(ShaderUniforms));
    g_context->Unmap(g_cbuffer, 0);

    // Set pipeline state
    g_context->OMSetRenderTargets(1, &g_rtv, nullptr);

    D3D11_VIEWPORT vp = {};
    vp.Width    = static_cast<float>(width);
    vp.Height   = static_cast<float>(height);
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    float clearColor[4] = { 0, 0, 0, 1 };
    g_context->ClearRenderTargetView(g_rtv, clearColor);

    g_context->VSSetShader(g_vertexShader, nullptr, 0);
    g_context->PSSetShader(g_pixelShader, nullptr, 0);
    g_context->PSSetConstantBuffers(0, 1, &g_cbuffer);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    // Draw full-screen triangle (3 vertices, no vertex buffer needed)
    g_context->Draw(3, 0);

    return 0;
}

SHADER_API int32_t engine_get_frame_pixels(uint8_t* out_pixels, int32_t buffer_size) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_context || !g_renderTarget || !g_staging) return -1;

    int32_t expected = g_rtWidth * g_rtHeight * 4;
    if (buffer_size < expected) return -1;

    g_context->CopyResource(g_staging, g_renderTarget);

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(g_staging, 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) return -1;

    const uint8_t* src = static_cast<const uint8_t*>(mapped.pData);
    for (int32_t y = 0; y < g_rtHeight; y++) {
        memcpy(
            out_pixels + y * g_rtWidth * 4,
            src + y * mapped.RowPitch,
            g_rtWidth * 4
        );
    }

    g_context->Unmap(g_staging, 0);
    return 0;
}

SHADER_API void engine_shutdown() {
    std::lock_guard<std::mutex> lock(g_mutex);
    SafeRelease(g_pixelShader);
    SafeRelease(g_vertexShader);
    SafeRelease(g_inputLayout);
    SafeRelease(g_vertexBuffer);
    SafeRelease(g_cbuffer);
    SafeRelease(g_rtv);
    SafeRelease(g_renderTarget);
    SafeRelease(g_staging);
    SafeRelease(g_context);
    SafeRelease(g_device);
    g_rtWidth  = 0;
    g_rtHeight = 0;
}
