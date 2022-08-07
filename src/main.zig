const std = @import("std");
const linux = std.os.linux;
const mem = std.mem;
const C = std.c;
const Thread = std.Thread;
const builtin = @import("builtin");

pub fn main() void {
    const server_impl = switch (builtin.os.tag) {
        .linux => server_linux,
        .macos => server_mac,
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

fn server_linux(thread_id: usize) void {
    std.log.info("thread {} started\n", .{thread_id});

    const sockfd = C.socket(C.AF.INET, C.SOCK.STREAM | C.SOCK.NONBLOCK | C.SOCK.CLOEXEC, 0);
    if (sockfd == -1) {
        std.log.err("failed to create socket. errno: {}\n", .{C.getErrno(sockfd)});
        std.process.exit(1);
    }
    defer _ = C.close(sockfd);

    {
        const optval = @intCast(c_int, @boolToInt(true));
        const setsockopt_ret = C.setsockopt(sockfd, C.SOL.SOCKET, C.SO.REUSEADDR, mem.asBytes(&optval), @sizeOf(@TypeOf(optval)));
        if (setsockopt_ret == -1) {
            std.log.err("failed to set SO_REUSEADDR. errno: {}\n", .{C.getErrno(setsockopt_ret)});
            std.process.exit(1);
        }
    }

    {
        const optval = @intCast(c_int, @boolToInt(true));
        const setsockopt_ret = C.setsockopt(sockfd, C.SOL.SOCKET, C.SO.REUSEPORT, mem.asBytes(&optval), @sizeOf(@TypeOf(optval)));
        if (setsockopt_ret == -1) {
            std.log.err("failed to set SO_REUSEPORT. errno: {}\n", .{C.getErrno(setsockopt_ret)});
            std.process.exit(1);
        }
    }

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

    // create epoll instance
    const epfd = epoll: {
        const epfd = C.epoll_create1(linux.EPOLL.CLOEXEC);
        if (epfd == -1) {
            std.log.err("failed to create epoll instance. errno: {}\n", .{C.getErrno(-1)});
            std.process.exit(1);
        }
        break :epoll @intCast(i32, epfd);
    };
    defer _ = C.close(epfd);

    // add sockfd to the interest list
    {
        var epoll_ev = C.epoll_event{
            .events = linux.EPOLL.IN | linux.EPOLL.OUT | linux.EPOLL.ET,
            .data = .{
                .fd = sockfd,
            },
        };
        const ctl_ret = C.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, sockfd, &epoll_ev);
        if (ctl_ret == -1) {
            std.log.err("failed to add sockfd to the interest list. errno: {}\n", .{C.getErrno(ctl_ret)});
            std.process.exit(1);
        }
    }

    const max_events = 64;
    var events: [max_events]linux.epoll_event = undefined;

    while (true) {
        std.log.info("======== beginning of the loop in thread {} ========", .{thread_id});

        const nfds = C.epoll_wait(epfd, &events, max_events, -1);
        if (nfds == -1) {
            std.log.err("something went wrong when waiting for events. errno: {}\n", .{C.getErrno(nfds)});
            std.process.exit(1);
        }

        std.log.info("thread {} is awakened\n", .{thread_id});

        var i: usize = 0;
        while (i < nfds) : (i += 1) {
            if (events[i].data.fd == sockfd) {
                // new connection is opening
                const conn_fd = C.accept4(sockfd, null, null, C.SOCK.NONBLOCK | C.SOCK.CLOEXEC);
                if (conn_fd == -1) {
                    std.log.err("failed to accept socket. errno: {}\n", .{C.getErrno(conn_fd)});
                    continue;
                }

                std.log.info("new connetion established\n", .{});

                {
                    var epoll_ev = C.epoll_event{
                        .events = linux.EPOLL.IN | linux.EPOLL.ET | linux.EPOLL.RDHUP | linux.EPOLL.HUP,
                        .data = .{
                            .fd = conn_fd,
                        },
                    };
                    const ctl_ret = C.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, conn_fd, &epoll_ev);
                    if (ctl_ret == -1) {
                        std.log.err("failed to add new connection to the interest list. errno: {}\n", .{C.getErrno(ctl_ret)});
                        continue;
                    }
                }
            } else if (events[i].events & linux.EPOLL.IN != 0) {
                // data is arriving on the existing connection
                while (true) {
                    const buf_size = 4096;
                    var buf: [buf_size]u8 = undefined;

                    const nread = C.read(events[i].data.fd, &buf, buf_size);
                    if (nread <= 0) break; // including WOULDBLOCK

                    const bytes = @intCast(usize, nread);
                    const received = buf[0..bytes];

                    const nwrite = C.write(events[i].data.fd, received.ptr, bytes);
                    if (nwrite == -1) {
                        std.log.err("failed to write data. errno: {}\n", .{C.getErrno(nwrite)});
                        std.process.exit(1);
                    }
                }
            } else {
                std.log.warn("unexpected event occurred\n", .{});
            }

            // Check if the conneciton is closing
            if (events[i].events & (linux.EPOLL.RDHUP | linux.EPOLL.HUP) != 0) {
                std.log.info("connection closed\n", .{});
                const ctl_ret = C.epoll_ctl(epfd, linux.EPOLL.CTL_DEL, events[i].data.fd, null);
                if (ctl_ret == -1) {
                    std.log.err("failed to delete a file descritor from the interest list. errno: {}\n", .{C.getErrno(ctl_ret)});
                }
                _ = C.close(events[i].data.fd);
            }
        }
    }
}

fn server_mac(thread_id: usize) void {
    std.log.warn("not yet implemented {}\n", .{thread_id});
}
