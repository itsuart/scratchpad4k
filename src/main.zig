//! scratchpad4k entry point (the Zig counterpart of `main.cpp`).

const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const error_message = @import("helpers/error_message.zig");
const WindowMsgDispatcher = @import("window_msg_dispatcher.zig").WindowMsgDispatcher;
const main_window_module = @import("main_window.zig");
const MainWindow = main_window_module.MainWindow;

pub export fn wWinMain(
    h_instance: win.HINSTANCE,
    h_prev_instance: ?win.HINSTANCE,
    lp_cmd_line: [*:0]u16,
    n_cmd_show: c_int,
) callconv(.winapi) win.INT {
    _ = h_prev_instance;
    _ = lp_cmd_line;
    _ = n_cmd_show;

    _ = win32.SetProcessDpiAwareness(win32.PROCESS_PER_MONITOR_DPI_AWARE);

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dispatcher: WindowMsgDispatcher = undefined;
    dispatcher.init(allocator) catch |err| return failStartup(allocator, err);
    defer dispatcher.deinit();

    var main_window: MainWindow = undefined;
    main_window.init(allocator, &dispatcher, h_instance) catch |err| return failStartup(allocator, err);
    defer main_window.deinit();

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0).toBool()) {
        if (main_window.previewMessage(&msg)) continue;
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }

    return @intCast(msg.wParam);
}

fn failStartup(allocator: std.mem.Allocator, err: anyerror) win.INT {
    if (main_window_module.last_init_error) |code| {
        error_message.showErrorMessageBox(allocator, null, "scratchpad4k", "Failed to start: {s} (GetLastError = {})", .{
            @errorName(err),
            code,
        }) catch {};
    } else {
        error_message.showErrorMessageBox(allocator, null, "scratchpad4k", "Failed to start: {s}", .{@errorName(err)}) catch {};
    }
    return 1;
}
