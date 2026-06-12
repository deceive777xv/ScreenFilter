#include "shader_engine.h"

#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dcomp.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif
#ifndef WDA_NONE
#define WDA_NONE 0x00000000
#endif

// ── Internal state ──────────────────────────────────────────────────────────
static ID3D11Device*           g_device       = nullptr;
static ID3D11DeviceContext*    g_context      = nullptr;
static ID3D11PixelShader*      g_pixelShader  = nullptr;
static ID3D11PixelShader*      g_previewPixelShader = nullptr;
static ID3D11VertexShader*     g_vertexShader = nullptr;
static ID3D11InputLayout*      g_inputLayout  = nullptr;
static ID3D11Buffer*           g_vertexBuffer = nullptr;
static ID3D11Buffer*           g_cbuffer      = nullptr;
static ID3D11Texture2D*        g_renderTarget = nullptr;
static ID3D11RenderTargetView* g_rtv          = nullptr;
static ID3D11ShaderResourceView* g_renderSrv  = nullptr;
static ID3D11Texture2D*        g_staging      = nullptr;
static ID3D11Texture2D*        g_previewRenderTarget = nullptr;
static ID3D11RenderTargetView* g_previewRtv   = nullptr;
static ID3D11Texture2D*        g_previewStaging = nullptr;
static ID3D11Texture2D*        g_maskTexture  = nullptr;
static ID3D11ShaderResourceView* g_maskSrv    = nullptr;
static int32_t                 g_rtWidth      = 0;
static int32_t                 g_rtHeight     = 0;
static int32_t                 g_previewRtWidth = 0;
static int32_t                 g_previewRtHeight = 0;
static std::mutex              g_mutex;

enum class FrameReadbackKind {
    None,
    Fullscreen,
    Preview,
};

static FrameReadbackKind       g_lastFrameReadbackKind = FrameReadbackKind::None;

static HWND                    g_overlayWindow = nullptr;
static IDCompositionDevice*    g_dcompDevice   = nullptr;
static IDCompositionTarget*    g_dcompTarget   = nullptr;
static IDCompositionVisual*    g_dcompVisual   = nullptr;
static IDXGISwapChain1*        g_overlaySwapChain = nullptr;
static ID3D11RenderTargetView* g_overlayRtv    = nullptr;
static ID3D11PixelShader*      g_compositeShader = nullptr;
static ID3D11PixelShader*      g_mosaicShader  = nullptr;
static ID3D11PixelShader*      g_downsampleShader = nullptr;
static ID3D11SamplerState*     g_sampler       = nullptr;
static ID3D11Buffer*           g_overlayCbuffer = nullptr;
static ID3D11Buffer*           g_postProcessCbuffer = nullptr;
static ID3D11Buffer*           g_screenTextureCbuffer = nullptr;
static IDXGIOutputDuplication* g_outputDuplication = nullptr;
static ID3D11Texture2D*        g_screenTexture = nullptr;
static ID3D11ShaderResourceView* g_screenSrv   = nullptr;
static ID3D11Texture2D*        g_sandboxScreenTexture = nullptr;
static ID3D11RenderTargetView* g_sandboxScreenRtv = nullptr;
static ID3D11ShaderResourceView* g_sandboxScreenSrv = nullptr;
static int32_t                 g_overlayWidth  = 0;
static int32_t                 g_overlayHeight = 0;
static int32_t                 g_screenWidth   = 0;
static int32_t                 g_screenHeight  = 0;
static DXGI_FORMAT             g_screenFormat  = DXGI_FORMAT_UNKNOWN;
static int32_t                 g_sandboxScreenWidth = 0;
static int32_t                 g_sandboxScreenHeight = 0;
static bool                    g_overlayBoundsValid = false;
static bool                    g_overlayHasPresentedFrame = false;
static int                     g_overlayX      = 0;
static int                     g_overlayY      = 0;
static int                     g_overlayWindowWidth = 0;
static int                     g_overlayWindowHeight = 0;
static bool                    g_overlayPlacedBehindFlutter = false;
static HWND                    g_overlayRelativeFlutterWindow = nullptr;
static HWND                    g_cachedFlutterWindow = nullptr;
static HWND                    g_captureExcludedFlutterWindow = nullptr;
static ULONGLONG               g_lastFlutterWindowSearchTick = 0;
static ULONGLONG               g_lastOverlayPositionTick = 0;
static float                   g_filterOpacity = 1.0f;
static float                   g_filterBrightness = 0.0f;
static int32_t                 g_postProcessEffect = 0;
static float                   g_postProcessIntensity = 24.0f;
static bool                    g_maskEnabled  = false;
static bool                    g_maskInverted = false;
static int32_t                 g_maskWidth    = 0;
static int32_t                 g_maskHeight   = 0;
static constexpr int32_t kMaxSandboxScreenTextureWidth = 960;
static constexpr int32_t kMaxSandboxScreenTextureHeight = 540;
static constexpr float kMaxScreenSampleRadiusPx = 32.0f;
static constexpr const wchar_t* kOverlayWindowClassName =
    L"SCREEN_FILTER_DX11_OVERLAY_WINDOW";
static constexpr ULONGLONG kFlutterWindowSearchIntervalMs = 2000;
static constexpr ULONGLONG kOverlayPositionIntervalMs = 100;

// ── Constant buffer layout (must match the HLSL cbuffer) ────────────────────
struct alignas(16) ShaderUniforms {
    float u_Time;
    float _pad0[3];
    float u_Resolution[2];
    float u_Mouse[2];
    float u_AccentColor[4];
};

static ShaderUniforms g_uniforms = {};

struct alignas(16) OverlayUniforms {
    float u_Opacity;
    float u_Brightness;
    float u_MaskEnabled;
    float u_MaskInverted;
};

static OverlayUniforms g_overlayUniforms = {1.0f, 0.0f, 0.0f, 0.0f};

struct alignas(16) PostProcessUniforms {
    float u_BlockSize;
    float u_TargetSize[2];
    float _pad0;
};

static PostProcessUniforms g_postProcessUniforms = {24.0f, {1.0f, 1.0f}, 0.0f};

struct alignas(16) ScreenTextureUniforms {
    float u_ScreenTextureSize[2];
    float u_ScreenTexelSize[2];
    float u_MaxScreenSampleRadius;
    float _pad0[3];
};

static ScreenTextureUniforms g_screenTextureUniforms = {
    {1.0f, 1.0f},
    {1.0f, 1.0f},
    kMaxScreenSampleRadiusPx,
    {0.0f, 0.0f, 0.0f},
};

static int32_t CompileShaderToSlot(
    const char* hlsl_code,
    int32_t code_length,
    char* error_buf,
    int32_t error_buf_size,
    ID3D11PixelShader*& shaderSlot
);
static bool ValidateUserShaderSandbox(
    const std::string& userCode,
    std::string& errorMessage
);
static void CopyErrorMessage(
    const char* message,
    char* errorBuf,
    int32_t errorBufSize
);
static void EnsureFlutterWindowExcludedFromCapture(bool force);
static void ClearFlutterWindowCaptureExclusion();

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

