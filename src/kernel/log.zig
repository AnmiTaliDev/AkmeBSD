const std = @import("std");
const serial = @import("../drivers/serial.zig");
const vfs = @import("../fs/vfs.zig");

pub const Level = enum { fatal, err, warn, info, debug, trace };

pub const current_level: Level = .trace;

var log_buf: [4000]u8 = undefined;
var log_len: usize = 0;

pub fn init() void {
    log_len = 0;
    const header = "=== Akme System Log ===\n";
    appendToLog(header);
    _ = vfs.create("/var/log/system.log", log_buf[0..log_len]);
}

fn appendToLog(msg: []const u8) void {
    for (msg) |c| {
        if (log_len >= log_buf.len - 1) break;
        log_buf[log_len] = c;
        log_len += 1;
    }
}

fn logWrite(level: Level, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(level) > @intFromEnum(current_level)) return;

    const prefix = switch (level) {
        .fatal => "[FATAL] ",
        .err   => "[ERROR] ",
        .warn  => "[WARN]  ",
        .info  => "[INFO]  ",
        .debug => "[DEBUG] ",
        .trace => "[TRACE] ",
    };

    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..0];

    serial.print(prefix);
    serial.print(msg);

    appendToLog(prefix);
    appendToLog(msg);
    _ = vfs.create("/var/log/system.log", log_buf[0..log_len]);
}

pub fn fatal(comptime fmt: []const u8, args: anytype) void {
    logWrite(.fatal, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    logWrite(.err, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    logWrite(.warn, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    logWrite(.info, fmt, args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    logWrite(.debug, fmt, args);
}

pub fn trace(comptime fmt: []const u8, args: anytype) void {
    logWrite(.trace, fmt, args);
}
