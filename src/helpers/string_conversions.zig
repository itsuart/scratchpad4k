//! UTF-8 <-> UTF-16 conversions via the Win32 conversion APIs
//! (the Zig counterpart of the C++ `helpers::string_conversions`).

const std = @import("std");
const win32 = @import("../win32.zig");

/// Converts a UTF-16 slice into an allocated UTF-8 string.
/// The caller owns the returned slice.
pub fn toUtf8(allocator: std.mem.Allocator, input: []const u16) ![]u8 {
    if (input.len == 0) return allocator.alloc(u8, 0);

    const needed = win32.WideCharToMultiByte(
        win32.CP_UTF8,
        0,
        input.ptr,
        @intCast(input.len),
        null,
        0,
        null,
        null,
    );
    if (needed <= 0) return error.InvalidText;

    const result = try allocator.alloc(u8, @intCast(needed));
    const written = win32.WideCharToMultiByte(
        win32.CP_UTF8,
        0,
        input.ptr,
        @intCast(input.len),
        result.ptr,
        needed,
        null,
        null,
    );
    if (written <= 0) return error.InvalidText;
    return result;
}

/// Converts a UTF-8 slice into an allocated UTF-16 string.
/// The caller owns the returned slice.
pub fn toUtf16(allocator: std.mem.Allocator, input: []const u8) ![]u16 {
    if (input.len == 0) return allocator.alloc(u16, 0);

    const needed = win32.MultiByteToWideChar(
        win32.CP_UTF8,
        0,
        input.ptr,
        @intCast(input.len),
        null,
        0,
    );
    if (needed <= 0) return error.InvalidText;

    const result = try allocator.alloc(u16, @intCast(needed));
    const written = win32.MultiByteToWideChar(
        win32.CP_UTF8,
        0,
        input.ptr,
        @intCast(input.len),
        result.ptr,
        needed,
    );
    if (written <= 0) return error.InvalidText;
    return result;
}

/// Converts a UTF-8 slice into a null-terminated UTF-16 allocation.
/// The caller owns the returned slice.
pub fn toUtf16Z(allocator: std.mem.Allocator, input: []const u8) ![:0]u16 {
    const wide = try toUtf16(allocator, input);
    defer allocator.free(wide);
    const z = try allocator.allocSentinel(u16, wide.len, 0);
    @memcpy(z[0..wide.len], wide);
    return z;
}
