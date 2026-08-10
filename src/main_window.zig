//! The main window of scratchpad4k (the Zig counterpart of `main_window.cpp`).

const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const string_conversions = @import("helpers/string_conversions.zig");
const error_message = @import("helpers/error_message.zig");
const WindowMsgDispatcher = @import("window_msg_dispatcher.zig").WindowMsgDispatcher;
const WindowMsgProcessor = @import("window_msg_dispatcher.zig").WindowMsgProcessor;

const WND_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("scratchpad4k-main");
const APP_NAME = std.unicode.utf8ToUtf16LeStringLiteral("Scratchpad4k");
const APP_NAME_EMPTY = std.unicode.utf8ToUtf16LeStringLiteral("Scratchpad4k (empty)");
const EDIT_CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("edit");

const DEFAULT_NON_SCALED_DPI: u32 = 96;

const INVALID_FILE_NAME_CHARACTERS = std.unicode.utf8ToUtf16LeStringLiteral("/\\<>:\"|?*");
const EMPTY_FILE_NAME = std.unicode.utf8ToUtf16LeStringLiteral("(empty)");
const EXTENDED_LENGTH_PREFIX = std.unicode.utf8ToUtf16LeStringLiteral("\\\\?\\");

const SUGGESTED_FILE_NAME_MAX_LENGTH = 100;
const SAVE_DIALOG_BUFFER_WCHARS = 33 * 1024;

/// Set by `MainWindow.init` when a Win32 call fails, so `main` can report the code.
pub var last_init_error: ?win.Win32Error = null;

// ---------------------------------------------------------------- Statistics

/// Extracts the numbers found in `content` and computes basic statistics
/// (min/max/sum/count/average/max deviation), mirroring the C++ `Statistics`.
const Statistics = struct {
    min: u64,
    max: u64,
    sum: u64,
    n_numbers: u64,
    average: u64,
    max_deviation: u64,

    fn fromString(content: []const u16) Statistics {
        var result = Statistics{
            .min = std.math.maxInt(u64),
            .max = 0,
            .sum = 0,
            .n_numbers = 0,
            .average = 0,
            .max_deviation = 0,
        };

        var rest = content;
        while (rest.len != 0) {
            rest = skipNonDigits(rest);

            var current_number: u64 = 0;
            var digit_chars_skipped: usize = 0;
            for (rest) |c| {
                if (isDigit(c)) {
                    // wrapping arithmetic, same as the C++ unsigned overflow
                    current_number = current_number *% 10 +% (c - '0');
                    digit_chars_skipped += 1;
                } else break;
            }

            if (digit_chars_skipped != 0) {
                result.onNewNumber(current_number);
                rest = rest[digit_chars_skipped..];
            }
        }

        if (result.n_numbers >= 2) {
            const average = std.math.round(
                @as(f64, @floatFromInt(result.sum)) / @as(f64, @floatFromInt(result.n_numbers)),
            );
            result.average = @intFromFloat(average);
            result.max_deviation = @max(result.max -% result.average, result.average -% result.min);
        }

        return result;
    }

    fn skipNonDigits(content: []const u16) []const u16 {
        var skipped: usize = 0;
        for (content) |c| {
            if (isDigit(c)) break;
            skipped += 1;
        }
        return content[skipped..];
    }

    fn isDigit(c: u16) bool {
        return c >= '0' and c <= '9';
    }

    fn onNewNumber(self: *Statistics, new_number: u64) void {
        self.n_numbers += 1;
        self.min = @min(self.min, new_number);
        self.max = @max(self.max, new_number);
        self.sum +%= new_number;
    }

    fn toString(self: *const Statistics, buffer: *std.ArrayListUnmanaged(u16), allocator: std.mem.Allocator) !void {
        buffer.clearRetainingCapacity();
        if (self.n_numbers < 2) {
            try appendAsciiUtf16(buffer, allocator, "Not enough numbers detected (need at least 2).");
            return;
        }

        const formatted = try std.fmt.allocPrint(
            allocator,
            "Avg={} +-{}, Min={}, Max={}, Sum={}, nNumbers={}",
            .{
                self.average,
                self.max_deviation,
                self.min,
                self.max,
                self.sum,
                self.n_numbers,
            },
        );
        defer allocator.free(formatted);
        try appendAsciiUtf16(buffer, allocator, formatted);
    }
};