static const char* kCompositeShaderCode = R"(
cbuffer OverlayUniforms : register(b1) {
    float u_Opacity;
    float u_Brightness;
    float u_MaskEnabled;
    float u_MaskInverted;
};

Texture2D userFrame : register(t0);
Texture2D maskFrame : register(t1);
SamplerState frameSampler : register(s0);

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET {
    float4 c = userFrame.Sample(frameSampler, input.uv);

    float scale;
    float offset;
    if (u_Brightness <= 0.0) {
        scale = 1.0 + u_Brightness * 0.95;
        offset = 0.0;
    } else {
        scale = 1.0 - u_Brightness * 0.95;
        offset = u_Brightness * 0.95;
    }

    c.rgb = saturate(c.rgb * scale + offset);
    c.a = saturate(c.a * u_Opacity);

    if (u_MaskEnabled > 0.5) {
        float mask = maskFrame.Sample(frameSampler, input.uv).r;
        if (u_MaskInverted > 0.5) {
            mask = 1.0 - mask;
        }
        c.a *= saturate(mask);
    }

    // DirectComposition swap chains use premultiplied alpha.
    return float4(c.rgb * c.a, c.a);
}
)";

static const char* kMosaicShaderCode = R"(
cbuffer PostProcessUniforms : register(b2) {
    float  u_BlockSize;
    float2 u_TargetSize;
    float  _pad0;
};

Texture2D screenFrame : register(t0);
SamplerState frameSampler : register(s0);

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET {
    float blockSize = max(u_BlockSize, 1.0);
    float2 targetSize = max(u_TargetSize, float2(1.0, 1.0));
    float2 pixel = input.uv * targetSize;
    float2 blockCenter = floor(pixel / blockSize) * blockSize + blockSize * 0.5;
    float2 sampleUv = saturate(blockCenter / targetSize);
    float4 c = screenFrame.Sample(frameSampler, sampleUv);
    return float4(c.rgb, 1.0);
}
)";

static const char* kScreenDownsampleShaderCode = R"(
Texture2D screenFrame : register(t0);
SamplerState frameSampler : register(s0);

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET {
    return screenFrame.Sample(frameSampler, input.uv);
}
)";

static const char* kScreenTextureSandboxHeader = R"(
#ifndef SCREENFILTER_SCREEN_TEXTURE_SANDBOX
#define SCREENFILTER_SCREEN_TEXTURE_SANDBOX
cbuffer ScreenTextureSandbox : register(b3) {
    float2 u_ScreenTextureSize;
    float2 u_ScreenTexelSize;
    float  u_MaxScreenSampleRadius;
    float3 _screenTexturePad0;
};

Texture2D screenTexture : register(t0);
SamplerState screenSampler : register(s0);

float4 SampleScreen(float2 uv, float2 offsetPx) {
    float2 safeOffsetPx = clamp(offsetPx,
        -u_MaxScreenSampleRadius.xx,
        u_MaxScreenSampleRadius.xx
    );
    float2 sampleUv = saturate(uv + safeOffsetPx * u_ScreenTexelSize);
    return screenTexture.Sample(screenSampler, sampleUv);
}
#endif

)";

// ── Helper: safe release ────────────────────────────────────────────────────
template<typename T>
static void SafeRelease(T*& p) {
    if (p) { p->Release(); p = nullptr; }
}

// ── Helper: create render target of given size ──────────────────────────────
static bool CreateRenderTarget(int32_t w, int32_t h) {
    SafeRelease(g_rtv);
    SafeRelease(g_renderSrv);
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
    desc.BindFlags          = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    HRESULT hr = g_device->CreateTexture2D(&desc, nullptr, &g_renderTarget);
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(g_renderTarget, nullptr, &g_rtv);
    if (FAILED(hr)) return false;

    hr = g_device->CreateShaderResourceView(g_renderTarget, nullptr, &g_renderSrv);
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

static bool CreatePreviewRenderTarget(int32_t w, int32_t h) {
    SafeRelease(g_previewRtv);
    SafeRelease(g_previewRenderTarget);
    SafeRelease(g_previewStaging);

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = w;
    desc.Height = h;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;

    HRESULT hr = g_device->CreateTexture2D(
        &desc, nullptr, &g_previewRenderTarget
    );
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(
        g_previewRenderTarget, nullptr, &g_previewRtv
    );
    if (FAILED(hr)) return false;

    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = g_device->CreateTexture2D(&desc, nullptr, &g_previewStaging);
    if (FAILED(hr)) return false;

    g_previewRtWidth = w;
    g_previewRtHeight = h;
    return true;
}

static void ReleaseOverlaySwapChain() {
    SafeRelease(g_overlayRtv);
    SafeRelease(g_overlaySwapChain);
    g_overlayWidth = 0;
    g_overlayHeight = 0;
}

static void ReleaseSandboxScreenResources() {
    SafeRelease(g_sandboxScreenSrv);
    SafeRelease(g_sandboxScreenRtv);
    SafeRelease(g_sandboxScreenTexture);
    g_sandboxScreenWidth = 0;
    g_sandboxScreenHeight = 0;
}

static void ReleaseScreenFrameResources() {
    ReleaseSandboxScreenResources();
    SafeRelease(g_screenSrv);
    SafeRelease(g_screenTexture);
    g_screenWidth = 0;
    g_screenHeight = 0;
    g_screenFormat = DXGI_FORMAT_UNKNOWN;
}

static void ReleaseScreenCaptureResources() {
    SafeRelease(g_outputDuplication);
    ReleaseScreenFrameResources();
    ClearFlutterWindowCaptureExclusion();
}

static void ReleaseMaskResources() {
    SafeRelease(g_maskSrv);
    SafeRelease(g_maskTexture);
    g_maskEnabled = false;
    g_maskInverted = false;
    g_maskWidth = 0;
    g_maskHeight = 0;
}

static bool PointInPolygon(
    float x,
    float y,
    const float* points,
    int32_t pointCount
) {
    bool inside = false;
    for (int32_t i = 0, j = pointCount - 1; i < pointCount; j = i++) {
        const float xi = points[i * 2];
        const float yi = points[i * 2 + 1];
        const float xj = points[j * 2];
        const float yj = points[j * 2 + 1];
        const bool crosses = ((yi > y) != (yj > y)) &&
            (x < (xj - xi) * (y - yi) / ((yj - yi) + 0.000001f) + xi);
        if (crosses) {
            inside = !inside;
        }
    }
    return inside;
}

static bool CreateMaskTexture(
    int32_t width,
    int32_t height,
    const std::vector<uint8_t>& mask
) {
    SafeRelease(g_maskSrv);
    SafeRelease(g_maskTexture);

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_IMMUTABLE;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

    D3D11_SUBRESOURCE_DATA data = {};
    data.pSysMem = mask.data();
    data.SysMemPitch = static_cast<UINT>(width);

    HRESULT hr = g_device->CreateTexture2D(&desc, &data, &g_maskTexture);
    if (FAILED(hr)) return false;

    hr = g_device->CreateShaderResourceView(g_maskTexture, nullptr, &g_maskSrv);
    if (FAILED(hr)) {
        SafeRelease(g_maskTexture);
        return false;
    }

    g_maskWidth = width;
    g_maskHeight = height;
    return true;
}

static bool EnsureOutputDuplication() {
    if (g_outputDuplication) return true;
    if (!g_device) return false;

    IDXGIDevice* dxgiDevice = nullptr;
    IDXGIAdapter* adapter = nullptr;
    IDXGIOutput* output = nullptr;
    IDXGIOutput1* output1 = nullptr;

    HRESULT hr = g_device->QueryInterface(
        __uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDevice)
    );
    if (FAILED(hr)) return false;

    hr = dxgiDevice->GetAdapter(&adapter);
    dxgiDevice->Release();
    if (FAILED(hr)) return false;

    hr = adapter->EnumOutputs(0, &output);
    adapter->Release();
    if (FAILED(hr)) return false;

    hr = output->QueryInterface(
        __uuidof(IDXGIOutput1), reinterpret_cast<void**>(&output1)
    );
    output->Release();
    if (FAILED(hr)) return false;

    hr = output1->DuplicateOutput(g_device, &g_outputDuplication);
    output1->Release();
    return SUCCEEDED(hr);
}

