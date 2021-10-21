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
const gen_allocator = std.heap.page_allocator;
const libcurl = @cImport(@cInclude("curl/curl.h"));

const LIBCURL_FALSE = @as(c_long, 0);
const LIBCURL_TRUE = @as(c_long, 1);

const YAP_VERSIONS = enum {
    V0 = @as(u16, 0),
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

fn u16be_from_u8s(left: u8, right: u8) u16 {
    return @as(u16, right) | @as(u16, left) << 8;
}

pub fn main() anyerror!void {
    var reqs = try std.fs.cwd().openFile("reqs.fifo", .{ .read = true, .write = false });
    defer reqs.close();
    var _resps = try std.fs.cwd().openFile("resps.fifo", .{ .read = false, .write = true });
    defer _resps.close();
    var resps = std.io.bufferedWriter(_resps.writer());
    var output = resps.writer();
    const reader = reqs.reader();

    request: while (true) {
        var last_char: u8 = undefined;
        var built = false;
        var version: ?YAP_VERSIONS = null;
        var protocol: ?PROTOCOLS = null;
        var req_id: ?u8 = null;
        var port: ?u16 = null;
        // while the HTTP spec says servers should always be able to handle any
        // length of URL, the practical limit according to The Interwebs seems
        // to be 2048 characters, in part set by IE way back when
        // allow one more byte to append \0
        var target_buf: [2049:0]u8 = undefined;
        var target_idx: usize = 0;
        var target_terminated = false;
        var varargs_terminated = false;
        var body_terminated = false;

        while (reader.readByte()) |c| {
            if (version == null) {
                const next_byte = try reader.readByte();
                const requested_version = u16be_from_u8s(c, next_byte);
                version = switch (requested_version) {
                    @enumToInt(YAP_VERSIONS.V0) => YAP_VERSIONS.V0,
                    else => error.InvalidYapVersion,
                } catch |err| {
                    std.log.err("InvalidYapVersion {d}, resetting", .{requested_version});
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
                const next_byte = try reader.readByte();
                port = u16be_from_u8s(c, next_byte);
            } else if (!target_terminated) {
                target_buf[target_idx] = c;

                if (c == 0) {
                    target_terminated = true;
                } else {
                    target_idx += 1;
                }
            } else if (!varargs_terminated) {
                // TODO FIXME implement varargs (headers, in HTTP at least)

                if (c == 0 and last_char == 0) {
                    varargs_terminated = true;
                    last_char = 1;
                } else if (c == 0) {
                    last_char = c;
                }
            } else if (!body_terminated) {
                // TODO FIXME implement request body

                if (c == 0 and last_char == 0) {
                    body_terminated = true;
                    last_char = 1;
                    built = true;
                } else if (c == 0) {
                    last_char = c;
                }
            }

            std.log.debug("current state: (" ++
                "version={d}, " ++
                "protocol={d}, " ++
                "req_id={d}, " ++
                "port={d}, " ++
                "target='{s}', " ++
                "varargs=<unimplemented>, " ++
                "body=<unimplemented>" ++
                ")", .{ version, protocol, req_id, port, target_buf[0..target_idx] });

            if (built) {
                std.log.debug("BUILT! Ship it.", .{});

                const curl = libcurl.curl_easy_init();
                if (curl == null) return error.InitFailed;
                defer libcurl.curl_easy_cleanup(curl);
                std.log.debug("libcurl initialized", .{});

                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_URL, target_buf[0..]));
                // TODO should these be configurable? or done at all?
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_VERBOSE, LIBCURL_FALSE));
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_FOLLOWLOCATION, LIBCURL_TRUE));
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_TCP_KEEPALIVE, LIBCURL_TRUE));
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_NOPROGRESS, LIBCURL_TRUE));

                // FIXME this is actually wrong, should be a c_long which is a
                // i64 - not sure if uxnyap protocol should change or if we
                // should try to truncate the field somehow
                var http_code: u16 = undefined;
                try wrap(libcurl.curl_easy_getinfo(curl, ._RESPONSE_CODE, &http_code));

                var res_body = std.ArrayList(u8).init(gen_allocator);
                defer res_body.deinit();
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_WRITEFUNCTION, writeCallback));
                try wrap(libcurl.curl_easy_setopt(curl, .CURLOPT_WRITEDATA, &res_body));

                if (libcurl.curl_easy_perform(curl) == .CURLE_OK) {
                    std.log.debug("request complete with status {d}", .{http_code});

                    try output.writeIntBig(u16, @enumToInt(version.?));
                    try output.writeIntBig(u8, @enumToInt(protocol.?));
                    try output.writeIntBig(u8, req_id.?);
                    try output.writeIntBig(u16, http_code);
                    try output.writeIntBig(u16, 0); // just terminate varags, FIXME not implemented

                    try output.writeAll(res_body.items[0..]);

                    // it's known that this needs to change to be binary-safe,
                    // but until then, the protocol says to
                    // double-null-terminate the end of bodies so we're doing
                    // it
                    try output.writeIntBig(u16, 0);
                }

                try resps.flush();
                continue :request;
            }
        } else |err| {
            switch (err) {
                error.EndOfStream => {
                    try resps.flush();
                    std.os.exit(0);
                },
                else => std.log.err("received error: {s}", .{err}),
            }
        }
    }

    try resps.flush();
}

// https://github.com/gaultier/zorrent/blob/095752f5fda62ef21cf3cecb8be3bec434b79277/src/tracker.zig#L263
fn writeCallback(
    p_contents: *c_void,
    size: usize,
    nmemb: usize,
    p_user_data: *std.ArrayList(u8),
) usize {
    const contents = @ptrCast([*c]const u8, p_contents);
    p_user_data.*.appendSlice(contents[0..nmemb]) catch {
        std.process.exit(1);
    };
    return size * nmemb;
}
