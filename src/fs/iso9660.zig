const vfs = @import("vfs.zig");

const BLOCK_SIZE_DEFAULT: u32 = 2048;
const ISO_FLAG_DIRECTORY: u8 = 0x02;

// ISO9660 directory entry on-disk layout (no padding):
//   0:  length          (u8)
//   1:  ext_attr_length (u8)
//   2:  extent_le       (u32 LE)
//   6:  extent_be       (u32 BE)
//  10:  size_le         (u32 LE)
//  14:  size_be         (u32 BE)
//  18:  date            (7 bytes)
//  25:  flags           (u8)
//  26:  file_unit_size  (u8)
//  27:  interleave      (u8)
//  28:  vol_seq_le      (u16 LE)
//  30:  vol_seq_be      (u16 BE)
//  32:  name_len        (u8)
//  33:  file_identifier (name_len bytes)
const DIRENT_HDR: usize = 33;

inline fn deLen(e: []const u8) u8 {
    return e[0];
}
inline fn deExtent(e: []const u8) u32 {
    return @as(u32, e[2]) | (@as(u32, e[3]) << 8) | (@as(u32, e[4]) << 16) | (@as(u32, e[5]) << 24);
}
inline fn deSize(e: []const u8) u32 {
    return @as(u32, e[10]) | (@as(u32, e[11]) << 8) | (@as(u32, e[12]) << 16) | (@as(u32, e[13]) << 24);
}
inline fn deFlags(e: []const u8) u8 {
    return e[25];
}
inline fn deNameLen(e: []const u8) u8 {
    return e[32];
}

// PVD (Primary Volume Descriptor) — 2048 bytes at LBA 16.
// All u32/u16 fields happen to sit at naturally aligned offsets,
// so extern struct is safe here.
const Pvd = extern struct {
    type: u8,
    identifier: [5]u8,
    version: u8,
    unused1: u8,
    system_id: [32]u8,
    volume_id: [32]u8,
    unused2: [8]u8,
    volume_space_size_le: u32,
    volume_space_size_be: u32,
    unused3: [32]u8,
    volume_set_size_le: u16,
    volume_set_size_be: u16,
    volume_seq_number_le: u16,
    volume_seq_number_be: u16,
    logical_block_size_le: u16,
    logical_block_size_be: u16,
    path_table_size_le: u32,
    path_table_size_be: u32,
    type_l_path_table: u32,
    opt_type_l_path_table: u32,
    type_m_path_table: u32,
    opt_type_m_path_table: u32,
    root_directory_entry: [34]u8, // raw DirEntry bytes
    volume_set_id: [128]u8,
    publisher_id: [128]u8,
    preparer_id: [128]u8,
    application_id: [128]u8,
    copyright_file_id: [37]u8,
    abstract_file_id: [37]u8,
    bibliographic_file_id: [37]u8,
    creation_date: [17]u8,
    modification_date: [17]u8,
    expiration_date: [17]u8,
    effective_date: [17]u8,
    file_structure_version: u8,
    unused4: u8,
    application_data: [512]u8,
    reserved: [653]u8,
};

var iso_data: ?[]const u8 = null;
var primary_volume: ?*align(1) const Pvd = null;
var block_size: u32 = BLOCK_SIZE_DEFAULT;
var initialized: bool = false;

fn readBlock(lba: u32) ?[]const u8 {
    const data = iso_data orelse return null;
    const offset = @as(usize, lba) * block_size;
    if (offset >= data.len) return null;
    const end = @min(offset + block_size, data.len);
    return data[offset..end];
}

fn fileSlice(lba: u32, size: u32) ?[]const u8 {
    const data = iso_data orelse return null;
    const offset = @as(usize, lba) * block_size;
    if (offset >= data.len) return null;
    const end = @min(offset + @as(usize, size), data.len);
    return data[offset..end];
}

fn normalizeFilename(name: []const u8, out: []u8) []u8 {
    var end = name.len;
    for (name, 0..) |c, i| {
        if (c == ';') { end = i; break; }
    }
    const n = @min(end, out.len - 1);
    @memcpy(out[0..n], name[0..n]);
    if (n > 0 and out[n - 1] == '.') {
        out[n - 1] = 0;
        return out[0 .. n - 1];
    }
    out[n] = 0;
    return out[0..n];
}

fn toLower(s: []u8) void {
    for (s) |*c| {
        if (c.* >= 'A' and c.* <= 'Z') c.* += 32;
    }
}

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

pub fn init(data: []const u8) void {
    iso_data = data;
    var i: u32 = 16;
    while (i < 32) : (i += 1) {
        const blk = readBlock(i) orelse return;
        if (blk.len < @sizeOf(Pvd)) continue;
        const vd: *align(1) const Pvd = @ptrCast(blk.ptr);
        if (vd.type == 1 and vd.identifier[0] == 'C' and vd.identifier[1] == 'D' and
            vd.identifier[2] == '0' and vd.identifier[3] == '0' and vd.identifier[4] == '1')
        {
            primary_volume = vd;
            block_size = vd.logical_block_size_le;
            initialized = true;
            return;
        }
        if (vd.type == 255) break;
    }
}

