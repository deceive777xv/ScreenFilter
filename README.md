# ScreenFilter

ScreenFilter 是一个 Windows-only 桌面屏幕滤镜工具。它使用 Flutter 构建控制台与覆盖层 UI，结合 Win32、DirectX 11、DirectComposition 和 HLSL shader，在桌面上方绘制透明、置顶、默认鼠标穿透的全屏滤镜。

当前仓库只维护 Windows 桌面版本，非 Windows 平台工程已移除。

## 当前能力

- 全屏透明覆盖层：置顶显示、隐藏任务栏入口、默认鼠标穿透，不影响正常操作桌面和其他应用。
- 控制台与托盘：托盘左键显示/隐藏控制面板，右键提供滤镜、聚光灯、快捷键、常用预设和退出入口。
- 全局快捷键：可通过 Win32 `RegisterHotKey` 切换控制台显示状态。
- 基础滤镜：颜色、透明度、亮度、最近颜色和常用预设。
- 顶层组件：时钟、标语、水印，可在控制台打开时拖动和配置。
- 高级遮罩：专注模式、聚光灯、多边形区域遮罩和反向遮罩。
- 自动化规则：按前台进程 exe 名称自动应用预设，离开匹配进程后恢复原滤镜。
- Shader 沙盒：编辑、编译、预览和导入导出 `.shader` HLSL 预设，可应用为静态或动态全屏滤镜。
- 屏幕特效：雪花、星星、萤火虫、极光、阳光等 HLSL 叠加效果，以及基于桌面截图纹理的马赛克后处理。
- DX11 native overlay：优先通过原生 DirectComposition 透明 overlay 渲染动态滤镜，高 DPI 下使用物理像素尺寸。
- 配置持久化：基础滤镜、组件、高级配置、快捷键、自动化规则、最近 native 滤镜状态和开机启动偏好。
- 配置导入导出：导出主要应用配置，导入后同步基础设置、高级功能、自动化和快捷键。

## 技术栈

| 层级 | 技术/依赖 | 作用 |
| --- | --- | --- |
| App UI | Flutter Material、CustomPaint、FragmentShader | 控制台、基础滤镜、组件、遮罩编辑 |
| 窗口控制 | `window_manager` | 全屏透明窗口、置顶、鼠标穿透 |
| 系统托盘 | `system_tray` | 托盘图标、右键菜单、快捷控制 |
| 配置存储 | `shared_preferences` | 本地偏好和 JSON 配置 |
| 文件选择 | `file_selector` | 配置与 shader 导入导出 |
| Native bridge | `dart:ffi`、`ffi`、Flutter MethodChannel | DX11 DLL 调用和全局快捷键 |
| Native GPU | Direct3D 11、DXGI Output Duplication、DirectComposition | HLSL 编译、屏幕采样、透明 overlay 渲染 |
| Win32 辅助 | `user32.dll`、`kernel32.dll` | 前台窗口/进程、鼠标、热键、启动项 |

## 目录结构

```text
lib/
  main.dart                         应用入口、窗口/托盘/全局状态、覆盖层组合
  models/                           滤镜、组件、高级配置、shader 和屏幕特效模型
  services/                         配置、托盘布局、Win32 轮询、DX11 FFI、自动化与热键服务
  ui/                               控制台、高级页、Shader 沙盒、颜色选择器、覆盖层组件

native/dx11_shader_engine/
  include/shader_engine.h           DX11 engine C ABI
  src/shader_engine.cpp             D3D11、DXGI、DirectComposition 和遮罩实现
  CMakeLists.txt                    原生 DLL 构建配置

windows/                            Flutter Windows runner、MethodChannel 热键和 CMake 集成
shaders/filter.frag                 Flutter 侧基础滤镜 shader
assets/                             图标与静态资源
test/                               Flutter/Dart 单元与组件测试
docs/TECHNICAL_OVERVIEW.md          维护者技术说明
```

## 开发环境

- Windows 10 或 Windows 11。
- Flutter SDK，项目约束为 Dart `^3.11.0`。
- Visual Studio 2022，并安装 **Desktop development with C++**。
- Windows SDK 和 DirectX 相关开发库。

## 本地运行

```powershell
flutter pub get
flutter run -d windows
```

## 测试

```powershell
flutter test
```

## 打包

```powershell
flutter build windows --release
```

Release 产物默认位于：

```text
build/windows/x64/runner/Release/screen_filter_app.exe
```

Windows CMake 会同时构建 `native/dx11_shader_engine`，并把 `dx11_shader_engine.dll` 复制到可执行文件旁边。Dart FFI 运行时会从 `Platform.resolvedExecutable` 所在目录加载这个 DLL。

## 维护说明

- 更完整的架构、渲染管线、native ABI、配置模型和扩展指南见 [docs/TECHNICAL_OVERVIEW.md](docs/TECHNICAL_OVERVIEW.md)。
- DX11 overlay 是动态 shader 的首选路径；若创建或渲染失败，会回退到 GPU 读回 + Flutter `RawImage`，但高分辨率下成本更高。
- 修改 native C ABI 时，需要同步 `shader_engine.h`、`shader_engine.cpp` 和 `lib/services/dx11_shader_ffi.dart`。
- 修改配置模型时，需要同步 `AppConfig` 导入导出、`SettingsService` 持久化和相关测试。
