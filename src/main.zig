const std = @import("std");
const Thread = std.Thread;
const builtin = @import("builtin");
const serverLinux = @import("./linux.zig").serverLinux;
const serverMac = @import("./mac.zig").serverMac;

pub fn main() void {
    comptime switch (builtin.os.tag) {
        .linux, .macos => {},
        else => {
            @compileError("This operating system is not supported");
        },
    };

    const server_impl = comptime switch (builtin.os.tag) {
        .linux => serverLinux,
        .macos => serverMac,
        else => unreachable,
    };

    // On Linux, when enabling `SO_REUSEPORT` and having multiple sockets to bind to the same port, the kernel will
    // distribute the incoming connections to these sockets automatically.
    // On the other hand, on macOS (and other OSes), automatic distribution won't happen; thus we use just one thread.
    // For more detail, see https://stackoverflow.com/questions/14388706/how-do-so-reuseaddr-and-so-reuseport-differ
    const cpu = switch (builtin.os.tag) {
        .linux => Thread.getCpuCount() catch |err| {
            std.log.err("failed to get cpu count because of {}\n", .{err});
            std.process.exit(1);
        },
        .macos => 1,
        else => unreachable,
    };

    std.log.info("{} thread(s) will be spawned\n", .{cpu});

    const allocator = std.heap.page_allocator;

    var threads = std.ArrayList(Thread).initCapacity(allocator, cpu) catch |err| {
        std.log.err("failed to create ArrayList because of {}\n", .{err});
        std.process.exit(1);
    };

    defer threads.deinit();

    var i: usize = 0;
    while (i < cpu) : (i += 1) {
        const t = Thread.spawn(.{}, server_impl, .{i}) catch |err| {
            std.log.err("failed to spawn new thread because of {}\n", .{err});
            std.process.exit(1);
        };

        threads.append(t) catch unreachable;
    }

    for (threads.items) |t| {
        t.join();
    }
}
