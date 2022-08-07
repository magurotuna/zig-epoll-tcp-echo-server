const std = @import("std");
const Thread = std.Thread;
const builtin = @import("builtin");
const serverLinux = @import("./linux.zig").serverLinux;
const serverMac = @import("./mac.zig").serverMac;

pub fn main() void {
    const server_impl = comptime switch (builtin.os.tag) {
        .linux => serverLinux,
        .macos => serverMac,
        else => {
            std.log.warn("This operating system is not supported\n", .{});
            std.process.exit(1);
        },
    };

    const cpu = Thread.getCpuCount() catch |err| {
        std.log.err("failed to get cpu count because of {}\n", .{err});
        std.process.exit(1);
    };

    std.log.info("there are {} cpus available\n", .{cpu});

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

