const std = @import("std");
const os = std.os;
const mem = std.mem;
const system = os.system;
const builtin = @import("builtin");

pub fn serverMac(thread_id: usize) !void {
    comptime if (builtin.os.tag != .macos) {
        @compileError("serverMac function should be invoked only in macOS");
    };

    std.log.info("thread {} started\n", .{thread_id});

    const sockfd = try os.socket(system.PF.INET, os.SOCK.STREAM, 0);
    defer os.closeSocket(sockfd);

    try setCloExec(sockfd);
    try setNonBlock(sockfd);

    try enableSockOpt(sockfd, os.SO.REUSEADDR);
    try enableSockOpt(sockfd, os.SO.REUSEPORT);

    try os.bind(sockfd, @ptrCast(*const system.sockaddr, &system.sockaddr.in{
        .port = mem.nativeToBig(u16, 8887),
        .addr = 0x00000000,
    }), @sizeOf(system.sockaddr));

    try os.listen(sockfd, 128);

    const kqfd = try os.kqueue();
    _ = try os.kevent(kqfd, &[_]os.Kevent{.{
        .ident = @intCast(usize, sockfd),
        .filter = system.EVFILT_READ,
        .flags = system.EV_ADD | system.EV_ENABLE,
        .fflags = 0,
        .data = 0,
        .udata = 0,
    }}, &.{}, null);

    const max_events = 64;
    var events: [max_events]os.Kevent = undefined;

    evloop: while (true) {
        std.log.info("======== beginning of the loop in thread {} ========", .{thread_id});

        const n_events = try os.kevent(kqfd, &.{}, &events, null);

        std.log.info("thread {} is awakened\n", .{thread_id});

        var i: usize = 0;
        while (i < n_events) : (i += 1) {
            const event_fd = events[i].ident;

            if (events[i].flags & system.EV_EOF != 0) {
                std.log.info("client has disconnected\n", .{});
                os.close(@intCast(c_int, event_fd));
            } else if (event_fd == sockfd) {
                // new connection is opening
                // TODO: get client data and output to log
                const connfd = try os.accept(sockfd, null, null, 0);

                // Darwin doesn't support `accept4(2)` call. We have to set `CLOEXEC`. For more detail, see:
                // https://github.com/tokio-rs/mio/blob/3340f6d39944c66b186e06d6c5d67f32596d15e4/src/sys/unix/tcp.rs#L84-L86
                try setCloExec(connfd);

                _ = try os.kevent(kqfd, &[_]os.Kevent{.{
                    .ident = @intCast(usize, connfd),
                    .filter = system.EVFILT_READ,
                    .flags = system.EV_ADD,
                    .fflags = 0,
                    .data = 0,
                    .udata = 0,
                }}, &.{}, null);
            } else if (events[i].filter & system.EVFILT_READ != 0) {
                // data is arriving on the existing connection
                while (true) {
                    const buf_size = 4096;
                    var buf: [buf_size]u8 = undefined;

                    const nread = os.read(@intCast(os.socket_t, event_fd), &buf) catch |err| switch (err) {
                        os.ReadError.WouldBlock => continue :evloop,
                        else => return err,
                    };

                    const bytes = @intCast(usize, nread);
                    const received = buf[0..bytes];

                    _ = try os.write(@intCast(os.socket_t, event_fd), received);
                }
            } else {
                std.log.warn("unexpected event occurred\n", .{});
            }
        }
    }
}

// On darwin, we need to set `O_NONBLOCK` and `FD_CLOEXEC` by calling `fcntl` syscall.
// https://github.com/tokio-rs/mio/blob/3340f6d39944c66b186e06d6c5d67f32596d15e4/src/sys/unix/net.rs?plain=1#L47-L48
fn setCloExec(sock: os.socket_t) !void {
    var fd_flags = try os.fcntl(sock, os.F.GETFD, 0);
    fd_flags |= os.FD_CLOEXEC;
    _ = try os.fcntl(sock, os.F.SETFD, fd_flags);
}

// On darwin, we need to set `O_NONBLOCK` and `FD_CLOEXEC` by calling `fcntl` syscall.
// https://github.com/tokio-rs/mio/blob/3340f6d39944c66b186e06d6c5d67f32596d15e4/src/sys/unix/net.rs?plain=1#L47-L48
fn setNonBlock(sock: os.socket_t) !void {
    var fl_flags = try os.fcntl(sock, os.F.GETFL, 0);
    fl_flags |= os.O.NONBLOCK;
    _ = try os.fcntl(sock, os.F.SETFL, os.O.NONBLOCK);
}

fn enableSockOpt(sock: os.socket_t, optname: u32) !void {
    const optval = @intCast(c_int, @boolToInt(true));
    try os.setsockopt(sock, os.SOL.SOCKET, optname, mem.asBytes(&optval));
}