// ---------------------------------------------------------------- helpers

/// Appends an ASCII string into a UTF-16 buffer (each byte becomes one WCHAR).
fn appendAsciiUtf16(buffer: *std.ArrayListUnmanaged(u16), allocator: std.mem.Allocator, ascii: []const u8) !void {
    try buffer.ensureUnusedCapacity(allocator, ascii.len);
    for (ascii) |ch| buffer.appendAssumeCapacity(ch);
}

fn isButtonDown(virtual_key: c_int) bool {
    const BTN_DOWN: c_int = 0x8000;
    return (@as(c_int, win32.GetKeyState(virtual_key)) & BTN_DOWN) != 0;
}

/// Fetches the whole text of an edit control into `result` (no trailing NUL).
fn getWindowText(allocator: std.mem.Allocator, h_edit: win32.HWND, result: *std.ArrayListUnmanaged(u16)) !void {
    const length_without_null = win32.SendMessageW(h_edit, win32.WM_GETTEXTLENGTH, 0, 0);
    if (length_without_null == 0) {
        result.clearRetainingCapacity();
        return;
    }

    try result.resize(allocator, @intCast(length_without_null + 1));
    const characters_copied = win32.SendMessageW(
        h_edit,
        win32.WM_GETTEXT,
        result.items.len,
        @intCast(@intFromPtr(result.items.ptr)),
    );
    result.shrinkRetainingCapacity(@intCast(characters_copied));
}

/// Returns the whole text of an edit control as a fresh allocation.
fn getWindowTextAlloc(allocator: std.mem.Allocator, h_edit: win32.HWND) ![]u16 {
    var buffer: std.ArrayListUnmanaged(u16) = .empty;
    defer buffer.deinit(allocator);
    try getWindowText(allocator, h_edit, &buffer);
    return allocator.dupe(u16, buffer.items);
}

fn centerWindow(hwnd: win32.HWND) void {
    var window_rect: win32.RECT = undefined;
    if (!win32.GetWindowRect(hwnd, &window_rect).toBool()) return;

    const h_monitor = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONULL) orelse return;

    var monitor_info: win32.MONITORINFO = undefined;
    monitor_info.cbSize = @sizeOf(win32.MONITORINFO);
    if (!win32.GetMonitorInfoW(h_monitor, &monitor_info).toBool()) return;

    const monitor_width: i64 = monitor_info.rcWork.right - monitor_info.rcWork.left;
    const window_width: i64 = window_rect.right - window_rect.left;
    const middle_x: i64 = @divTrunc(monitor_width - window_width, 2);
    if (middle_x > 0) {
        // the window is narrower than the monitor work area
        window_rect.left = monitor_info.rcWork.left + @as(c_long, @intCast(middle_x));
    }

    const monitor_height: i64 = monitor_info.rcWork.bottom - monitor_info.rcWork.top;
    const window_height: i64 = window_rect.bottom - window_rect.top;
    const middle_y: i64 = @divTrunc(monitor_height - window_height, 2);
    if (middle_y > 0) {
        // the window is shorter than the monitor work area
        window_rect.top = monitor_info.rcWork.top + @as(c_long, @intCast(middle_y));
    }

    // this does not solve the original problem with Emacs
    // (because it sets its size much later after creation of the window)
    _ = win32.SetWindowPos(
        hwnd,
        null,
        window_rect.left,
        window_rect.top,
        0,
        0,
        win32.SWP_ASYNCWINDOWPOS | win32.SWP_NOACTIVATE | win32.SWP_NOOWNERZORDER | win32.SWP_NOSIZE,
    );
}

fn writeToFile(handle: win.HANDLE, data: []const u8) bool {
    var bytes_written: win.DWORD = 0;
    return win32.WriteFile(handle, data.ptr, @intCast(data.len), &bytes_written, null).toBool();
}