static bool EnsureScreenFrameTexture(const D3D11_TEXTURE2D_DESC& srcDesc) {
    if (g_screenTexture &&
        g_screenWidth == static_cast<int32_t>(srcDesc.Width) &&
        g_screenHeight == static_cast<int32_t>(srcDesc.Height) &&
        g_screenFormat == srcDesc.Format) {
        return true;
    }

    ReleaseScreenFrameResources();

    D3D11_TEXTURE2D_DESC desc = srcDesc;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = 0;
    desc.MiscFlags = 0;

    HRESULT hr = g_device->CreateTexture2D(&desc, nullptr, &g_screenTexture);
    if (FAILED(hr)) return false;

    hr = g_device->CreateShaderResourceView(g_screenTexture, nullptr, &g_screenSrv);
    if (FAILED(hr)) {
        ReleaseScreenFrameResources();
        return false;
    }

    g_screenWidth = static_cast<int32_t>(srcDesc.Width);
    g_screenHeight = static_cast<int32_t>(srcDesc.Height);
    g_screenFormat = srcDesc.Format;
    return true;
}

static bool CaptureScreenFrame() {
    if (!g_context) return false;
    EnsureFlutterWindowExcludedFromCapture(false);
    if (!EnsureOutputDuplication()) {
        return g_screenSrv != nullptr;
    }

    DXGI_OUTDUPL_FRAME_INFO frameInfo = {};
    IDXGIResource* desktopResource = nullptr;
    HRESULT hr = g_outputDuplication->AcquireNextFrame(
        0, &frameInfo, &desktopResource
    );

    if (hr == DXGI_ERROR_WAIT_TIMEOUT) {
        return g_screenSrv != nullptr;
    }
    if (hr == DXGI_ERROR_ACCESS_LOST || hr == DXGI_ERROR_INVALID_CALL) {
        SafeRelease(g_outputDuplication);
        return g_screenSrv != nullptr;
    }
    if (FAILED(hr)) {
        return g_screenSrv != nullptr;
    }

    ID3D11Texture2D* frameTexture = nullptr;
    hr = desktopResource->QueryInterface(
        __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&frameTexture)
    );
    desktopResource->Release();

    bool ok = false;
    if (SUCCEEDED(hr)) {
        D3D11_TEXTURE2D_DESC desc = {};
        frameTexture->GetDesc(&desc);
        ok = EnsureScreenFrameTexture(desc);
        if (ok) {
            g_context->CopyResource(g_screenTexture, frameTexture);
        }
        frameTexture->Release();
    }

    g_outputDuplication->ReleaseFrame();
    return ok && g_screenSrv;
}

static bool EnsureSandboxScreenTexture(int32_t sourceWidth, int32_t sourceHeight) {
    if (!g_device || sourceWidth <= 0 || sourceHeight <= 0) return false;

    const float scaleX =
        static_cast<float>(kMaxSandboxScreenTextureWidth) /
        static_cast<float>(sourceWidth);
    const float scaleY =
        static_cast<float>(kMaxSandboxScreenTextureHeight) /
        static_cast<float>(sourceHeight);
    const float scale = (std::min)(1.0f, (std::min)(scaleX, scaleY));
    const int32_t targetWidth = (std::max)(
        1,
        static_cast<int32_t>(std::floor(sourceWidth * scale))
    );
    const int32_t targetHeight = (std::max)(
        1,
        static_cast<int32_t>(std::floor(sourceHeight * scale))
    );

    if (g_sandboxScreenTexture &&
        g_sandboxScreenWidth == targetWidth &&
        g_sandboxScreenHeight == targetHeight) {
        return true;
    }

    ReleaseSandboxScreenResources();

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = targetWidth;
    desc.Height = targetHeight;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    HRESULT hr = g_device->CreateTexture2D(
        &desc, nullptr, &g_sandboxScreenTexture
    );
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(
        g_sandboxScreenTexture, nullptr, &g_sandboxScreenRtv
    );
    if (FAILED(hr)) {
        ReleaseSandboxScreenResources();
        return false;
    }

    hr = g_device->CreateShaderResourceView(
        g_sandboxScreenTexture, nullptr, &g_sandboxScreenSrv
    );
    if (FAILED(hr)) {
        ReleaseSandboxScreenResources();
        return false;
    }

    g_sandboxScreenWidth = targetWidth;
    g_sandboxScreenHeight = targetHeight;
    return true;
}

static bool UpdateScreenTextureCbuffer() {
    if (!g_context || !g_screenTextureCbuffer) return false;

    const float width = static_cast<float>(
        (std::max)(1, g_sandboxScreenWidth)
    );
    const float height = static_cast<float>(
        (std::max)(1, g_sandboxScreenHeight)
    );
    g_screenTextureUniforms.u_ScreenTextureSize[0] = width;
    g_screenTextureUniforms.u_ScreenTextureSize[1] = height;
    g_screenTextureUniforms.u_ScreenTexelSize[0] = 1.0f / width;
    g_screenTextureUniforms.u_ScreenTexelSize[1] = 1.0f / height;
    g_screenTextureUniforms.u_MaxScreenSampleRadius = kMaxScreenSampleRadiusPx;

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(
        g_screenTextureCbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped
    );
    if (FAILED(hr)) return false;
    memcpy(
        mapped.pData,
        &g_screenTextureUniforms,
        sizeof(ScreenTextureUniforms)
    );
    g_context->Unmap(g_screenTextureCbuffer, 0);
    return true;
}

