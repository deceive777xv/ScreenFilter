# ScreenFilter

ScreenFilter 是一个面向 Windows 的桌面屏幕滤镜工具，使用 Flutter 构建界面，结合 DX11 原生模块与 Shader 能力实现高性能的全屏覆盖滤镜。

当前仓库只保留 Windows 版本所需文件，不再包含 Android、iOS、Linux、macOS、Web 及与项目运行无关的辅助目录。

## 当前能力

- 全屏置顶透明覆盖层，默认鼠标穿透，不影响正常使用桌面和应用
- 托盘驻留与控制面板开关
- 亮度、透明度、基础色等基础滤镜调节
- 预设中心，用于快速切换常用滤镜配置
- 顶层叠加组件：时钟、标语、水印
- 高级遮罩能力：专注模式、聚光灯、区域遮罩绘制
- 进程绑定预设，可按进程名自动切换滤镜配置
- Shader 沙盒与内置屏幕特效，支持基于 DX11/HLSL 的动态效果
- 配置持久化，以及开机启动控制

## 技术栈

- Flutter 桌面应用
- Windows Runner
- DirectX 11 原生动态库：native/dx11_shader_engine
- Fragment Shader：shaders/filter.frag
- 本地配置存储：shared_preferences

## 目录说明

- lib: Flutter 应用界面、状态管理与业务逻辑
- windows: Windows 桌面壳与构建配置
- native/dx11_shader_engine: DX11 Shader 原生库
- assets: 图标与静态资源
- shaders: Flutter 侧使用的 Shader 资源

## 开发环境

- Windows 10 或 Windows 11
- Flutter SDK 3.11+
- Visual Studio 2022，并安装 Desktop development with C++

## 本地运行

```bash
flutter pub get
flutter run -d windows
```

## 打包

```bash
flutter build windows
```

构建产物默认位于 build/windows/x64/runner/Release。

## 说明

该项目当前仅维护 Windows 桌面版本，仓库内容也已经按 Windows-only 形态整理。若后续需要扩展到其他平台，建议基于 Flutter 重新生成对应平台工程，并按实际实现逐步补齐平台能力。
