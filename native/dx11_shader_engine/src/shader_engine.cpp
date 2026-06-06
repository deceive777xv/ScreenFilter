#include "shader_engine.h"

#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dcomp.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

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
static ID3D11ShaderResourceView* g_renderSrv  = nullptr;
static ID3D11Texture2D*        g_staging      = nullptr;
static ID3D11Texture2D*        g_maskTexture  = nullptr;
static ID3D11ShaderResourceView* g_maskSrv    = nullptr;
static int32_t                 g_rtWidth      = 0;
static int32_t                 g_rtHeight     = 0;
static std::mutex              g_mutex;

static HWND                    g_overlayWindow = nullptr;
static IDCompositionDevice*    g_dcompDevice   = nullptr;
static IDCompositionTarget*    g_dcompTarget   = nullptr;
static IDCompositionVisual*    g_dcompVisual   = nullptr;
static IDXGISwapChain1*        g_overlaySwapChain = nullptr;
static ID3D11RenderTargetView* g_overlayRtv    = nullptr;
static ID3D11PixelShader*      g_compositeShader = nullptr;
static ID3D11PixelShader*      g_mosaicShader  = nullptr;
static ID3D11SamplerState*     g_sampler       = nullptr;
static ID3D11Buffer*           g_overlayCbuffer = nullptr;
static ID3D11Buffer*           g_postProcessCbuffer = nullptr;
static IDXGIOutputDuplication* g_outputDuplication = nullptr;
static ID3D11Texture2D*        g_screenTexture = nullptr;
static ID3D11ShaderResourceView* g_screenSrv   = nullptr;
static int32_t                 g_overlayWidth  = 0;
static int32_t                 g_overlayHeight = 0;
static int32_t                 g_screenWidth   = 0;
static int32_t                 g_screenHeight  = 0;
static DXGI_FORMAT             g_screenFormat  = DXGI_FORMAT_UNKNOWN;
static bool                    g_overlayBoundsValid = false;
static int                     g_overlayX      = 0;
static int                     g_overlayY      = 0;
static int                     g_overlayWindowWidth = 0;
static int                     g_overlayWindowHeight = 0;
static HWND                    g_cachedFlutterWindow = nullptr;
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

static void ReleaseOverlaySwapChain() {
    SafeRelease(g_overlayRtv);
    SafeRelease(g_overlaySwapChain);
    g_overlayWidth = 0;
    g_overlayHeight = 0;
}

static void ReleaseScreenFrameResources() {
    SafeRelease(g_screenSrv);
    SafeRelease(g_screenTexture);
    g_screenWidth = 0;
    g_screenHeight = 0;
    g_screenFormat = DXGI_FORMAT_UNKNOWN;
}

static void ReleaseScreenCaptureResources() {
    SafeRelease(g_outputDuplication);
    ReleaseScreenFrameResources();
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
    g_cachedFlutterWindow = nullptr;
    g_lastFlutterWindowSearchTick = 0;
    g_lastOverlayPositionTick = 0;
}

static void EnsureOverlayClickThrough() {
    if (!g_overlayWindow) return;

    LONG_PTR exStyle = GetWindowLongPtrW(g_overlayWindow, GWL_EXSTYLE);
    const LONG_PTR requiredStyles =
        WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE |
        WS_EX_NOREDIRECTIONBITMAP;
    if ((exStyle & requiredStyles) != requiredStyles) {
        exStyle |= requiredStyles;
        exStyle &= ~WS_EX_APPWINDOW;
        SetWindowLongPtrW(g_overlayWindow, GWL_EXSTYLE, exStyle);
        SetWindowPos(
            g_overlayWindow, nullptr, 0, 0, 0, 0,
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                SWP_NOACTIVATE | SWP_FRAMECHANGED
        );
    }
}

static LRESULT CALLBACK OverlayWndProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam
) {
    switch (message) {
        case WM_NCHITTEST:
            return HTTRANSPARENT;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
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

static void PositionOverlayWindow(
    int32_t width,
    int32_t height,
    bool force = false
) {
    if (!g_overlayWindow) return;
    EnsureOverlayClickThrough();

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

    if (g_overlayBoundsValid &&
        x == g_overlayX && y == g_overlayY &&
        w == g_overlayWindowWidth && h == g_overlayWindowHeight) {
        return;
    }

    SetWindowPos(
        g_overlayWindow, HWND_TOPMOST, x, y, w, h,
        SWP_NOACTIVATE | SWP_SHOWWINDOW
    );
    if (flutterWindow) {
        SetWindowPos(
            g_overlayWindow, flutterWindow, x, y, w, h,
            SWP_NOACTIVATE | SWP_SHOWWINDOW
        );
    }

    g_overlayBoundsValid = true;
    g_overlayX = x;
    g_overlayY = y;
    g_overlayWindowWidth = w;
    g_overlayWindowHeight = h;
}

static bool CreateOverlayWindow(int32_t width, int32_t height) {
    if (g_overlayWindow) {
        return true;
    }

    if (!RegisterOverlayWindowClass()) return false;

    g_overlayWindow = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE |
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

    EnsureOverlayClickThrough();
    ShowWindow(g_overlayWindow, SW_SHOWNOACTIVATE);
    SetWindowDisplayAffinity(g_overlayWindow, WDA_EXCLUDEFROMCAPTURE);
    EnsureOverlayClickThrough();
    PositionOverlayWindow(width, height, true);
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
        PositionOverlayWindow(width, height, true);
        return CreateOverlaySwapChain(width, height);
    }
    PositionOverlayWindow(width, height);
    return true;
}

static bool RenderUserShaderToTarget(
    int32_t width, int32_t height, ID3D11RenderTargetView* target
) {
    if (!g_context || !g_pixelShader || !g_vertexShader || !g_cbuffer || !target) {
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
    g_context->PSSetShader(g_pixelShader, nullptr, 0);
    g_context->PSSetConstantBuffers(0, 1, &g_cbuffer);
    g_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_context->Draw(3, 0);

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
    return SUCCEEDED(hr);
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

    return RenderUserShaderToTarget(width, height, g_rtv) ? 0 : -1;
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
        if (!RenderUserShaderToTarget(width, height, g_rtv))
            return -1;
    }

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
    ReleaseOverlayResources();
    ReleaseMaskResources();
    SafeRelease(g_pixelShader);
    SafeRelease(g_compositeShader);
    SafeRelease(g_mosaicShader);
    SafeRelease(g_vertexShader);
    SafeRelease(g_inputLayout);
    SafeRelease(g_vertexBuffer);
    SafeRelease(g_cbuffer);
    SafeRelease(g_overlayCbuffer);
    SafeRelease(g_postProcessCbuffer);
    SafeRelease(g_sampler);
    SafeRelease(g_rtv);
    SafeRelease(g_renderSrv);
    SafeRelease(g_renderTarget);
    SafeRelease(g_staging);
    SafeRelease(g_context);
    SafeRelease(g_device);
    g_rtWidth  = 0;
    g_rtHeight = 0;
    g_postProcessEffect = 0;
    g_postProcessIntensity = 24.0f;
}
