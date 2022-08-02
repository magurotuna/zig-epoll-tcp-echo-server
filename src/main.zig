const std = @import("std");
const mem = std.mem;
const C = std.c;

pub fn main() void {
    std.log.info("start\n", .{});

    const sockfd = C.socket(C.AF.INET, C.SOCK.STREAM, 0);
    if (sockfd == -1) {
        std.log.err("failed to create socket. errno: {}\n", .{C.getErrno(sockfd)});
        std.process.exit(1);
    }
    defer _ = C.close(sockfd);

    var sa = C.sockaddr.in{
        .family = C.AF.INET,
        .port = mem.nativeToBig(u16, 8888),
        .addr = 0x00000000,
        .zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    const bind_ret = C.bind(sockfd, @ptrCast(*C.sockaddr, &sa), @sizeOf(@TypeOf(sa)));
    if (bind_ret == -1) {
        std.log.err("failed to bind socket. errno: {}\n", .{C.getErrno(bind_ret)});
        std.process.exit(1);
    }

    const listen_ret = C.listen(sockfd, 128);
    if (listen_ret == -1) {
        std.log.err("failed to listen socket. errno: {}\n", .{C.getErrno(listen_ret)});
        std.process.exit(1);
    }

    const accepted_fd = C.accept(sockfd, null, null);
    if (accepted_fd == -1) {
        std.log.err("failed to accept socket. errno: {}\n", .{C.getErrno(accepted_fd)});
        std.process.exit(1);
    }
    defer _ = C.close(accepted_fd);

    std.log.info("connection established!\n", .{});

    const buf_size = 4096;
    var buf: [buf_size]u8 = undefined;
    while (true) {
        const nread = C.read(accepted_fd, &buf, buf_size);
        if (nread == -1) {
            std.log.err("failed to read data. errno: {}\n", .{C.getErrno(nread)});
            std.process.exit(1);
        }
        if (nread == 0) break;

        const bytes = @intCast(usize, nread);
        const received = buf[0..bytes];
        std.log.info("received: {s}\n", .{received});

        const nwrite = C.write(accepted_fd, received.ptr, bytes);
        if (nwrite == -1) {
            std.log.err("failed to write data. errno: {}\n", .{C.getErrno(nwrite)});
            std.process.exit(1);
        }
    }

    std.log.info("connection interrupted!\n", .{});

    std.log.info("finish\n", .{});
}
