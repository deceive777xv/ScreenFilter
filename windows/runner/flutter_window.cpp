#include "flutter_window.h"

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kConsoleHotkeyId = 0x5346;
constexpr UINT kModNoRepeat = 0x4000;

int GetIntArgument(const flutter::EncodableMap& args,
                   const char* key,
                   int fallback = 0) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto value = std::get_if<int>(&it->second)) {
    return *value;
  }
  if (const auto value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "screen_filter_app/hotkey",
          &flutter::StandardMethodCodec::GetInstance());
  hotkey_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "registerHotkey") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("bad_args", "Expected hotkey argument map.");
            return;
          }

          if (hotkey_registered_) {
            UnregisterHotKey(GetHandle(), kConsoleHotkeyId);
            hotkey_registered_ = false;
          }

          const int modifiers = GetIntArgument(*args, "modifiers");
          const int key_code = GetIntArgument(*args, "keyCode");
          const BOOL ok = RegisterHotKey(
              GetHandle(), kConsoleHotkeyId,
              static_cast<UINT>(modifiers) | kModNoRepeat,
              static_cast<UINT>(key_code));
          hotkey_registered_ = ok != FALSE;
          result->Success(flutter::EncodableValue(hotkey_registered_));
          return;
        }

        if (call.method_name() == "unregisterHotkey") {
          if (hotkey_registered_) {
            UnregisterHotKey(GetHandle(), kConsoleHotkeyId);
            hotkey_registered_ = false;
          }
          result->Success(flutter::EncodableValue(true));
          return;
        }

        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (hotkey_registered_) {
    UnregisterHotKey(GetHandle(), kConsoleHotkeyId);
    hotkey_registered_ = false;
  }
  hotkey_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_HOTKEY &&
      static_cast<int>(wparam) == kConsoleHotkeyId) {
    if (hotkey_channel_) {
      hotkey_channel_->InvokeMethod(
          "hotkeyPressed", std::make_unique<flutter::EncodableValue>());
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
