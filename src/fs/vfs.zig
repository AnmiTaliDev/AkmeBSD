pub const MAX_FILES: usize = 256;
pub const MAX_HANDLES: usize = 64;
pub const MAX_FILENAME: usize = 256;

pub const FileType = enum { file, dir, device };

pub const DevOps = struct {
    read: ?*const fn (*File, []u8, *usize) isize = null,
    write: ?*const fn (*File, []const u8, *usize) isize = null,
    seek: ?*const fn (*File, isize, SeekWhence, *usize) isize = null,
    ioctl: ?*const fn (*File, usize, ?*anyopaque) i32 = null,
};

pub const File = struct {
    name: [MAX_FILENAME]u8 = [_]u8{0} ** MAX_FILENAME,
    used: bool = false,
    size: usize = 0,
    type: FileType = .file,
    data: []const u8 = &[_]u8{},
    ops: DevOps = .{},
    dev_data: ?*anyopaque = null,
};

pub const Handle = struct {
    used: bool = false,
    fd: i32 = -1,
    file: ?*File = null,
    position: usize = 0,
    flags: u32 = 0,
};

pub const SeekWhence = enum(u8) { set = 0, cur = 1, end = 2 };

pub const Flags = struct {
    pub const read: u32 = 0x01;
    pub const write: u32 = 0x02;
    pub const creat: u32 = 0x04;
    pub const append: u32 = 0x08;
};

const PseudoFd = struct {
    pub const dev_null: i32 = 1000;
    pub const dev_zero: i32 = 1001;
    pub const dev_stdin: i32 = 1003;
    pub const dev_stdout: i32 = 1004;
    pub const dev_stderr: i32 = 1005;
};

var files: [MAX_FILES]File = [_]File{.{}} ** MAX_FILES;
var handles: [MAX_HANDLES]Handle = [_]Handle{.{}} ** MAX_HANDLES;
var next_fd: i32 = 3;

pub fn init() void {
    @memset(@as([*]u8, @ptrCast(&files))[0..@sizeOf(@TypeOf(files))], 0);
    @memset(@as([*]u8, @ptrCast(&handles))[0..@sizeOf(@TypeOf(handles))], 0);

    handles[0] = .{ .used = true, .fd = 0, .flags = Flags.read };
    handles[1] = .{ .used = true, .fd = 1, .flags = Flags.write };
    handles[2] = .{ .used = true, .fd = 2, .flags = Flags.write };

    _ = mkdir("/home");
    _ = mkdir("/tmp");
    _ = mkdir("/var");
    _ = mkdir("/var/log");
    _ = mkdir("/var/cache");
    _ = mkdir("/dev");
}

fn nameEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

fn nameLen(name: []const u8) usize {
    for (name, 0..) |c, i| if (c == 0) return i;
    return name.len;
}

