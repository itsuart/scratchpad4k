//! Thin bindings for the Win32 GUI APIs (user32, gdi32, comdlg32, shcore) that
//! `std.os.windows` does not ship, plus the constants the app relies on.

const std = @import("std");
const win = std.os.windows;

pub const BOOL = win.BOOL;
pub const DWORD = win.DWORD;
pub const UINT = win.UINT;
pub const WCHAR = win.WCHAR;
/// Removed from `std.os.windows` in 0.16; defined here.
pub const WPARAM = usize;
pub const LPARAM = win.LPARAM;
/// Removed from `std.os.windows` in 0.16; defined here (was `LONG_PTR`).
pub const LRESULT = isize;
pub const HWND = win.HWND;
pub const HINSTANCE = win.HINSTANCE;
pub const HANDLE = win.HANDLE;
pub const LPWSTR = win.LPWSTR;
pub const LPCWSTR = win.LPCWSTR;
/// Removed from `std.os.windows` in 0.16; defined here (LONG = i32).
pub const RECT = extern struct {
    left: win.LONG,
    top: win.LONG,
    right: win.LONG,
    bottom: win.LONG,
};
/// Removed from `std.os.windows` in 0.16; defined here (LONG = i32).
pub const POINT = extern struct {
    x: win.LONG,
    y: win.LONG,
};
/// Removed from `std.os.windows` in 0.16; defined here.
pub const HRESULT = c_long;
pub const MAX_PATH = win.MAX_PATH;
pub const INVALID_HANDLE_VALUE = win.INVALID_HANDLE_VALUE;

// file access constants (removed from `std.os.windows` in 0.16)
pub const GENERIC_WRITE = 0x40000000;
pub const FILE_SHARE_READ = 0x00000001;
pub const CREATE_ALWAYS = 2;
pub const FILE_ATTRIBUTE_NORMAL = 0x80;

// ---------------------------------------------------------------- handles

pub const HICON = *opaque {};
pub const HCURSOR = *opaque {};
pub const HBRUSH = *opaque {};
pub const HFONT = *opaque {};
pub const HMENU = *opaque {};
pub const HMONITOR = *opaque {};

// ---------------------------------------------------------------- structs

pub const WNDPROC = *const fn (hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT;

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: u32,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON,
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD,
    rcMonitor: RECT,
    rcWork: RECT,
    dwFlags: DWORD,
};

pub const LOGFONTW = extern struct {
    lfHeight: c_long,
    lfWidth: c_long,
    lfEscapement: c_long,
    lfOrientation: c_long,
    lfWeight: c_long,
    lfItalic: u8,
    lfUnderline: u8,
    lfStrikeOut: u8,
    lfCharSet: u8,
    lfOutPrecision: u8,
    lfClipPrecision: u8,
    lfQuality: u8,
    lfPitchAndFamily: u8,
    lfFaceName: [32]WCHAR,
};

pub const NONCLIENTMETRICSW = extern struct {
    cbSize: DWORD,
    iBorderWidth: c_int,
    iScrollWidth: c_int,
    iScrollHeight: c_int,
    iCaptionWidth: c_int,
    iCaptionHeight: c_int,
    lfCaptionFont: LOGFONTW,
    iSmCaptionWidth: c_int,
    iSmCaptionHeight: c_int,
    lfSmCaptionFont: LOGFONTW,
    iMenuWidth: c_int,
    iMenuHeight: c_int,
    lfMenuFont: LOGFONTW,
    lfStatusFont: LOGFONTW,
    lfMessageFont: LOGFONTW,
    iPaddedBorderWidth: c_int,
};

pub const OPENFILENAMEW = extern struct {
    lStructSize: DWORD,
    hwndOwner: ?HWND,
    hInstance: ?HINSTANCE,
    lpstrFilter: ?LPCWSTR,
    lpstrCustomFilter: ?LPWSTR,
    nMaxCustFilter: DWORD,
    nFilterIndex: DWORD,
    lpstrFile: LPWSTR,
    nMaxFile: DWORD,
    lpstrFileTitle: ?LPWSTR,
    nMaxFileTitle: DWORD,
    lpstrInitialDir: ?LPCWSTR,
    lpstrTitle: ?LPCWSTR,
    Flags: DWORD,
    nFileOffset: u16,
    nFileExtension: u16,
    lpstrDefExt: ?LPCWSTR,
    lCustData: LPARAM,
    lpfnHook: ?*anyopaque,
    lpTemplateName: ?LPCWSTR,
    pvReserved: ?*anyopaque,
    dwReserved: DWORD,
    FlagsEx: DWORD,
};

// ---------------------------------------------------------------- kernel32
// Zig 0.16's std no longer ships the raw kernel32 externs we need, so declare
// them here (ABI-identical to the ones that used to live in `std.os.windows`).

pub extern "kernel32" fn CreateFileW(
    lpFileName: LPCWSTR,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*win.SECURITY_ATTRIBUTES,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) callconv(.winapi) HANDLE;