/// Creates the UI font: the menu font scaled to the given DPI. If the system
/// metrics cannot be retrieved (e.g. a malformed `NonClientMetrics` registry
/// value makes `SPI_GETNONCLIENTMETRICS` return without filling the struct),
/// falls back to the classic UI font.
fn createFont(dpi: u32) win32.HFONT {
    var logfont = std.mem.zeroes(win32.LOGFONTW);
    var got_metrics = false;

    var metrics = std.mem.zeroes(win32.NONCLIENTMETRICSW);
    metrics.cbSize = @sizeOf(win32.NONCLIENTMETRICSW);
    if (win32.SystemParametersInfoForDpi(win32.SPI_GETNONCLIENTMETRICS, metrics.cbSize, &metrics, 0, dpi).toBool()) {
        got_metrics = metrics.lfMenuFont.lfFaceName[0] != 0;
    }
    if (!got_metrics) {
        // The ForDpi call was a no-op; try the classic call (same face name,
        // only lfHeight is DPI-dependent and we override it below anyway).
        metrics = std.mem.zeroes(win32.NONCLIENTMETRICSW);
        metrics.cbSize = @sizeOf(win32.NONCLIENTMETRICSW);
        if (win32.SystemParametersInfoW(win32.SPI_GETNONCLIENTMETRICS, metrics.cbSize, &metrics, 0).toBool()) {
            got_metrics = metrics.lfMenuFont.lfFaceName[0] != 0;
        }
    }

    if (got_metrics) {
        logfont = metrics.lfMenuFont;
    } else {
        const FALLBACK_FACE = std.unicode.utf8ToUtf16LeStringLiteral("MS Shell Dlg 2");
        logfont.lfCharSet = 1; // DEFAULT_CHARSET
        @memcpy(logfont.lfFaceName[0..FALLBACK_FACE.len], FALLBACK_FACE);
    }

    // For some reason fonts are scaled with 72 ppi as the default.
    logfont.lfHeight = @divTrunc(16 * @as(c_long, @intCast(dpi)), 72);
    return win32.CreateFontIndirectW(&logfont) orelse
        std.debug.panic("CreateFontIndirectW() failed", .{});
}

/// Shows "<system message>(error code = <code>)" for a failed Win32 call.
fn showFileError(allocator: std.mem.Allocator, parent: win32.HWND, comptime caption: []const u8, last_error: win.Win32Error) !void {
    const error_description = try error_message.getErrorMessageW(allocator, last_error);
    defer allocator.free(error_description);
    const error_description_utf8 = try string_conversions.toUtf8(allocator, error_description);
    defer allocator.free(error_description_utf8);
    try error_message.showErrorMessageBox(allocator, parent, caption, "{s}(error code = {})", .{
        error_description_utf8,
        last_error,
    });
}

// ---------------------------------------------------------------- MainWindow