static bool PrepareSandboxScreenTexture() {
    if (!g_context || !g_vertexShader || !g_downsampleShader || !g_sampler) {
        return false;
    }
    if (!CaptureScreenFrame() || !g_screenSrv) {
        return g_sandboxScreenSrv != nullptr;
    }
    if (!EnsureSandboxScreenTexture(g_screenWidth, g_screenHeight)) {
        return false;
    }

    ID3D11ShaderResourceView* nullSrv[1] = {nullptr};
    g_context->PSSetShaderResources(0, 1, nullSrv);
    g_context->OMSetRenderTargets(1, &g_sandboxScreenRtv, nullptr);

    D3D11_VIEWPORT vp = {};
    vp.Width = static_cast<float>(g_sandboxScreenWidth);
    vp.Height = static_cast<float>(g_sandboxScreenHeight);
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    g_context->VSSetShader(g_vertexShader, nullptr, 0);
    g_context->PSSetShader(g_downsampleShader, nullptr, 0);
    g_context->PSSetShaderResources(0, 1, &g_screenSrv);
    g_context->PSSetSamplers(0, 1, &g_sampler);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_context->Draw(3, 0);
    g_context->PSSetShaderResources(0, 1, nullSrv);

    return g_sandboxScreenSrv != nullptr;
}

static void ReleaseOverlayResources() {
    ReleaseOverlaySwapChain();
    ReleaseScreenCaptureResources();
    SafeRelease(g_dcompVisual);
    SafeRelease(g_dcompTarget);
    SafeRelease(g_dcompDevice);
    if (g_overlayWindow) {
        DestroyWindow(g_overlayWindow);
        g_overlayWindow = nullptr;
    }
    g_overlayBoundsValid = false;
    g_overlayHasPresentedFrame = false;
    g_overlayPlacedBehindFlutter = false;
    g_overlayRelativeFlutterWindow = nullptr;
    g_cachedFlutterWindow = nullptr;
    g_lastFlutterWindowSearchTick = 0;
    g_lastOverlayPositionTick = 0;
}

static LRESULT CALLBACK OverlayWndProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam
) {
    switch (message) {
        case WM_NCHITTEST:
            return HTTRANSPARENT;
        case WM_CLOSE:
            ShowWindow(hwnd, SW_HIDE);
            return 0;
        default:
            return DefWindowProc(hwnd, message, wparam, lparam);
    }
}

static bool RegisterOverlayWindowClass() {
    WNDCLASSW wc = {};
    if (GetClassInfoW(GetModuleHandleW(nullptr), kOverlayWindowClassName, &wc)) {
        return true;
    }

    wc.lpfnWndProc = OverlayWndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kOverlayWindowClassName;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;

    return RegisterClassW(&wc) != 0;
}

struct FindWindowData {
    DWORD processId;
    HWND window;
};

static BOOL CALLBACK FindFlutterWindowProc(HWND hwnd, LPARAM lparam) {
    auto* data = reinterpret_cast<FindWindowData*>(lparam);

    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != data->processId || !IsWindowVisible(hwnd)) {
        return TRUE;
    }

    wchar_t className[128] = {};
    GetClassNameW(hwnd, className, 128);
    if (wcscmp(className, kOverlayWindowClassName) == 0) {
        return TRUE;
    }
    if (wcscmp(className, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
        return TRUE;
    }

    data->window = hwnd;
    return FALSE;
}

static HWND FindFlutterWindow() {
    FindWindowData data = {GetCurrentProcessId(), nullptr};
    EnumWindows(FindFlutterWindowProc, reinterpret_cast<LPARAM>(&data));
    return data.window;
}

static HWND FindFlutterWindowCached(bool force) {
    const ULONGLONG now = GetTickCount64();
    if (!force && g_cachedFlutterWindow && IsWindow(g_cachedFlutterWindow)) {
        return g_cachedFlutterWindow;
    }
    if (!force &&
        now - g_lastFlutterWindowSearchTick < kFlutterWindowSearchIntervalMs) {
        return g_cachedFlutterWindow;
    }

    g_lastFlutterWindowSearchTick = now;
    g_cachedFlutterWindow = FindFlutterWindow();
    return g_cachedFlutterWindow;
}

static void EnsureFlutterWindowExcludedFromCapture(bool force) {
    HWND flutterWindow = FindFlutterWindowCached(force);
    if (!flutterWindow) return;
    if (!force && g_captureExcludedFlutterWindow == flutterWindow) return;
    if (SetWindowDisplayAffinity(flutterWindow, WDA_EXCLUDEFROMCAPTURE)) {
        g_captureExcludedFlutterWindow = flutterWindow;
    }
}

static void ClearFlutterWindowCaptureExclusion() {
    if (!g_captureExcludedFlutterWindow) return;
    if (IsWindow(g_captureExcludedFlutterWindow)) {
        SetWindowDisplayAffinity(g_captureExcludedFlutterWindow, WDA_NONE);
    }
    g_captureExcludedFlutterWindow = nullptr;
}

static void PositionOverlayWindow(
    int32_t width,
    int32_t height,
    bool force = false,
    bool showWindow = true
) {
    if (!g_overlayWindow) return;

    const ULONGLONG now = GetTickCount64();
    if (!force &&
        g_overlayBoundsValid &&
        now - g_lastOverlayPositionTick < kOverlayPositionIntervalMs) {
        return;
    }
    g_lastOverlayPositionTick = now;

    int x = 0;
    int y = 0;
    int w = width;
    int h = height;
    HWND flutterWindow = FindFlutterWindowCached(force);
    if (flutterWindow) {
        RECT rect = {};
        if (GetWindowRect(flutterWindow, &rect)) {
            x = rect.left;
            y = rect.top;
            w = rect.right - rect.left;
            h = rect.bottom - rect.top;
        }
    }

    const bool needsShow = showWindow && !IsWindowVisible(g_overlayWindow);
    if (g_overlayBoundsValid &&
        x == g_overlayX && y == g_overlayY &&
        w == g_overlayWindowWidth && h == g_overlayWindowHeight &&
        !needsShow &&
        (!flutterWindow ||
            (g_overlayPlacedBehindFlutter &&
             g_overlayRelativeFlutterWindow == flutterWindow))) {
        return;
    }

    const UINT flags = SWP_NOACTIVATE | (showWindow ? SWP_SHOWWINDOW : 0);
    SetWindowPos(
        g_overlayWindow, HWND_TOPMOST, x, y, w, h,
        flags
    );
    if (flutterWindow) {
        SetWindowPos(
            g_overlayWindow, flutterWindow, x, y, w, h,
            flags
        );
    }

    g_overlayBoundsValid = true;
    g_overlayX = x;
    g_overlayY = y;
    g_overlayWindowWidth = w;
    g_overlayWindowHeight = h;
    g_overlayPlacedBehindFlutter = flutterWindow != nullptr;
    g_overlayRelativeFlutterWindow = flutterWindow;
}

