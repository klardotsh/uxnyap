// This source code is part of the uxnyap project, released under the CC0-1.0
// dedication found in the COPYING file in the root directory of this source
// tree, or at https://creativecommons.org/publicdomain/zero/1.0/

// tested on zig 0.8.1 by klardotsh. requires libcurl dev headers and, of
// course, linkable objects.

// in a more "production-ready" world,
// https://github.com/ducdetronquito/requestz is probably the more
// zig-ergonomic answer for HTTP(s) stuff, and
// https://github.com/MasterQ32/zig-network for raw TCP/UDP stuff. since this
// is just a quick PoC, libcurl it is!

// it's expected that this "daemon" run before uxncli <rom> does, but after the
// fifos are created (mkfifo reqs.fifo; mkfifo.resps.fifo). please
// productionize this better than I did.
//
// thus:
//
// mkfifo reqs.fifo
// mkfifo resps.fifo
// zig build -Drelease-safe run

const std = @import("std");
const libcurl = @cImport(@cInclude("curl/curl.h"));

const YAP_VERSIONS = enum {
    V0 = 0,
};

const PROTOCOLS = enum {
    MALFORMED = 0,
    UDP,
    TCP,
    HTTP,
    GEMINI,
};

fn wrap(result: anytype) !void {
    switch (@enumToInt(result)) {
        libcurl.CURLE_OK => return,
        else => unreachable,
    }
}

pub fn main() anyerror!void {
    //const curl_res = try wrap(libcurl.curl_global_init(libcurl.CURL_GLOBAL_ALL));
    //defer libcurl.curl_global_cleanup();
    //std.log.debug("libcurl global initialized", .{});

    const curl = libcurl.curl_easy_init();
    if (curl == null) return error.InitFailed;
    defer libcurl.curl_easy_cleanup(curl);
    std.log.debug("libcurl initialized", .{});

    try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_URL, "https://client.tlsfingerprint.io:8443/"));
    try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_FOLLOWLOCATION, @as(c_long, 1)));

    if (libcurl.curl_easy_perform(curl) == .CURLE_OK) {
        std.log.debug("request successful", .{});
    }

    request: while (true) {
        var built = false;
        var version: ?YAP_VERSIONS = null;
        var protocol: ?PROTOCOLS = null;
        var req_id: ?u8 = null;
        var port: ?u16 = null;
        // while the HTTP spec says servers should always be able to handle any
        // length of URL, the practical limit according to The Interwebs seems
        // to be 2048 characters, in part set by IE way back when
        var target_buf: [2048]u8 = undefined;
        var target_idx: usize = 0;
        var target_terminated = false;

        while (true) {
            // at least while using echo as a test client, I had to constantly
            // reopen these pipes as I'd otherwise constantly get EndOfStream.
            // this probably needs cleaned up somehow or another, but again,
            // proof of concept. hack it til you make it.
            var reqs = try std.fs.cwd().openFile("reqs.fifo", .{ .read = true, .write = false });
            defer reqs.close();
            var _resps = try std.fs.cwd().openFile("resps.fifo", .{ .read = false, .write = true });
            defer _resps.close();
            var resps = std.io.bufferedWriter(_resps.writer());
            const reader = reqs.reader();

            while (reader.readByte()) |c| {
                if (version == null) {
                    version = switch (c) {
                        @enumToInt(YAP_VERSIONS.V0) => YAP_VERSIONS.V0,
                        else => error.InvalidYapVersion,
                    } catch |err| {
                        std.log.err("InvalidYapVersion {d}, resetting", .{c});
                        continue :request;
                    };
                } else if (protocol == null) {
                    protocol = switch (c) {
                        @enumToInt(PROTOCOLS.HTTP) => PROTOCOLS.HTTP,
                        else => error.UnsupportedProtocol,
                    } catch |err| {
                        std.log.err("UnsupportedProtocol {d}, resetting", .{c});
                        continue :request;
                    };
                } else if (req_id == null) {
                    req_id = c;
                } else if (port == null) {
                    port = @as(u16, try reader.readByte()) | @as(u16, c) << 8;
                } else if (!target_terminated) {
                    if (c == 0) {
                        target_terminated = true;
                        built = true;
                    } else {
                        target_buf[target_idx] = c;
                        target_idx += 1;
                    }
                }

                std.log.debug("current state: (" ++
                    "version={d}, " ++
                    "protocol={d}, " ++
                    "req_id={d} " ++
                    "port={d} " ++
                    "target='{s}'" ++
                    ")", .{ version, protocol, req_id, port, target_buf[0..target_idx] });

                if (built) {
                    std.log.debug("BUILT! Ship it.", .{});
                    continue :request;
                }
            } else |err| {
                switch (err) {
                    error.EndOfStream => {},
                    else => std.log.err("received error: {s}", .{err}),
                }
            }
        }
    }

    try resps.flush();
}
