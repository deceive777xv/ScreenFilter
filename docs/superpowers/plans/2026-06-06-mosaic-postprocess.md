# Mosaic Postprocess Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first real screen post-processing filter: a fullscreen mosaic effect that samples the desktop frame instead of only drawing a transparent overlay.

**Architecture:** Keep the existing generated shader overlay path intact. Add a post-process mode to `ShaderFilterService`, route it through a native `engine_set_post_process_effect` FFI call, and let the DX11 overlay render either the compiled user shader or a built-in mosaic shader fed by a captured screen texture.

**Tech Stack:** Flutter/Dart service and UI, Dart FFI, C++17, Direct3D 11, DXGI output duplication, DirectComposition overlay.

---

### Task 1: Dart API Red Test

**Files:**
- Modify: `test/shader_filter_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add a test proving mosaic can start without compiling a user shader, sets the native post-process effect, and renders through the native overlay path.

- [ ] **Step 2: Run red test**

Run: `flutter test test/shader_filter_service_test.dart -r expanded`

Expected: fail because `ScreenPostProcessEffect` and the new `applyFilter` argument do not exist yet.

### Task 2: Dart Service and FFI Bridge

**Files:**
- Modify: `lib/services/shader_filter_service.dart`
- Modify: `lib/services/dx11_shader_ffi.dart`
- Modify: `test/shader_filter_service_test.dart`

- [ ] **Step 1: Add post-process enum and service state**

Add `ScreenPostProcessEffect { none, mosaic }`, expose `postProcessEffect`, and make renderability mean either a compiled shader or a non-none post-process effect.

- [ ] **Step 2: Add FFI method**

Resolve `engine_set_post_process_effect` and call it whenever filters start, stop, or switch between shader and post-process paths.

- [ ] **Step 3: Run service test**

Run: `flutter test test/shader_filter_service_test.dart -r expanded`

Expected: pass once the fake engine records the effect.

### Task 3: Native Mosaic Pipeline

**Files:**
- Modify: `native/dx11_shader_engine/include/shader_engine.h`
- Modify: `native/dx11_shader_engine/src/shader_engine.cpp`

- [ ] **Step 1: Add C ABI**

Declare and implement `engine_set_post_process_effect(int32_t effect, float intensity)`.

- [ ] **Step 2: Add screen capture texture**

Use DXGI output duplication to capture output 0 into a shader-resource texture. Reuse the last captured texture on timeout, and reset duplication on access loss.

- [ ] **Step 3: Add mosaic pixel shader**

Compile a built-in mosaic shader at init. It samples the captured screen texture at block centers using a fixed block size supplied by `intensity`.

- [ ] **Step 4: Route overlay rendering**

When post-process effect is mosaic, render the mosaic shader into `g_renderTarget`; otherwise keep the existing user shader path.

### Task 4: UI Entry

**Files:**
- Modify: `lib/ui/console_panel.dart`

- [ ] **Step 1: Add mosaic tile handler**

Add a tile in the existing "屏幕特效" row. The tile calls `applyFilter(..., postProcessEffect: ScreenPostProcessEffect.mosaic)` and reuses the current active-effect highlighting and stop behavior.

### Task 5: Verification

**Files:**
- Build/test only

- [ ] **Step 1: Run Dart tests with elevation**

Run: `flutter test test/shader_filter_service_test.dart -r expanded`

Expected: all tests pass.

- [ ] **Step 2: Run Windows build with elevation**

Run: `flutter build windows --debug`

Expected: build succeeds and compiles `dx11_shader_engine.dll`.