static bool CreateOverlayWindow(int32_t width, int32_t height) {
    if (g_overlayWindow) {
        return true;
    }

    if (!RegisterOverlayWindowClass()) return false;

    g_overlayWindow = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE |
            WS_EX_NOREDIRECTIONBITMAP,
        kOverlayWindowClassName,
        L"ScreenFilter DX11 Overlay",
        WS_POPUP,
        0,
        0,
        width,
        height,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr
    );
    if (!g_overlayWindow) return false;

    // Prevent desktop duplication from sampling our previous overlay frame.
    SetWindowDisplayAffinity(g_overlayWindow, WDA_EXCLUDEFROMCAPTURE);
    SetLayeredWindowAttributes(g_overlayWindow, 0, 255, LWA_ALPHA);
    PositionOverlayWindow(width, height, true, false);
    return true;
}

static bool EnsureCompositionTarget() {
    if (g_dcompDevice && g_dcompTarget && g_dcompVisual) return true;
    if (!g_device || !g_overlayWindow) return false;

    IDXGIDevice* dxgiDevice = nullptr;
    HRESULT hr = g_device->QueryInterface(__uuidof(IDXGIDevice),
        reinterpret_cast<void**>(&dxgiDevice));
    if (FAILED(hr)) return false;

    hr = DCompositionCreateDevice(
        dxgiDevice, __uuidof(IDCompositionDevice),
        reinterpret_cast<void**>(&g_dcompDevice)
    );
    dxgiDevice->Release();
    if (FAILED(hr)) return false;

    hr = g_dcompDevice->CreateTargetForHwnd(g_overlayWindow, TRUE, &g_dcompTarget);
    if (FAILED(hr)) return false;

    hr = g_dcompDevice->CreateVisual(&g_dcompVisual);
    if (FAILED(hr)) return false;

    return true;
}

static bool CreateOverlaySwapChain(int32_t width, int32_t height) {
    ReleaseOverlaySwapChain();
    g_overlayHasPresentedFrame = false;
    if (g_overlayWindow) {
        ShowWindow(g_overlayWindow, SW_HIDE);
    }
    if (!g_device || !g_dcompDevice || !g_dcompTarget || !g_dcompVisual) {
        return false;
    }

    IDXGIDevice* dxgiDevice = nullptr;
    IDXGIAdapter* adapter = nullptr;
    IDXGIFactory2* factory = nullptr;
    HRESULT hr = g_device->QueryInterface(__uuidof(IDXGIDevice),
        reinterpret_cast<void**>(&dxgiDevice));
    if (FAILED(hr)) return false;

    hr = dxgiDevice->GetAdapter(&adapter);
    dxgiDevice->Release();
    if (FAILED(hr)) return false;

    hr = adapter->GetParent(__uuidof(IDXGIFactory2),
        reinterpret_cast<void**>(&factory));
    adapter->Release();
    if (FAILED(hr)) return false;

    DXGI_SWAP_CHAIN_DESC1 desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.Stereo = FALSE;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2;
    desc.Scaling = DXGI_SCALING_STRETCH;
    desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;

    hr = factory->CreateSwapChainForComposition(
        g_device, &desc, nullptr, &g_overlaySwapChain
    );
    factory->Release();
    if (FAILED(hr)) return false;

    ID3D11Texture2D* backBuffer = nullptr;
    hr = g_overlaySwapChain->GetBuffer(
        0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&backBuffer)
    );
    if (FAILED(hr)) return false;

    hr = g_device->CreateRenderTargetView(backBuffer, nullptr, &g_overlayRtv);
    backBuffer->Release();
    if (FAILED(hr)) return false;

    hr = g_dcompVisual->SetContent(g_overlaySwapChain);
    if (FAILED(hr)) return false;
    hr = g_dcompTarget->SetRoot(g_dcompVisual);
    if (FAILED(hr)) return false;
    hr = g_dcompDevice->Commit();
    if (FAILED(hr)) return false;

    g_overlayWidth = width;
    g_overlayHeight = height;
    return true;
}

static bool EnsureOverlay(int32_t width, int32_t height) {
    if (width <= 0 || height <= 0) return false;
    if (!CreateOverlayWindow(width, height)) return false;
    if (!EnsureCompositionTarget()) return false;

    if (!g_overlaySwapChain || width != g_overlayWidth || height != g_overlayHeight) {
        PositionOverlayWindow(width, height, true, g_overlayHasPresentedFrame);
        return CreateOverlaySwapChain(width, height);
    }
    PositionOverlayWindow(width, height, false, g_overlayHasPresentedFrame);
    return true;
}

static void ShowOverlayWindowAfterFirstFrame(int32_t width, int32_t height) {
    if (!g_overlayWindow || g_overlayHasPresentedFrame) return;
    g_overlayHasPresentedFrame = true;
    PositionOverlayWindow(width, height, true, true);
}

