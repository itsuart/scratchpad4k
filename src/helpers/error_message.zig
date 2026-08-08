//! Helpers for turning Windows error codes into human-readable messages
//! (the Zig counterpart of the C++ `helpers::error_message`).

const std = @import("std");
const win = std.os.windows;
const win32 = @import("../win32.zig");

const FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000;
const FORMAT_MESSAGE_IGNORE_INSERTS = 0x00000200;

/// Returns the system error message for `error_code` as an allocated UTF-16
/// string (the counterpart of `helpers::get_error_message_w`).
/// The caller owns the returned slice.
pub fn getErrorMessageW(allocator: std.mem.Allocator, error_code: win.Win32Error) ![]u16 {
    var buffer: [512]u16 = std.mem.zeroes([512]u16);
    const copied = win.kernel32.FormatMessageW(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        null,
        error_code,
        0, // default language
        @ptrCast(&buffer),
        buffer.len,
        null,
    );
    if (copied == 0) {
        return std.unicode.utf8ToUtf16LeAllocZ(allocator, "Unknown error");
    }

    // The system appends "\r\n" to the message; drop it.
    var end: usize = copied;
    while (end > 0 and (buffer[end - 1] == '\r' or buffer[end - 1] == '\n')) end -= 1;
    return allocator.dupe(u16, buffer[0..end]);
}

/// Formats `args` into `fmt` and shows an error message box with the given caption.
pub fn showErrorMessageBox(
    allocator: std.mem.Allocator,
    parent: ?win32.HWND,
    comptime caption: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    const text_wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, text);
    defer allocator.free(text_wide);
    const caption_wide = comptime std.unicode.utf8ToUtf16LeStringLiteral(caption);
    _ = win32.MessageBoxW(parent, text_wide.ptr, caption_wide, win32.MB_OK | win32.MB_ICONERROR);
}
