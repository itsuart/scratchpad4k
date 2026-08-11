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
    const copied = win32.FormatMessageW(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        null,
        error_code,
        0, // default language
        @ptrCast(&buffer),
        buffer.len,
        null,
    );
    if (copied == 0) {
        const unknown = std.unicode.utf8ToUtf16LeStringLiteral("Unknown error");
        return allocator.dupe(u16, unknown[0..unknown.len]);
    }

    // The system appends "\r\n" to the message; drop it.
    var end: usize = copied;
    while (end > 0 and (buffer[end - 1] == '\r' or buffer[end - 1] == '\n')) end -= 1;
    return allocator.dupe(u16, buffer[0..end]);
}

/// Shows an error message box with the given caption. `fmt` supports `{s}`
/// for `[]const u8` and `{}` / `{d}` for unsigned integers; the text is
/// formatted into a fixed stack buffer, so no allocation is involved.
pub fn showErrorMessageBox(
    parent: ?win32.HWND,
    comptime caption: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    var text: [1024]u8 = undefined;
    const text_len = formatInto(&text, fmt, args);

    var wide: [1024]u16 = undefined;
    const wide_len = win32.MultiByteToWideChar(
        win32.CP_UTF8,
        0,
        text[0..text_len].ptr,
        @intCast(text_len),
        @ptrCast(&wide),
        wide.len,
    );
    if (wide_len <= 0 or wide_len >= wide.len) return error.TextTooLong;
    wide[@intCast(wide_len)] = 0;

    const caption_wide = comptime std.unicode.utf8ToUtf16LeStringLiteral(caption);
    _ = win32.MessageBoxW(parent, @ptrCast(&wide), caption_wide, win32.MB_OK | win32.MB_ICONERROR);
}

/// Minimal formatter: `{s}` for `[]const u8`, `{}`/`{d}` for unsigned
/// integers. Everything else is copied verbatim. Output is truncated to
/// `buf.len`.
fn formatInto(buf: []u8, comptime fmt: []const u8, args: anytype) usize {
    var pos: usize = 0;
    // `inline for` unrolls the loop, so `i` is comptime-known and each
    // `{s}`/`{}` can be matched to its tuple argument by counting the
    // specifiers that precede it.
    inline for (fmt, 0..) |fmt_char, i| {
        if (fmt_char == '{' and i + 1 < fmt.len and fmt[i + 1] == '}') {
            const arg = args[comptime countSpecifiers(fmt[0..i])];
            switch (@typeInfo(@TypeOf(arg))) {
                .int => pos += writeDecimal(buf[pos..], arg),
                .pointer => {
                    const s: []const u8 = arg;
                    const n = @min(s.len, buf.len - pos);
                    @memcpy(buf[pos..][0..n], s[0..n]);
                    pos += n;
                },
                else => @compileError("unsupported argument type in showErrorMessageBox"),
            }
        } else if (fmt_char == '}' and i > 0 and fmt[i - 1] == '{') {
            // closing brace of a specifier; already handled above
        } else {
            if (pos < buf.len) {
                buf[pos] = fmt_char;
                pos += 1;
            }
        }
    }
    return pos;
}

/// Number of `{}` specifiers in `s` (comptime helper for `formatInto`).
fn countSpecifiers(s: []const u8) usize {
    var n: usize = 0;
    var j: usize = 0;
    while (j + 1 < s.len) : (j += 1) {
        if (s[j] == '{' and s[j + 1] == '}') n += 1;
    }
    return n;
}

/// Writes `value` in decimal; returns the number of bytes written.
fn writeDecimal(buf: []u8, value: anytype) usize {
    var v: u64 = value;
    var tmp: [20]u8 = undefined; // u64 max is 20 digits
    var n: usize = 0;
    while (true) {
        tmp[n] = @intCast('0' + v % 10);
        n += 1;
        v /= 10;
        if (v == 0) break;
    }
    const limit = @min(n, buf.len);
    for (0..limit) |j| buf[j] = tmp[n - 1 - j];
    return limit;
}
