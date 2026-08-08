//! Maps HWNDs to message processors (the Zig counterpart of the C++
//! `window_msg_dispatcher`).

const std = @import("std");
const win32 = @import("win32.zig");

pub const HWND = win32.HWND;
pub const UINT = win32.UINT;
pub const WPARAM = win32.WPARAM;
pub const LPARAM = win32.LPARAM;
pub const LRESULT = win32.LRESULT;

/// A window message processor: a context pointer plus a function that
/// handles messages addressed to a window.
pub const WindowMsgProcessor = struct {
    ctx: *anyopaque,
    process: *const fn (ctx: *anyopaque, hwnd: HWND, message: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT,

    pub fn init(comptime T: type, ctx: *T) WindowMsgProcessor {
        return .{
            .ctx = ctx,
            .process = struct {
                fn handle(
                    raw_ctx: *anyopaque,
                    hwnd: HWND,
                    message: UINT,
                    wparam: WPARAM,
                    lparam: LPARAM,
                ) callconv(.winapi) LRESULT {
                    const self: *T = @ptrCast(@alignCast(raw_ctx));
                    return T.processMessage(self, hwnd, message, wparam, lparam);
                }
            }.handle,
        };
    }
};

var g_instance: ?*WindowMsgDispatcher = null;

/// Dispatches window messages to per-HWND processors. A processor enqueued via
/// `bindToNextNewWindow` is bound to the first HWND that arrives without one.
pub const WindowMsgDispatcher = struct {
    allocator: std.mem.Allocator,
    enqueued: ?WindowMsgProcessor = null,
    map: std.AutoHashMapUnmanaged(HWND, WindowMsgProcessor) = .empty,

    pub fn init(self: *WindowMsgDispatcher, allocator: std.mem.Allocator) !void {
        if (g_instance != null) return error.AlreadyInstantiated;
        self.* = .{ .allocator = allocator };
        try self.map.ensureTotalCapacity(allocator, 1);
        g_instance = self;
    }

    pub fn deinit(self: *WindowMsgDispatcher) void {
        g_instance = null;
        self.map.deinit(self.allocator);
        self.* = undefined;
    }

    /// The next HWND that sends a message without a bound processor gets `processor`.
    pub fn bindToNextNewWindow(self: *WindowMsgDispatcher, processor: WindowMsgProcessor) !void {
        if (self.enqueued != null) return error.ProcessorAlreadyEnqueued;
        self.enqueued = processor;
    }

    pub fn unbind(self: *WindowMsgDispatcher, hwnd: HWND) void {
        _ = self.map.remove(hwnd);
    }

    /// Window procedure installed for windows that go through this dispatcher.
    pub fn dispatchingProc(hwnd: HWND, message: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const instance = g_instance orelse return win32.DefWindowProcW(hwnd, message, wparam, lparam);
        return instance.processMessage(hwnd, message, wparam, lparam);
    }

    fn processMessage(self: *WindowMsgDispatcher, hwnd: HWND, message: UINT, wparam: WPARAM, lparam: LPARAM) LRESULT {
        if (self.map.get(hwnd)) |processor| {
            return processor.process(processor.ctx, hwnd, message, wparam, lparam);
        }

        const processor = self.enqueued orelse
            std.debug.panic("A message to unknown HWND came, but no processor enqueued", .{});
        self.enqueued = null;
        self.map.put(self.allocator, hwnd, processor) catch unreachable;
        return processor.process(processor.ctx, hwnd, message, wparam, lparam);
    }
};
