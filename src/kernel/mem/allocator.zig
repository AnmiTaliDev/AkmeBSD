const limine = @import("../../limine.zig");
const buddy_mod = @import("buddy.zig");
const panic = @import("../../arch/panic.zig");

const ALLOC_MAGIC: u32 = 0xA110C123;

const AllocInfo = extern struct {
    order: u32,
    magic: u32,
    user_size: usize,
};

export var memmap_request: limine.MemmapRequest = .{};
export var hhdm_request: limine.HhdmRequest = .{};

var buddy: buddy_mod.BuddyAllocator = undefined;
var hhdm_offset: u64 = 0;
var allocated_memory: usize = 0;
var alloc_count: usize = 0;
var free_count: usize = 0;

pub fn init() void {
    if (hhdm_request.response == null) panic.panic("HHDM request failed");
    hhdm_offset = hhdm_request.response.?.offset;

    if (memmap_request.response == null) panic.panic("Memory map request failed");
    const memmap = memmap_request.response.?;

    var best_size: usize = 0;
    var best_base: u64 = 0;

    for (0..memmap.entry_count) |i| {
        const entry = memmap.entries.?[i] orelse continue;
        if (entry.type == limine.MemmapEntry.usable and entry.length > best_size) {
            best_size = @intCast(entry.length);
            best_base = entry.base;
        }
    }

    if (best_size == 0) panic.panic("No usable memory region found");

    const pool: [*]u8 = @ptrFromInt(@as(usize, @intCast(best_base)) + @as(usize, @intCast(hhdm_offset)));
    buddy.init(pool, best_size, hhdm_offset);
}

pub fn kmalloc(size: usize) ?[*]u8 {
    if (size == 0) return null;

    const total = size + @sizeOf(AllocInfo);
    var order: u5 = buddy_mod.MIN_ORDER;
    while (order < buddy_mod.MAX_ORDER and buddy_mod.blockSize(order) < total) : (order += 1) {}

    const block = buddy.alloc(buddy_mod.blockSize(order)) orelse return null;

    const info: *AllocInfo = @alignCast(@ptrCast(block));
    info.order = order;
    info.magic = ALLOC_MAGIC;
    info.user_size = size;

    allocated_memory += size;
    alloc_count += 1;

    return block + @sizeOf(AllocInfo);
}

pub fn kfree(ptr: [*]u8) void {
    const raw = ptr - @sizeOf(AllocInfo);
    const info: *AllocInfo = @alignCast(@ptrCast(raw));

    if (info.magic != ALLOC_MAGIC) panic.panic("kfree: corrupted allocation");
    if (info.order < buddy_mod.MIN_ORDER or info.order > buddy_mod.MAX_ORDER) {
        panic.panic("kfree: invalid order");
    }

    if (allocated_memory >= info.user_size) {
        allocated_memory -= info.user_size;
    }
    free_count += 1;

    buddy.free(raw, @intCast(info.order));
}

pub fn getTotal() usize {
    return buddy.getTotalMemory();
}

pub fn getFree() usize {
    return buddy.getFreeMemory();
}

pub fn getUsed() usize {
    return allocated_memory;
}

pub fn formatSize(size: usize, buf: []u8) []u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB" };
    var unit: usize = 0;
    var val = size;
    while (val >= 1024 and unit < 3) : (unit += 1) {
        val /= 1024;
    }
    const int_part = val;
    const frac = (size / (@as(usize, 1) << @as(u6, @intCast(unit * 10)))) % 10;
    return intoBuf(buf, int_part, frac, units[unit]);
}

fn intoBuf(buf: []u8, int_part: usize, frac: usize, unit: []const u8) []u8 {
    var tmp: [32]u8 = undefined;
    var pos: usize = 0;
    var n = int_part;
    if (n == 0) {
        tmp[pos] = '0';
        pos += 1;
    } else {
        const start = pos;
        while (n > 0) : (n /= 10) {
            tmp[pos] = '0' + @as(u8, @intCast(n % 10));
            pos += 1;
        }
        var l = start;
        var r = pos - 1;
        while (l < r) : ({ l += 1; r -= 1; }) {
            const t = tmp[l];
            tmp[l] = tmp[r];
            tmp[r] = t;
        }
    }
    tmp[pos] = '.';
    pos += 1;
    tmp[pos] = '0' + @as(u8, @intCast(frac));
    pos += 1;
    tmp[pos] = ' ';
    pos += 1;
    for (unit) |c| {
        tmp[pos] = c;
        pos += 1;
    }
    const len = @min(pos, buf.len);
    @memcpy(buf[0..len], tmp[0..len]);
    return buf[0..len];
}