static bool RenderUserShaderToTarget(
    ID3D11PixelShader* pixelShader,
    int32_t width,
    int32_t height,
    ID3D11RenderTargetView* target
) {
    if (!g_context || !pixelShader || !g_vertexShader || !g_cbuffer ||
        !g_sampler || !g_screenTextureCbuffer || !target) {
        return false;
    }

    PrepareSandboxScreenTexture();
    if (!UpdateScreenTextureCbuffer()) {
        return false;
    }

    ID3D11ShaderResourceView* nullSrv[1] = {nullptr};
    g_context->PSSetShaderResources(0, 1, nullSrv);

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(g_cbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (FAILED(hr)) return false;
    memcpy(mapped.pData, &g_uniforms, sizeof(ShaderUniforms));
    g_context->Unmap(g_cbuffer, 0);

    g_context->OMSetRenderTargets(1, &target, nullptr);

    D3D11_VIEWPORT vp = {};
    vp.Width = static_cast<float>(width);
    vp.Height = static_cast<float>(height);
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    float clearColor[4] = {0, 0, 0, 0};
    g_context->ClearRenderTargetView(target, clearColor);

    g_context->VSSetShader(g_vertexShader, nullptr, 0);
    g_context->PSSetShader(pixelShader, nullptr, 0);
    ID3D11ShaderResourceView* screenSrv = g_sandboxScreenSrv;
    g_context->PSSetShaderResources(0, 1, &screenSrv);
    g_context->PSSetSamplers(0, 1, &g_sampler);
    g_context->PSSetConstantBuffers(0, 1, &g_cbuffer);
    g_context->PSSetConstantBuffers(3, 1, &g_screenTextureCbuffer);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_context->Draw(3, 0);

    g_context->PSSetShaderResources(0, 1, nullSrv);
    return true;
}

static bool RenderPostProcessToTarget(
    int32_t width, int32_t height, ID3D11RenderTargetView* target
) {
    if (!g_context || !g_vertexShader || !g_mosaicShader ||
        !g_sampler || !g_postProcessCbuffer || !target) {
        return false;
    }
    if (g_postProcessEffect != 1) {
        return false;
    }
    if (!CaptureScreenFrame()) {
        return false;
    }

    g_postProcessUniforms.u_BlockSize =
        (std::max)(1.0f, g_postProcessIntensity);
    g_postProcessUniforms.u_TargetSize[0] = static_cast<float>(width);
    g_postProcessUniforms.u_TargetSize[1] = static_cast<float>(height);

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(
        g_postProcessCbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped
    );
    if (FAILED(hr)) return false;
    memcpy(mapped.pData, &g_postProcessUniforms, sizeof(PostProcessUniforms));
    g_context->Unmap(g_postProcessCbuffer, 0);

    ID3D11ShaderResourceView* nullSrv[1] = {nullptr};
    g_context->PSSetShaderResources(0, 1, nullSrv);
    g_context->OMSetRenderTargets(1, &target, nullptr);

    D3D11_VIEWPORT vp = {};
    vp.Width = static_cast<float>(width);
    vp.Height = static_cast<float>(height);
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    float clearColor[4] = {0, 0, 0, 0};
    g_context->ClearRenderTargetView(target, clearColor);

    g_context->VSSetShader(g_vertexShader, nullptr, 0);
    g_context->PSSetShader(g_mosaicShader, nullptr, 0);
    g_context->PSSetShaderResources(0, 1, &g_screenSrv);
    g_context->PSSetSamplers(0, 1, &g_sampler);
    g_context->PSSetConstantBuffers(2, 1, &g_postProcessCbuffer);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_context->Draw(3, 0);

    g_context->PSSetShaderResources(0, 1, nullSrv);
    return true;
}

static bool RenderCompositeToOverlay(int32_t width, int32_t height) {
    if (!g_context || !g_renderSrv || !g_overlayRtv || !g_compositeShader ||
        !g_sampler || !g_overlayCbuffer || !g_overlaySwapChain) {
        return false;
    }

    g_overlayUniforms.u_Opacity = g_filterOpacity;
    g_overlayUniforms.u_Brightness = g_filterBrightness;
    g_overlayUniforms.u_MaskEnabled = g_maskEnabled ? 1.0f : 0.0f;
    g_overlayUniforms.u_MaskInverted = g_maskInverted ? 1.0f : 0.0f;

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(
        g_overlayCbuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped
    );
    if (FAILED(hr)) return false;
    memcpy(mapped.pData, &g_overlayUniforms, sizeof(OverlayUniforms));
    g_context->Unmap(g_overlayCbuffer, 0);

    g_context->OMSetRenderTargets(1, &g_overlayRtv, nullptr);

    D3D11_VIEWPORT vp = {};
    vp.Width = static_cast<float>(width);
    vp.Height = static_cast<float>(height);
    vp.MaxDepth = 1.0f;
    g_context->RSSetViewports(1, &vp);

    float clearColor[4] = {0, 0, 0, 0};
    g_context->ClearRenderTargetView(g_overlayRtv, clearColor);

    g_context->VSSetShader(g_vertexShader, nullptr, 0);
    g_context->PSSetShader(g_compositeShader, nullptr, 0);
    g_context->PSSetShaderResources(0, 1, &g_renderSrv);
    if (g_maskEnabled && g_maskSrv) {
        g_context->PSSetShaderResources(1, 1, &g_maskSrv);
    }
    g_context->PSSetSamplers(0, 1, &g_sampler);
    g_context->PSSetConstantBuffers(1, 1, &g_overlayCbuffer);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_context->Draw(3, 0);

    ID3D11ShaderResourceView* nullSrvs[2] = {nullptr, nullptr};
    g_context->PSSetShaderResources(0, 2, nullSrvs);

    hr = g_overlaySwapChain->Present(1, 0);
    if (SUCCEEDED(hr)) {
        ShowOverlayWindowAfterFirstFrame(width, height);
        return true;
    }
    return false;
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

    // Compile the compositor shader used by the native transparent overlay.
    ID3DBlob* compositeBlob = nullptr;
    ID3DBlob* compositeError = nullptr;
    hr = D3DCompile(
        kCompositeShaderCode, strlen(kCompositeShaderCode),
        "OverlayCompositePS", nullptr, nullptr,
        "main", "ps_5_0", 0, 0,
        &compositeBlob, &compositeError
    );
    if (compositeError) compositeError->Release();
    if (FAILED(hr)) return -1;

    hr = g_device->CreatePixelShader(
        compositeBlob->GetBufferPointer(), compositeBlob->GetBufferSize(),
        nullptr, &g_compositeShader
    );
    compositeBlob->Release();
    if (FAILED(hr)) return -1;

    // Compile the built-in mosaic post-processing shader.
    ID3DBlob* mosaicBlob = nullptr;
    ID3DBlob* mosaicError = nullptr;
    hr = D3DCompile(
        kMosaicShaderCode, strlen(kMosaicShaderCode),
        "MosaicPostProcessPS", nullptr, nullptr,
        "main", "ps_5_0", 0, 0,
        &mosaicBlob, &mosaicError
    );
    if (mosaicError) mosaicError->Release();
    if (FAILED(hr)) return -1;

    hr = g_device->CreatePixelShader(
        mosaicBlob->GetBufferPointer(), mosaicBlob->GetBufferSize(),
        nullptr, &g_mosaicShader
    );
    mosaicBlob->Release();
    if (FAILED(hr)) return -1;

    // Compile the screen downsample shader used for user post-processing.
    ID3DBlob* downsampleBlob = nullptr;
    ID3DBlob* downsampleError = nullptr;
    hr = D3DCompile(
        kScreenDownsampleShaderCode, strlen(kScreenDownsampleShaderCode),
        "ScreenDownsamplePS", nullptr, nullptr,
        "main", "ps_5_0", 0, 0,
        &downsampleBlob, &downsampleError
    );
    if (downsampleError) downsampleError->Release();
    if (FAILED(hr)) return -1;

    hr = g_device->CreatePixelShader(
        downsampleBlob->GetBufferPointer(), downsampleBlob->GetBufferSize(),
        nullptr, &g_downsampleShader
    );
    downsampleBlob->Release();
    if (FAILED(hr)) return -1;

    // Create constant buffer
    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.ByteWidth      = sizeof(ShaderUniforms);
    cbDesc.Usage           = D3D11_USAGE_DYNAMIC;
    cbDesc.BindFlags       = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags  = D3D11_CPU_ACCESS_WRITE;
    hr = g_device->CreateBuffer(&cbDesc, nullptr, &g_cbuffer);
    if (FAILED(hr)) return -1;

    D3D11_BUFFER_DESC overlayCbDesc = {};
    overlayCbDesc.ByteWidth = sizeof(OverlayUniforms);
    overlayCbDesc.Usage = D3D11_USAGE_DYNAMIC;
    overlayCbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    overlayCbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    hr = g_device->CreateBuffer(&overlayCbDesc, nullptr, &g_overlayCbuffer);
    if (FAILED(hr)) return -1;

    D3D11_BUFFER_DESC postProcessCbDesc = {};
    postProcessCbDesc.ByteWidth = sizeof(PostProcessUniforms);
    postProcessCbDesc.Usage = D3D11_USAGE_DYNAMIC;
    postProcessCbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    postProcessCbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    hr = g_device->CreateBuffer(
        &postProcessCbDesc, nullptr, &g_postProcessCbuffer
    );
    if (FAILED(hr)) return -1;

    D3D11_BUFFER_DESC screenTextureCbDesc = {};
    screenTextureCbDesc.ByteWidth = sizeof(ScreenTextureUniforms);
    screenTextureCbDesc.Usage = D3D11_USAGE_DYNAMIC;
    screenTextureCbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    screenTextureCbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    hr = g_device->CreateBuffer(
        &screenTextureCbDesc, nullptr, &g_screenTextureCbuffer
    );
    if (FAILED(hr)) return -1;

    D3D11_SAMPLER_DESC samplerDesc = {};
    samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    samplerDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.MinLOD = 0;
    samplerDesc.MaxLOD = D3D11_FLOAT32_MAX;
    hr = g_device->CreateSamplerState(&samplerDesc, &g_sampler);
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

    return CompileShaderToSlot(
        hlsl_code,
        code_length,
        error_buf,
        error_buf_size,
        g_pixelShader
    );
}

SHADER_API int32_t engine_compile_preview_shader(
    const char* hlsl_code,
    int32_t code_length,
    char* error_buf,
    int32_t error_buf_size
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device) return -1;

    return CompileShaderToSlot(
        hlsl_code,
        code_length,
        error_buf,
        error_buf_size,
        g_previewPixelShader
    );
}

