import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

// ── Structs ─────────────────────────────────────────────────────────

final class RECT extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final class POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

// ── Function signatures ─────────────────────────────────────────────

// GetForegroundWindow
final _getForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

// GetWindowRect
final _getWindowRect = _user32.lookupFunction<
    Int32 Function(IntPtr hWnd, Pointer<RECT> lpRect),
    int Function(int hWnd, Pointer<RECT> lpRect)>('GetWindowRect');

// GetWindowThreadProcessId
final _getWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId),
    int Function(
        int hWnd, Pointer<Uint32> lpdwProcessId)>('GetWindowThreadProcessId');

// OpenProcess
const int _processQueryLimitedInformation = 0x1000;
final _openProcess = _kernel32.lookupFunction<
    IntPtr Function(
        Uint32 dwDesiredAccess, Int32 bInheritHandle, Uint32 dwProcessId),
    int Function(
        int dwDesiredAccess, int bInheritHandle, int dwProcessId)>('OpenProcess');

// QueryFullProcessImageNameW
final _queryFullProcessImageName = _kernel32.lookupFunction<
    Int32 Function(IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName,
        Pointer<Uint32> lpdwSize),
    int Function(int hProcess, int dwFlags, Pointer<Utf16> lpExeName,
        Pointer<Uint32> lpdwSize)>('QueryFullProcessImageNameW');

// CloseHandle
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr hObject), int Function(int hObject)>(
        'CloseHandle');

// GetCursorPos
final _getCursorPos = _user32.lookupFunction<
    Int32 Function(Pointer<POINT>),
    int Function(Pointer<POINT>)>('GetCursorPos');

// ── Public API ──────────────────────────────────────────────────────

/// Get the foreground window rect in physical screen pixels.
Rect? getForegroundWindowRect() {
  final hwnd = _getForegroundWindow();
  if (hwnd == 0) return null;
  final rect = calloc<RECT>();
  try {
    if (_getWindowRect(hwnd, rect) != 0) {
      return Rect.fromLTRB(
        rect.ref.left.toDouble(),
        rect.ref.top.toDouble(),
        rect.ref.right.toDouble(),
        rect.ref.bottom.toDouble(),
      );
    }
    return null;
  } finally {
    calloc.free(rect);
  }
}

/// Get the process name (exe filename) of the foreground window.
String? getForegroundProcessName() {
  final hwnd = _getForegroundWindow();
  if (hwnd == 0) return null;

  final pidPtr = calloc<Uint32>();
  try {
    _getWindowThreadProcessId(hwnd, pidPtr);
    final pid = pidPtr.cast<Uint32>().asTypedList(1)[0];
    if (pid == 0) return null;

    final hProcess = _openProcess(_processQueryLimitedInformation, 0, pid);
    if (hProcess == 0) return null;

    const maxPath = 260;
    final nameBuf = calloc<Uint16>(maxPath);
    final sizePtr = calloc<Uint32>();
    sizePtr.cast<Uint32>().asTypedList(1)[0] = maxPath;

    try {
      final result =
          _queryFullProcessImageName(hProcess, 0, nameBuf.cast(), sizePtr);
      if (result != 0) {
        final len = sizePtr.cast<Uint32>().asTypedList(1)[0];
        final fullPath =
            nameBuf.cast<Utf16>().toDartString(length: len);
        final lastSlash = fullPath.lastIndexOf('\\');
        return lastSlash >= 0 ? fullPath.substring(lastSlash + 1) : fullPath;
      }
      return null;
    } finally {
      _closeHandle(hProcess);
      calloc.free(nameBuf);
      calloc.free(sizePtr);
    }
  } finally {
    calloc.free(pidPtr);
  }
}

/// Get the global mouse cursor position in physical screen pixels.
Offset getGlobalCursorPos() {
  final pt = calloc<POINT>();
  try {
    _getCursorPos(pt);
    return Offset(pt.ref.x.toDouble(), pt.ref.y.toDouble());
  } finally {
    calloc.free(pt);
  }
}
