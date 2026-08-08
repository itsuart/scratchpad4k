//! UTF-8 <-> UTF-16 conversions (the Zig counterpart of the C++
//! `helpers::string_conversions`).

const std = @import("std");

/// Converts a UTF-16 (WTF-16) slice into an allocated UTF-8 string.
/// The caller owns the returned slice.
pub fn toUtf8(allocator: std.mem.Allocator, input: []const u16) ![]u8 {
    return std.unicode.utf16LeToUtf8Alloc(allocator, input);
}

/// Converts a UTF-8 slice into an allocated UTF-16 (WTF-16) string.
/// The caller owns the returned slice.
pub fn toUtf16(allocator: std.mem.Allocator, input: []const u8) ![]u16 {
    return std.unicode.utf8ToUtf16LeAlloc(allocator, input);
}