pub fn findFile(path: []const u8) ?[]const u8 {
    if (!initialized) return null;
    const pvd = primary_volume orelse return null;
    const root_raw = pvd.root_directory_entry[0..];
    var cur_extent = deExtent(root_raw);
    var cur_size = deSize(root_raw);

    var search = path;
    if (search.len > 0 and search[0] == '/') search = search[1..];
    if (search.len == 0) return fileSlice(cur_extent, cur_size);

    var it = search;
    while (it.len > 0) {
        var slash: usize = 0;
        while (slash < it.len and it[slash] != '/') : (slash += 1) {}
        const component = it[0..slash];
        const found = findEntryInDir(cur_extent, cur_size, component) orelse return null;
        cur_extent = found.extent;
        cur_size = found.size;
        it = if (slash < it.len) it[slash + 1 ..] else it[it.len..];
    }

    return fileSlice(cur_extent, cur_size);
}

const EntryInfo = struct { extent: u32, size: u32 };

fn findEntryInDir(dir_extent: u32, dir_size: u32, name: []const u8) ?EntryInfo {
    const dir_data = readBlock(dir_extent) orelse return null;
    var offset: usize = 0;
    while (offset + DIRENT_HDR <= @min(dir_size, dir_data.len)) {
        const e = dir_data[offset..];
        const len = deLen(e);
        if (len == 0) break;
        const nlen = deNameLen(e);
        const name_start = DIRENT_HDR;
        const name_end = name_start + nlen;
        if (name_end > len or offset + name_end > dir_data.len) break;
        const raw_name = e[name_start..name_end];
        if (nlen == 1 and (raw_name[0] == 0 or raw_name[0] == 1)) {
            offset += len;
            continue;
        }
        var norm_buf: [256]u8 = undefined;
        const norm = normalizeFilename(raw_name, &norm_buf);
        toLower(norm);
        if (strEq(norm, name)) return .{ .extent = deExtent(e), .size = deSize(e) };
        offset += len;
    }
    return null;
}

pub fn isReady() bool {
    return initialized;
}

pub fn mountToVfs(mount_point: []const u8) void {
    if (!initialized) return;
    const pvd = primary_volume orelse return;
    const root_raw = pvd.root_directory_entry[0..];
    var mp_buf: [256]u8 = undefined;
    const mp_n = @min(mount_point.len, mp_buf.len - 1);
    @memcpy(mp_buf[0..mp_n], mount_point[0..mp_n]);
    mp_buf[mp_n] = 0;
    toLower(mp_buf[0..mp_n]);
    _ = vfs.mkdir(mp_buf[0..mp_n]);
    mountDirRecursive(mp_buf[0..mp_n], deExtent(root_raw), deSize(root_raw));
}

fn mountDirRecursive(mount_point: []const u8, dir_extent: u32, dir_size: u32) void {
    const dir_data = readBlock(dir_extent) orelse return;
    var offset: usize = 0;
    while (offset + DIRENT_HDR <= @min(@as(usize, dir_size), dir_data.len)) {
        const e = dir_data[offset..];
        const len = deLen(e);
        if (len == 0) break;
        const nlen = deNameLen(e);
        const name_end_in_e = DIRENT_HDR + nlen;
        if (name_end_in_e > len or offset + name_end_in_e > dir_data.len) {
            offset += len;
            continue;
        }
        const raw_name = e[DIRENT_HDR .. DIRENT_HDR + nlen];
        if (nlen == 1 and (raw_name[0] == 0 or raw_name[0] == 1)) {
            offset += len;
            continue;
        }

        var norm_buf: [256]u8 = undefined;
        const norm = normalizeFilename(raw_name, &norm_buf);
        toLower(norm);

        var vfs_path_buf: [512]u8 = undefined;
        var idx: usize = 0;
        for (mount_point) |c| {
            if (idx >= 510) break;
            vfs_path_buf[idx] = c;
            idx += 1;
        }
        if (idx > 0 and vfs_path_buf[idx - 1] != '/') {
            vfs_path_buf[idx] = '/';
            idx += 1;
        }
        for (norm) |c| {
            if (idx >= 511) break;
            vfs_path_buf[idx] = c;
            idx += 1;
        }
        const vfs_path = vfs_path_buf[0..idx];

        const entry_extent = deExtent(e);
        const entry_size = deSize(e);
        const entry_flags = deFlags(e);

        if (entry_flags & ISO_FLAG_DIRECTORY != 0) {
            _ = vfs.mkdir(vfs_path);
            mountDirRecursive(vfs_path, entry_extent, entry_size);
        } else {
            // Pass zero-copy slice directly into the ISO module memory.
            const file_data = fileSlice(entry_extent, entry_size) orelse {
                offset += len;
                continue;
            };
            _ = vfs.create(vfs_path, file_data);
        }
        offset += len;
    }
}