pub const MainWindow = struct {
    dispatcher: *WindowMsgDispatcher,
    h_instance: win.HINSTANCE,
    allocator: std.mem.Allocator,

    main_wnd: win32.HWND = undefined,
    content_edit_wnd: win32.HWND = undefined,
    stats_edit_wnd: win32.HWND = undefined,

    dpi: u32,

    /// Current UI font (recreated when the DPI changes).
    font: ?win32.HFONT = null,

    buffer_for_content: std.ArrayListUnmanaged(u16) = .empty,
    buffer_for_stats: std.ArrayListUnmanaged(u16) = .empty,

    pub fn init(self: *MainWindow, allocator: std.mem.Allocator, dispatcher: *WindowMsgDispatcher, h_instance: win.HINSTANCE) !void {
        self.* = .{
            .dispatcher = dispatcher,
            .h_instance = h_instance,
            .allocator = allocator,
            .dpi = win32.GetDpiForSystem(),
        };

        {
            var wcex = std.mem.zeroes(win32.WNDCLASSEXW);
            wcex.cbSize = @sizeOf(win32.WNDCLASSEXW);
            wcex.style = win32.CS_HREDRAW | win32.CS_VREDRAW;
            wcex.lpfnWndProc = WindowMsgDispatcher.dispatchingProc;
            wcex.cbClsExtra = 0;
            wcex.cbWndExtra = 0;
            wcex.hInstance = h_instance;
            wcex.hIcon = null;
            wcex.hCursor = win32.LoadCursorW(null, @ptrFromInt(win32.IDC_ARROW));
            wcex.hbrBackground = @ptrFromInt(win32.COLOR_WINDOW + 1);
            wcex.lpszMenuName = null;
            wcex.lpszClassName = WND_CLASS_NAME;
            wcex.hIconSm = null;
            if (win32.RegisterClassExW(&wcex) == 0) {
                // The C++ code ignored registration failures; keep doing the same,
                // but remember the code in case window creation then fails.
                last_init_error = win.GetLastError();
                std.debug.print("RegisterClassExW failed with error code {}\n", .{last_init_error.?});
            }
        }

        try dispatcher.bindToNextNewWindow(WindowMsgProcessor.init(MainWindow, self));

        const initial_width: u32 = 800;
        const initial_height: u32 = 600;

        self.main_wnd = win32.CreateWindowExW(
            0,
            WND_CLASS_NAME,
            APP_NAME,
            win32.WS_OVERLAPPEDWINDOW,
            0,
            0,
            @intCast(self.toDpiAwarePixels(initial_width)),
            @intCast(self.toDpiAwarePixels(initial_height)),
            null,
            null,
            h_instance,
            null,
        ) orelse {
            last_init_error = win.GetLastError();
            std.debug.print("CreateWindowExW failed with error code {}\n", .{last_init_error.?});
            return error.FailedToCreateMainWindow;
        };

        centerWindow(self.main_wnd);

        try self.createSubcontrols();
        self.layoutSubcontrols();

        _ = win32.ShowWindow(self.main_wnd, win32.SW_SHOW);
        _ = win32.UpdateWindow(self.main_wnd);
    }

    pub fn deinit(self: *MainWindow) void {
        if (self.font) |font| _ = win32.DeleteObject(font);
        self.buffer_for_content.deinit(self.allocator);
        self.buffer_for_stats.deinit(self.allocator);
    }

    /// Returns true if the message was handled and need not be dispatched.
    pub fn previewMessage(self: *MainWindow, msg: *const win32.MSG) bool {
        const message = msg.message;
        const wparam = msg.wParam;

        // intercept keyboard shortcuts before they reach the focused control
        if (message != win32.WM_KEYUP and message != win32.WM_KEYDOWN) return false;

        if (wparam == win32.VK_ESCAPE and message == win32.WM_KEYDOWN) {
            win32.PostQuitMessage(0);
            return true;
        }

        if (message == win32.WM_KEYDOWN) {
            if (wparam == win32.VK_TAB) {
                const current_focused_wnd = win32.GetFocus();
                if (current_focused_wnd == self.content_edit_wnd) {
                    _ = win32.SetFocus(self.stats_edit_wnd);
                    // also select all content of the control (it is readonly, so it's completely safe)
                    _ = win32.PostMessageW(self.stats_edit_wnd, win32.EM_SETSEL, 0, @as(win32.LPARAM, -1));
                    return true;
                } else if (current_focused_wnd == self.stats_edit_wnd) {
                    _ = win32.SetFocus(self.content_edit_wnd);
                    return true;
                }
            }
        }

        if (isButtonDown(win32.VK_CONTROL)) {
            if (wparam == 'S') {
                if (message == win32.WM_KEYUP) {
                    self.onSaveContentCommand() catch |err| {
                        std.debug.panic("onSaveContentCommand failed: {s}", .{@errorName(err)});
                    };
                    return true;
                } else { // WM_KEYDOWN
                    return true;
                }
            } else if (wparam == 'A') {
                if (message == win32.WM_KEYUP) {
                    const focused_wnd = win32.GetFocus();
                    _ = win32.PostMessageW(focused_wnd, win32.EM_SETSEL, 0, @as(win32.LPARAM, -1));
                    return true;
                } else if (message == win32.WM_KEYDOWN) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn processMessage(self: *MainWindow, hwnd: win32.HWND, message: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) win32.LRESULT {
        const MESSAGE_PROCESSED: win32.LRESULT = 0;

        switch (message) {
            win32.WM_CLOSE => {
                win32.PostQuitMessage(0);
                return MESSAGE_PROCESSED;
            },

            win32.WM_SIZING => {
                const rect: *win32.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const effective_width: c_long = @max(rect.right - rect.left, @as(c_long, @intCast(self.toDpiAwarePixels(400))));
                const effective_height: c_long = @max(rect.bottom - rect.top, @as(c_long, @intCast(self.toDpiAwarePixels(200))));
                rect.bottom = rect.top + effective_height;
                rect.right = rect.left + effective_width;
                return 1;
            },

            win32.WM_SIZE => {
                self.layoutSubcontrols();
                return MESSAGE_PROCESSED;
            },

            win32.WM_ACTIVATE => {
                if (win32.loword(wparam) != win32.WA_INACTIVE) {
                    _ = win32.SetFocus(self.content_edit_wnd);
                    return MESSAGE_PROCESSED;
                }
            },

            win32.WM_DPICHANGED => {
                const new_dpi = win32.loword(wparam);
                const suggested_new_rect: *const win32.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
                self.onDpiChanged(new_dpi, suggested_new_rect);
                return MESSAGE_PROCESSED;
            },

            win32.WM_COMMAND => {
                if (lparam == @as(win32.LPARAM, @bitCast(@intFromPtr(self.content_edit_wnd)))) {
                    if (win32.hiword(wparam) == win32.EN_UPDATE) {
                        self.onContentChanged() catch |err| {
                            std.debug.panic("onContentChanged failed: {s}", .{@errorName(err)});
                        };
                        return MESSAGE_PROCESSED;
                    }
                }
            },

            else => {},
        }

        return win32.DefWindowProcW(hwnd, message, wparam, lparam);
    }

    fn createSubcontrols(self: *MainWindow) !void {
        self.content_edit_wnd = win32.CreateWindowExW(
            win32.WS_EX_CLIENTEDGE,
            EDIT_CLASS_NAME,
            null,
            win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.ES_MULTILINE,
            0,
            0,
            @intCast(self.toDpiAwarePixels(100)),
            @intCast(self.toDpiAwarePixels(200)),
            self.main_wnd,
            null,
            self.h_instance,
            null,
        ) orelse return error.FailedToCreateContentEdit;

        self.stats_edit_wnd = win32.CreateWindowExW(
            win32.WS_EX_CLIENTEDGE,
            EDIT_CLASS_NAME,
            null,
            win32.WS_CHILD | win32.WS_VISIBLE | win32.ES_READONLY,
            0,
            0,
            @intCast(self.toDpiAwarePixels(100)),
            @intCast(self.toDpiAwarePixels(16)),
            self.main_wnd,
            null,
            self.h_instance,
            null,
        ) orelse return error.FailedToCreateStatsEdit;

        const h_font = createFont(self.dpi);
        self.font = h_font;
        _ = win32.SendMessageW(self.content_edit_wnd, win32.WM_SETFONT, @intFromPtr(h_font), 0);
        _ = win32.SendMessageW(self.stats_edit_wnd, win32.WM_SETFONT, @intFromPtr(h_font), 0);
    }

    fn layoutSubcontrols(self: *MainWindow) void {
        const LEFT_PADDING: c_long = 0;
        const RIGHT_PADDING: c_long = 0;
        const TOP_PADDING: c_long = 0;
        const BOTTOM_PADDING: c_long = 0;
        const STATS_CONTROL_VERTICAL_SPACE: u32 = 24;

        var client_rect: win32.RECT = undefined;
        if (!win32.GetClientRect(self.main_wnd, &client_rect).toBool()) return;

        const effective_stats_vertical_space: c_long = @intCast(self.toDpiAwarePixels(STATS_CONTROL_VERTICAL_SPACE));

        _ = win32.MoveWindow(
            self.content_edit_wnd,
            LEFT_PADDING,
            TOP_PADDING,
            client_rect.right - (LEFT_PADDING + RIGHT_PADDING),
            client_rect.bottom - client_rect.top - (TOP_PADDING + BOTTOM_PADDING) - effective_stats_vertical_space,
            win.BOOL.FALSE, // bRepaint
        );
        _ = win32.MoveWindow(
            self.stats_edit_wnd,
            LEFT_PADDING,
            TOP_PADDING + (client_rect.bottom - client_rect.top) - effective_stats_vertical_space,
            client_rect.right - (LEFT_PADDING + RIGHT_PADDING),
            effective_stats_vertical_space,
            win.BOOL.FALSE,
        );
    }

    fn onContentChanged(self: *MainWindow) !void {
        self.buffer_for_content.clearRetainingCapacity();
        try getWindowText(self.allocator, self.content_edit_wnd, &self.buffer_for_content);

        if (self.buffer_for_content.items.len == 0) {
            _ = win32.SetWindowTextW(self.main_wnd, APP_NAME_EMPTY);
            return;
        }

        const number_stats = Statistics.fromString(self.buffer_for_content.items);
        try number_stats.toString(&self.buffer_for_stats, self.allocator);
        try self.buffer_for_stats.append(self.allocator, 0);
        _ = win32.SetWindowTextW(self.stats_edit_wnd, @ptrCast(self.buffer_for_stats.items.ptr));

        const content_size = self.buffer_for_content.items.len;
        {
            var offset: usize = 0;
            for (self.buffer_for_content.items) |c| {
                if (c == '\n' or c == '\r') {
                    self.buffer_for_content.shrinkRetainingCapacity(offset);
                    break;
                }
                offset += 1;
            }
        }

        const title = try std.fmt.allocPrint(self.allocator, " -- Scratchpad4k ({} wchars)", .{content_size});
        defer self.allocator.free(title);
        try appendAsciiUtf16(&self.buffer_for_content, self.allocator, title);
        try self.buffer_for_content.append(self.allocator, 0);
        _ = win32.SetWindowTextW(self.main_wnd, @ptrCast(self.buffer_for_content.items.ptr));
    }

    fn onDpiChanged(self: *MainWindow, new_dpi: u32, suggested_new_rect: *const win32.RECT) void {
        self.dpi = new_dpi;

        // The controls would keep rendering at the old font size; recreate the
        // font at the new DPI and redraw before resizing the window.
        const new_font = createFont(new_dpi);
        _ = win32.SendMessageW(self.content_edit_wnd, win32.WM_SETFONT, @intFromPtr(new_font), 1);
        _ = win32.SendMessageW(self.stats_edit_wnd, win32.WM_SETFONT, @intFromPtr(new_font), 1);
        if (self.font) |old_font| _ = win32.DeleteObject(old_font);
        self.font = new_font;

        _ = win32.SetWindowPos(
            self.main_wnd,
            null,
            suggested_new_rect.left,
            suggested_new_rect.top,
            suggested_new_rect.right - suggested_new_rect.left,
            suggested_new_rect.bottom - suggested_new_rect.top,
            win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
        );
    }

    fn toDpiAwarePixels(self: *const MainWindow, default_dpi_pixels: u32) u32 {
        return @intCast(@as(u64, default_dpi_pixels) * self.dpi / DEFAULT_NON_SCALED_DPI);
    }

    fn onSaveContentCommand(self: *MainWindow) !void {
        const allocator = self.allocator;

        var buffer = try allocator.alloc(u16, SAVE_DIALOG_BUFFER_WCHARS);
        defer allocator.free(buffer);
        @memset(buffer, 0);

        const content = try getWindowTextAlloc(allocator, self.content_edit_wnd);
        defer allocator.free(content);

        // Suggest a file name from the first line of the content.
        {
            var write_pos: usize = 0;
            const stop_pos = @min(SUGGESTED_FILE_NAME_MAX_LENGTH, content.len);
            while (write_pos < stop_pos) : (write_pos += 1) {
                const current_char = content[write_pos];
                if (current_char == '\r' or current_char == '\n') break;
                buffer[write_pos] = if (std.mem.indexOfScalar(u16, INVALID_FILE_NAME_CHARACTERS, current_char) != null)
                    '!'
                else
                    current_char;
            }
            if (write_pos == 0) {
                @memcpy(buffer[0..EMPTY_FILE_NAME.len], EMPTY_FILE_NAME);
            }
        }

        var save_file_dialog_settings = std.mem.zeroes(win32.OPENFILENAMEW);
        save_file_dialog_settings.lStructSize = @sizeOf(win32.OPENFILENAMEW);
        save_file_dialog_settings.hwndOwner = self.main_wnd;
        save_file_dialog_settings.lpstrFile = @ptrCast(buffer.ptr);
        save_file_dialog_settings.nMaxFile = @intCast(buffer.len);
        save_file_dialog_settings.Flags = win32.OFN_DONTADDTORECENT | win32.OFN_FORCESHOWHIDDEN | win32.OFN_LONGNAMES | win32.OFN_NOTESTFILECREATE;

        if (!win32.GetSaveFileNameW(&save_file_dialog_settings).toBool()) {
            const err = win32.CommDlgExtendedError();
            if (err == 0) return; // the user cancelled the dialog

            try error_message.showErrorMessageBox(
                allocator,
                self.main_wnd,
                "::GetSaveFileNameW() failed",
                "Extended error code : {}.",
                .{err},
            );
            return;
        }

        // Trim the file-name buffer to the actual path length (up to the first NUL).
        var path_len: usize = buffer.len;
        {
            var i: usize = save_file_dialog_settings.nFileOffset;
            while (i < buffer.len) : (i += 1) {
                if (buffer[i] == 0) {
                    path_len = i;
                    break;
                }
            }
        }

        // Long paths need the extended-length prefix.
        if (path_len >= win.MAX_PATH and !std.mem.startsWith(u16, buffer[0..path_len], EXTENDED_LENGTH_PREFIX)) {
            std.mem.copyBackwards(u16, buffer[EXTENDED_LENGTH_PREFIX.len .. EXTENDED_LENGTH_PREFIX.len + path_len], buffer[0..path_len]);
            @memcpy(buffer[0..EXTENDED_LENGTH_PREFIX.len], EXTENDED_LENGTH_PREFIX);
            path_len += EXTENDED_LENGTH_PREFIX.len;
        }

        const h_file = win32.CreateFileW(
            @ptrCast(buffer.ptr),
            win32.GENERIC_WRITE,
            win32.FILE_SHARE_READ,
            null,
            win32.CREATE_ALWAYS,
            win32.FILE_ATTRIBUTE_NORMAL,
            null,
        );
        if (h_file == win.INVALID_HANDLE_VALUE) {
            const last_error = win.GetLastError();
            try showFileError(allocator, self.main_wnd, "::CreateFileW() failed", last_error);
            return;
        }
        defer win.CloseHandle(h_file);

        const content_in_utf8 = try string_conversions.toUtf8(allocator, content);
        defer allocator.free(content_in_utf8);

        if (!writeToFile(h_file, content_in_utf8)) {
            const last_error = win.GetLastError();
            try showFileError(allocator, self.main_wnd, "::WriteFile() failed", last_error);
            return;
        }
    }
};

test "Statistics.fromString" {
    // "12, 34, 5, 5" (the '-' is not a digit and gets skipped, like in C++)
    const s1 = Statistics.fromString(std.unicode.utf8ToUtf16LeStringLiteral("abc 12 -34 xyz 5.5"));
    try std.testing.expectEqual(@as(u64, 4), s1.n_numbers);
    try std.testing.expectEqual(@as(u64, 5), s1.min);
    try std.testing.expectEqual(@as(u64, 34), s1.max);
    try std.testing.expectEqual(@as(u64, 56), s1.sum);
    try std.testing.expectEqual(@as(u64, 14), s1.average);
    try std.testing.expectEqual(@as(u64, 20), s1.max_deviation);

    // fewer than two numbers
    const s2 = Statistics.fromString(std.unicode.utf8ToUtf16LeStringLiteral("no numbers here"));
    try std.testing.expectEqual(@as(u64, 0), s2.n_numbers);

    const s3 = Statistics.fromString(std.unicode.utf8ToUtf16LeStringLiteral("only 1"));
    try std.testing.expectEqual(@as(u64, 1), s3.n_numbers);
}

test "Statistics.toString" {
    const allocator = std.testing.allocator;
    var buffer: std.ArrayListUnmanaged(u16) = .empty;
    defer buffer.deinit(allocator);

    const s1 = Statistics.fromString(std.unicode.utf8ToUtf16LeStringLiteral("1 4 7"));
    try s1.toString(&buffer, allocator);
    const utf8_1 = try std.unicode.utf16LeToUtf8Alloc(allocator, buffer.items);
    defer allocator.free(utf8_1);
    try std.testing.expectEqualStrings("Avg=4 +-3, Min=1, Max=7, Sum=12, nNumbers=3", utf8_1);

    const s2 = Statistics.fromString(std.unicode.utf8ToUtf16LeStringLiteral("x"));
    try s2.toString(&buffer, allocator);
    const utf8_2 = try std.unicode.utf16LeToUtf8Alloc(allocator, buffer.items);
    defer allocator.free(utf8_2);
    try std.testing.expectEqualStrings("Not enough numbers detected (need at least 2).", utf8_2);
}