fn copyName(dst: []u8, src: []const u8) void {
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

fn findFile(path: []const u8) ?*File {
    for (&files) |*f| {
        if (!f.used) continue;
        const flen = nameLen(&f.name);
        if (nameEq(f.name[0..flen], path)) return f;
    }
    return null;
}

fn getHandle(fd: i32) ?*Handle {
    for (&handles) |*h| {
        if (h.used and h.fd == fd) return h;
    }
    return null;
}

fn allocFd() i32 {
    var i: i32 = next_fd;
    while (i < MAX_HANDLES + 3) : (i += 1) {
        if (i == PseudoFd.dev_null or i == PseudoFd.dev_zero or
            i == PseudoFd.dev_stdin or i == PseudoFd.dev_stdout or i == PseudoFd.dev_stderr) continue;
        if (getHandle(i) == null) {
            next_fd = i + 1;
            return i;
        }
    }
    return -1;
}

fn freeSlot() ?*File {
    for (&files) |*f| if (!f.used) return f;
    return null;
}

fn freeHandleSlot() ?*Handle {
    for (&handles) |*h| if (!h.used) return h;
    return null;
}

pub fn mkdir(path: []const u8) i32 {
    if (path.len >= MAX_FILENAME) return -1;
    if (findFile(path)) |f| {
        return if (f.type == .dir) 0 else -2;
    }
    const f = freeSlot() orelse return -3;
    copyName(&f.name, path);
    f.size = 0;
    f.used = true;
    f.type = .dir;
    return 0;
}

pub fn create(path: []const u8, data: []const u8) i32 {
    if (path.len >= MAX_FILENAME) return -1;
    if (findFile(path)) |f| {
        if (f.type == .dir) return -4;
        f.data = data;
        f.size = data.len;
        return 0;
    }
    const f = freeSlot() orelse return -3;
    copyName(&f.name, path);
    f.data = data;
    f.size = data.len;
    f.used = true;
    f.type = .file;
    return 0;
}

pub fn pseudoRegister(
    path: []const u8,
    read_fn: ?*const fn (*File, []u8, *usize) isize,
    write_fn: ?*const fn (*File, []const u8, *usize) isize,
    seek_fn: ?*const fn (*File, isize, SeekWhence, *usize) isize,
    ioctl_fn: ?*const fn (*File, usize, ?*anyopaque) i32,
    dev_data: ?*anyopaque,
) i32 {
    if (path.len >= MAX_FILENAME) return -1;
    if (findFile(path)) |f| {
        f.ops = .{ .read = read_fn, .write = write_fn, .seek = seek_fn, .ioctl = ioctl_fn };
        f.dev_data = dev_data;
        return 0;
    }
    const f = freeSlot() orelse return -3;
    copyName(&f.name, path);
    f.size = 0;
    f.used = true;
    f.type = .device;
    f.ops = .{ .read = read_fn, .write = write_fn, .seek = seek_fn, .ioctl = ioctl_fn };
    f.dev_data = dev_data;
    return 0;
}

pub fn read(path: []const u8) ?[]const u8 {
    const f = findFile(path) orelse return null;
    return f.data;
}

pub fn open(path: []const u8, flags: u32) i32 {
    var file = findFile(path);
    if (file == null and flags & Flags.creat != 0) {
        _ = create(path, &[_]u8{});
        file = findFile(path);
    }
    const f = file orelse return -1;
    const h = freeHandleSlot() orelse return -2;
    const fd = allocFd();
    if (fd < 0) return -3;
    h.* = .{ .used = true, .fd = fd, .file = f, .position = 0, .flags = flags };
    return fd;
}

pub fn readFd(fd: i32, buf: []u8) isize {
    const h = getHandle(fd) orelse return -9;
    if (h.flags & Flags.read == 0) return -13;
    const f = h.file orelse return -9;
    if (fd == 0 or fd == PseudoFd.dev_stdin) return 0;
    if (f.type == .device) {
        if (f.ops.read) |rfn| return rfn(f, buf, &h.position);
        return -13;
    }
    if (h.position >= f.size) return 0;
    const remaining = f.size - h.position;
    const to_read = @min(buf.len, remaining);
    @memcpy(buf[0..to_read], f.data[h.position .. h.position + to_read]);
    h.position += to_read;
    return @intCast(to_read);
}

pub fn writeFd(fd: i32, buf: []const u8) isize {
    const h = getHandle(fd) orelse return -9;
    if (h.flags & Flags.write == 0) return -13;
    if (fd == 1 or fd == 2 or fd == PseudoFd.dev_stdout or fd == PseudoFd.dev_stderr) {
        return @intCast(buf.len);
    }
    const f = h.file orelse return -9;
    if (f.type == .device) {
        if (f.ops.write) |wfn| return wfn(f, buf, &h.position);
        return -13;
    }
    return -30; // EROFS: read-only file system
}

pub fn close(fd: i32) i32 {
    if (fd < 3) return 0;
    const h = getHandle(fd) orelse return -1;
    h.* = .{};
    return 0;
}

pub fn seek(fd: i32, offset: isize, whence: SeekWhence) isize {
    const h = getHandle(fd) orelse return -1;
    const f = h.file orelse return -2;
    if (f.type == .device) {
        if (f.ops.seek) |sfn| return sfn(f, offset, whence, &h.position);
    }
    const new_pos: isize = switch (whence) {
        .set => offset,
        .cur => @as(isize, @intCast(h.position)) + offset,
        .end => @as(isize, @intCast(f.size)) + offset,
    };
    if (new_pos < 0) {
        h.position = 0;
    } else if (@as(usize, @intCast(new_pos)) > f.size) {
        h.position = f.size;
    } else {
        h.position = @intCast(new_pos);
    }
    return @intCast(h.position);
}

pub fn exists(path: []const u8) bool {
    return findFile(path) != null;
}

pub fn isDir(path: []const u8) bool {
    const f = findFile(path) orelse return false;
    return f.type == .dir;
}

pub fn isDevice(path: []const u8) bool {
    const f = findFile(path) orelse return false;
    return f.type == .device;
}

pub fn delete(path: []const u8) i32 {
    const f = findFile(path) orelse return -1;
    for (&handles) |*h| {
        if (h.used and h.file == f) h.* = .{};
    }
    f.* = .{};
    return 0;
}

pub fn list() void {
    for (files, 0..) |*f, i| {
        if (!f.used) continue;
        const flen = nameLen(&f.name);
        _ = i;
        _ = flen;
    }
}

pub fn getFiles() []File {
    return &files;
}