pub extern "kernel32" fn WriteFile(
    in_hFile: HANDLE,
    in_lpBuffer: [*]const u8,
    in_nNumberOfBytesToWrite: DWORD,
    out_lpNumberOfBytesWritten: ?*DWORD,
    in_out_lpOverlapped: ?*anyopaque,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn FormatMessageW(
    dwFlags: DWORD,
    lpSource: ?win.LPCVOID,
    dwMessageId: win.Win32Error,
    dwLanguageId: DWORD,
    lpBuffer: LPWSTR,
    nSize: DWORD,
    arguments: ?*anyopaque,
) callconv(.winapi) DWORD;

// ---------------------------------------------------------------- user32

pub extern "user32" fn RegisterClassExW(wndClassEx: *const WNDCLASSEXW) callconv(.winapi) u16;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: LPCWSTR,
    lpWindowName: ?LPCWSTR,
    dwStyle: u32,
    x: c_int,
    y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;
pub extern "user32" fn PostMessageW(hWnd: ?HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn SendMessageW(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn SetFocus(hWnd: ?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn GetFocus() callconv(.winapi) ?HWND;
pub extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(.winapi) c_short;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn MoveWindow(hWnd: HWND, x: c_int, y: c_int, nWidth: c_int, nHeight: c_int, bRepaint: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: ?HWND, x: c_int, y: c_int, cx: c_int, cy: c_int, uFlags: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn MessageBoxW(hWnd: ?HWND, lpText: LPCWSTR, lpCaption: LPCWSTR, uType: UINT) callconv(.winapi) c_int;
pub extern "user32" fn MonitorFromWindow(hWnd: HWND, dwFlags: DWORD) callconv(.winapi) ?HMONITOR;
pub extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: LPCWSTR) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn GetDpiForSystem() callconv(.winapi) UINT;
pub extern "user32" fn SystemParametersInfoW(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn SystemParametersInfoForDpi(uiAction: UINT, uiParam: UINT, pvParam: ?*anyopaque, fWinIni: UINT, dpi: UINT) callconv(.winapi) BOOL;

// ---------------------------------------------------------------- gdi32

pub extern "gdi32" fn CreateFontIndirectW(lplf: *const LOGFONTW) callconv(.winapi) ?HFONT;

// ---------------------------------------------------------------- comdlg32

pub extern "comdlg32" fn GetSaveFileNameW(lpofn: *OPENFILENAMEW) callconv(.winapi) BOOL;
pub extern "comdlg32" fn CommDlgExtendedError() callconv(.winapi) DWORD;

// ---------------------------------------------------------------- shcore

pub extern "shcore" fn SetProcessDpiAwareness(value: c_int) callconv(.winapi) HRESULT;

// ---------------------------------------------------------------- constants

// class styles
pub const CS_HREDRAW = 0x0002;
pub const CS_VREDRAW = 0x0001;

pub const COLOR_WINDOW = 5;
pub const IDC_ARROW = 32512;

// window styles
pub const WS_OVERLAPPEDWINDOW = 0x00CF0000;
pub const WS_CHILD = 0x40000000;
pub const WS_VISIBLE = 0x10000000;
pub const WS_VSCROLL = 0x00200000;
pub const WS_EX_CLIENTEDGE = 0x00000200;

// edit control styles
pub const ES_MULTILINE = 0x0004;
pub const ES_READONLY = 0x0800;

// SetWindowPos flags
pub const SWP_NOSIZE = 0x0001;
pub const SWP_NOZORDER = 0x0004;
pub const SWP_NOACTIVATE = 0x0010;
pub const SWP_NOOWNERZORDER = 0x0200;
pub const SWP_ASYNCWINDOWPOS = 0x4000;

pub const MONITOR_DEFAULTTONULL = 0;

// window messages
pub const WM_GETTEXT = 0x000D;
pub const WM_GETTEXTLENGTH = 0x000E;
pub const WM_CLOSE = 0x0010;
pub const WM_SETFONT = 0x0030;
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_COMMAND = 0x0111;
pub const WM_SIZING = 0x0214;
pub const WM_ACTIVATE = 0x0006;
pub const WM_SIZE = 0x0005;
pub const WM_DPICHANGED = 0x02E0;

// edit control messages / notifications
pub const EM_SETSEL = 0x00B1;
pub const EN_UPDATE = 0x0400;

pub const WA_INACTIVE = 0;

// virtual key codes
pub const VK_TAB = 0x09;
pub const VK_SHIFT = 0x10;
pub const VK_CONTROL = 0x11;
pub const VK_ESCAPE = 0x1B;

pub const SW_SHOW = 5;

pub const SPI_GETNONCLIENTMETRICS = 0x002A;

// OPENFILENAME flags
pub const OFN_NOTESTFILECREATE = 0x00010000;
pub const OFN_LONGNAMES = 0x00200000;
pub const OFN_DONTADDTORECENT = 0x02000000;
pub const OFN_FORCESHOWHIDDEN = 0x10000000;

// MessageBox flags
pub const MB_OK = 0x0000;
pub const MB_ICONERROR = 0x0010;

pub const PROCESS_PER_MONITOR_DPI_AWARE = 2;

// ---------------------------------------------------------------- helpers

/// Low 16 bits of `x` (LOWORD), works for both `usize` and `isize` arguments.
pub inline fn loword(x: anytype) u16 {
    const unsigned = std.meta.Int(.unsigned, @bitSizeOf(@TypeOf(x)));
    return @truncate(@as(u64, @bitCast(@as(unsigned, x))));
}

/// High 16 bits of `x` (HIWORD), works for both `usize` and `isize` arguments.
pub inline fn hiword(x: anytype) u16 {
    const unsigned = std.meta.Int(.unsigned, @bitSizeOf(@TypeOf(x)));
    return @truncate(@as(u64, @bitCast(@as(unsigned, x))) >> 16);
}
