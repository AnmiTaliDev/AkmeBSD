pub const Header = extern struct {
    ident: [16]u8,
    type: u16,
    machine: u16,
    version: u32,
    entry: u64,
    phoff: u64,
    shoff: u64,
    flags: u32,
    ehsize: u16,
    phentsize: u16,
    phnum: u16,
    shentsize: u16,
    shnum: u16,
    shstrndx: u16,
};

pub const Phdr = extern struct {
    type: u32,
    flags: u32,
    offset: u64,
    vaddr: u64,
    paddr: u64,
    filesz: u64,
    memsz: u64,
    align_: u64,
};

pub const PT_LOAD: u32 = 1;
pub const PF_X: u32 = 0x1;
pub const PF_W: u32 = 0x2;
pub const PF_R: u32 = 0x4;

const ELFMAG = [4]u8{ 0x7F, 'E', 'L', 'F' };
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;

pub const ProgramInfo = struct {
    entry_point: u64,
    text_start: u64,
    text_size: u64,
    data_start: u64,
    data_size: u64,
    bss_start: u64,
    bss_size: u64,
};

pub fn validate(data: []const u8) bool {
    if (data.len < 16) return false;
    if (!@import("std").mem.eql(u8, data[0..4], &ELFMAG)) return false;
    if (data[4] != ELFCLASS64) return false;
    if (data[5] != ELFDATA2LSB) return false;
    return true;
}

pub fn header(data: []const u8) *align(1) const Header {
    return @ptrCast(data.ptr);
}

pub fn phdr(data: []const u8, idx: u16) ?*align(1) const Phdr {
    const h = header(data);
    if (idx >= h.phnum) return null;
    const off = @as(usize, h.phoff) + @as(usize, idx) * @as(usize, h.phentsize);
    if (off + @sizeOf(Phdr) > data.len) return null;
    return @ptrCast(data[off..].ptr);
}

pub fn loadProgramRelative(dest: [*]u8, base_vaddr: u64, data: []const u8) bool {
    if (!validate(data)) return false;
    const h = header(data);
    for (0..h.phnum) |i| {
        const ph = phdr(data, @intCast(i)) orelse return false;
        if (ph.type != PT_LOAD) continue;
        const rel_vaddr = ph.vaddr - base_vaddr;
        const seg_dest = dest + rel_vaddr;
        const file_sz: usize = @intCast(ph.filesz);
        const mem_sz: usize = @intCast(ph.memsz);
        const off: usize = @intCast(ph.offset);
        if (off + file_sz > data.len) return false;
        @memcpy(seg_dest[0..file_sz], data[off .. off + file_sz]);
        if (mem_sz > file_sz) @memset(seg_dest[file_sz..mem_sz], 0);
    }
    return true;
}

pub fn programInfo(data: []const u8) ?ProgramInfo {
    if (!validate(data)) return null;
    const h = header(data);
    var info = ProgramInfo{ .entry_point = h.entry, .text_start = 0, .text_size = 0, .data_start = 0, .data_size = 0, .bss_start = 0, .bss_size = 0 };
    for (0..h.phnum) |i| {
        const ph = phdr(data, @intCast(i)) orelse continue;
        if (ph.type != PT_LOAD) continue;
        if (ph.flags & PF_X != 0) {
            info.text_start = ph.vaddr;
            info.text_size = ph.memsz;
        } else if (ph.flags & PF_W != 0) {
            info.data_start = ph.vaddr;
            info.data_size = ph.filesz;
            info.bss_start = ph.vaddr + ph.filesz;
            info.bss_size = ph.memsz - ph.filesz;
        }
    }
    return info;
}

pub fn vaddressRange(data: []const u8) ?struct { min: u64, max: u64 } {
    if (!validate(data)) return null;
    const h = header(data);
    var min: u64 = @as(u64, @bitCast(@as(i64, -1)));
    var max: u64 = 0;
    for (0..h.phnum) |i| {
        const ph = phdr(data, @intCast(i)) orelse continue;
        if (ph.type != PT_LOAD) continue;
        if (ph.vaddr < min) min = ph.vaddr;
        const end = ph.vaddr + ph.memsz;
        if (end > max) max = end;
    }
    if (max == 0) return null;
    return .{ .min = min, .max = max };
}