static std::string StripHlslComments(const std::string& code) {
    std::string out;
    out.reserve(code.size());
    bool inLineComment = false;
    bool inBlockComment = false;

    for (size_t i = 0; i < code.size(); i++) {
        const char c = code[i];
        const char next = i + 1 < code.size() ? code[i + 1] : '\0';

        if (inLineComment) {
            if (c == '\n' || c == '\r') {
                inLineComment = false;
                out.push_back(c);
            } else {
                out.push_back(' ');
            }
            continue;
        }

        if (inBlockComment) {
            if (c == '*' && next == '/') {
                inBlockComment = false;
                out.append("  ");
                i++;
            } else {
                out.push_back(c == '\n' || c == '\r' ? c : ' ');
            }
            continue;
        }

        if (c == '/' && next == '/') {
            inLineComment = true;
            out.append("  ");
            i++;
            continue;
        }
        if (c == '/' && next == '*') {
            inBlockComment = true;
            out.append("  ");
            i++;
            continue;
        }
        out.push_back(c);
    }

    return out;
}

static std::string ToLowerAscii(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return text;
}

static bool ValidateUserShaderSandbox(
    const std::string& userCode,
    std::string& errorMessage
) {
    const std::string code = ToLowerAscii(StripHlslComments(userCode));
    const char* forbiddenTokens[] = {
        "screentexture.",
        "texture1d",
        "texture2d",
        "texture3d",
        "texturecube",
        "rwtexture",
        "samplerstate",
        "samplercomparisonstate",
        "register(t",
        "register(s",
        ".sample(",
        ".samplelevel(",
        ".samplegrad(",
        ".samplecmp(",
        ".load(",
        ".gather",
    };

    for (const char* token : forbiddenTokens) {
        if (code.find(token) != std::string::npos) {
            errorMessage =
                "Screen texture access is sandboxed. Use "
                "SampleScreen(uv, offsetPx); do not declare textures, "
                "samplers, or t*/s* registers in user shaders.";
            return false;
        }
    }

    return true;
}

static void CopyErrorMessage(
    const char* message,
    char* errorBuf,
    int32_t errorBufSize
) {
    if (!errorBuf || errorBufSize <= 0) return;
    const size_t len = (std::min)(
        strlen(message),
        static_cast<size_t>(errorBufSize - 1)
    );
    memcpy(errorBuf, message, len);
    errorBuf[len] = '\0';
}

static int32_t CompileShaderToSlot(
    const char* hlsl_code,
    int32_t code_length,
    char* error_buf,
    int32_t error_buf_size,
    ID3D11PixelShader*& shaderSlot
) {
    if (error_buf && error_buf_size > 0) error_buf[0] = '\0';
    if (!hlsl_code || code_length < 0) return -1;

    const std::string userCode(
        hlsl_code,
        static_cast<size_t>(code_length)
    );
    std::string validationError;
    if (!ValidateUserShaderSandbox(userCode, validationError)) {
        CopyErrorMessage(validationError.c_str(), error_buf, error_buf_size);
        return 1;
    }

    const std::string compiledCode =
        std::string(kScreenTextureSandboxHeader) + userCode;

    ID3DBlob* psBlob  = nullptr;
    ID3DBlob* psError = nullptr;

    HRESULT hr = D3DCompile(
        compiledCode.c_str(), compiledCode.size(),
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

    SafeRelease(shaderSlot);
    shaderSlot = newPS;
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

    const bool ok = RenderUserShaderToTarget(g_pixelShader, width, height, g_rtv);
    if (ok) {
        g_lastFrameReadbackKind = FrameReadbackKind::Fullscreen;
    }
    return ok ? 0 : -1;
}

SHADER_API int32_t engine_render_preview_frame(int32_t width, int32_t height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device || !g_context || !g_previewPixelShader || !g_vertexShader)
        return -1;

    if (width != g_previewRtWidth || height != g_previewRtHeight) {
        if (!CreatePreviewRenderTarget(width, height))
            return -1;
    }

    const bool ok = RenderUserShaderToTarget(
        g_previewPixelShader, width, height, g_previewRtv
    );
    if (ok) {
        g_lastFrameReadbackKind = FrameReadbackKind::Preview;
    }
    return ok ? 0 : -1;
}

SHADER_API int32_t engine_show_overlay(int32_t width, int32_t height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device || !g_context || !g_vertexShader || !g_compositeShader)
        return -1;

    return EnsureOverlay(width, height) ? 0 : -1;
}

