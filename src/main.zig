const std = @import("std");
const mem = std.mem;
const C = std.c;
const c = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("netinet/in.h");
    @cInclude("netinet/tcp.h");
});

pub fn main() void {
    std.log.info("start\n", .{});

    const sockfd = c.socket(C.AF.INET, C.SOCK.STREAM, 0);
    if (sockfd == -1) {
        std.log.err("failed to create socket. errno: {}\n", .{C.getErrno(sockfd)});
        std.process.exit(1);
    }

    const sa = C.sockaddr.in{
        .family = C.AF.INET,
        .port = mem.nativeToBig(u16, 8888),
        .addr = 0x00000000,
        .zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    const bind_ret = c.bind(sockfd, @ptrToInt(&sa), @sizeOf(@TypeOf(sa)));
    if (bind_ret == -1) {
        std.log.err("failed to bind socket. errno: {}\n", .{C.getErrno(bind_ret)});
        std.process.exit(1);
    }

    const listen_ret = c.listen(sockfd, 128);
    if (listen_ret == -1) {
        std.log.err("failed to listen socket. errno: {}\n", .{C.getErrno(listen_ret)});
        std.process.exit(1);
    }

    const accepted_fd = c.accept(sockfd, null, null);
    if (accepted_fd == -1) {
        std.log.err("failed to accept socket. errno: {}\n", .{C.getErrno(accepted_fd)});
        std.process.exit(1);
    }

    std.log.info("finish\n", .{});
}