SHADER_API int32_t engine_render_overlay_frame(int32_t width, int32_t height) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device || !g_context || !g_vertexShader)
        return -1;

    const bool usePostProcess = g_postProcessEffect != 0;
    if (!usePostProcess && !g_pixelShader)
        return -1;

    if (!EnsureOverlay(width, height))
        return -1;

    if (width != g_rtWidth || height != g_rtHeight) {
        if (!CreateRenderTarget(width, height))
            return -1;
    }

    if (usePostProcess) {
        if (!RenderPostProcessToTarget(width, height, g_rtv))
            return -1;
    } else {
        if (!RenderUserShaderToTarget(g_pixelShader, width, height, g_rtv))
            return -1;
    }
    g_lastFrameReadbackKind = FrameReadbackKind::Fullscreen;

    return RenderCompositeToOverlay(width, height) ? 0 : -1;
}

SHADER_API void engine_set_filter_visuals(float opacity, float brightness) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_filterOpacity = std::clamp(opacity, 0.0f, 1.0f);
    g_filterBrightness = std::clamp(brightness, -1.0f, 1.0f);
}

SHADER_API void engine_set_post_process_effect(int32_t effect, float intensity) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_postProcessEffect = effect == 1 ? 1 : 0;
    g_postProcessIntensity = std::clamp(intensity, 1.0f, 256.0f);
    if (g_postProcessEffect == 0) {
        ReleaseScreenCaptureResources();
    }
}

SHADER_API void engine_hide_overlay() {
    std::lock_guard<std::mutex> lock(g_mutex);
    ReleaseOverlayResources();
}

SHADER_API int32_t engine_is_overlay_active() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_overlayWindow && IsWindowVisible(g_overlayWindow) ? 1 : 0;
}

SHADER_API int32_t engine_set_region_mask(
    int32_t enabled,
    int32_t inverted,
    int32_t width,
    int32_t height,
    const float* points,
    const int32_t* region_point_counts,
    int32_t region_count
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_device || width <= 0 || height <= 0) return -1;

    if (!enabled) {
        ReleaseMaskResources();
        return 0;
    }

    if (region_count < 0 || (region_count > 0 && !region_point_counts)) {
        return -1;
    }

    int32_t totalPoints = 0;
    for (int32_t i = 0; i < region_count; i++) {
        if (region_point_counts[i] < 0) return -1;
        totalPoints += region_point_counts[i];
    }

    if (totalPoints > 0 && !points) {
        return -1;
    }

    if (totalPoints == 0) {
        const std::vector<uint8_t> emptyMask(1, 0);
        if (!CreateMaskTexture(1, 1, emptyMask)) return -1;
        g_maskEnabled = true;
        g_maskInverted = inverted != 0;
        return 0;
    }

    std::vector<uint8_t> mask(static_cast<size_t>(width) * height, 0);

    int32_t pointOffset = 0;
    for (int32_t region = 0; region < region_count; region++) {
        const int32_t pointCount = region_point_counts[region];
        if (pointCount < 3) {
            pointOffset += pointCount;
            continue;
        }

        const float* regionPoints = points + pointOffset * 2;
        float minX = regionPoints[0];
        float maxX = regionPoints[0];
        float minY = regionPoints[1];
        float maxY = regionPoints[1];
        for (int32_t i = 1; i < pointCount; i++) {
            const float x = regionPoints[i * 2];
            const float y = regionPoints[i * 2 + 1];
            minX = (std::min)(minX, x);
            maxX = (std::max)(maxX, x);
            minY = (std::min)(minY, y);
            maxY = (std::max)(maxY, y);
        }

        const int32_t startX = (std::max)(0, static_cast<int32_t>(std::floor(minX)));
        const int32_t endX = (std::min)(width - 1, static_cast<int32_t>(std::ceil(maxX)));
        const int32_t startY = (std::max)(0, static_cast<int32_t>(std::floor(minY)));
        const int32_t endY = (std::min)(height - 1, static_cast<int32_t>(std::ceil(maxY)));

        for (int32_t y = startY; y <= endY; y++) {
            for (int32_t x = startX; x <= endX; x++) {
                if (PointInPolygon(x + 0.5f, y + 0.5f, regionPoints, pointCount)) {
                    mask[static_cast<size_t>(y) * width + x] = 255;
                }
            }
        }

        pointOffset += pointCount;
    }

    if (!CreateMaskTexture(width, height, mask)) return -1;
    g_maskEnabled = true;
    g_maskInverted = inverted != 0;
    return 0;
}

SHADER_API int32_t engine_get_frame_pixels(uint8_t* out_pixels, int32_t buffer_size) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_context) return -1;

    ID3D11Texture2D* source = nullptr;
    ID3D11Texture2D* staging = nullptr;
    int32_t width = 0;
    int32_t height = 0;

    if (g_lastFrameReadbackKind == FrameReadbackKind::Preview) {
        source = g_previewRenderTarget;
        staging = g_previewStaging;
        width = g_previewRtWidth;
        height = g_previewRtHeight;
    } else if (g_lastFrameReadbackKind == FrameReadbackKind::Fullscreen) {
        source = g_renderTarget;
        staging = g_staging;
        width = g_rtWidth;
        height = g_rtHeight;
    } else {
        return -1;
    }

    if (!source || !staging || width <= 0 || height <= 0) return -1;

    int32_t expected = width * height * 4;
    if (buffer_size < expected) return -1;

    g_context->CopyResource(staging, source);

    D3D11_MAPPED_SUBRESOURCE mapped;
    HRESULT hr = g_context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) return -1;

    const uint8_t* src = static_cast<const uint8_t*>(mapped.pData);
    for (int32_t y = 0; y < height; y++) {
        memcpy(
            out_pixels + y * width * 4,
            src + y * mapped.RowPitch,
            width * 4
        );
    }

    g_context->Unmap(staging, 0);
    return 0;
}

SHADER_API void engine_shutdown() {
    std::lock_guard<std::mutex> lock(g_mutex);
    ReleaseOverlayResources();
    ReleaseMaskResources();
    SafeRelease(g_pixelShader);
    SafeRelease(g_previewPixelShader);
    SafeRelease(g_compositeShader);
    SafeRelease(g_mosaicShader);
    SafeRelease(g_downsampleShader);
    SafeRelease(g_vertexShader);
    SafeRelease(g_inputLayout);
    SafeRelease(g_vertexBuffer);
    SafeRelease(g_cbuffer);
    SafeRelease(g_overlayCbuffer);
    SafeRelease(g_postProcessCbuffer);
    SafeRelease(g_screenTextureCbuffer);
    SafeRelease(g_sampler);
    SafeRelease(g_rtv);
    SafeRelease(g_renderSrv);
    SafeRelease(g_renderTarget);
    SafeRelease(g_staging);
    SafeRelease(g_previewRtv);
    SafeRelease(g_previewRenderTarget);
    SafeRelease(g_previewStaging);
    SafeRelease(g_context);
    SafeRelease(g_device);
    g_rtWidth  = 0;
    g_rtHeight = 0;
    g_previewRtWidth = 0;
    g_previewRtHeight = 0;
    g_lastFrameReadbackKind = FrameReadbackKind::None;
    g_postProcessEffect = 0;
    g_postProcessIntensity = 24.0f;
}
