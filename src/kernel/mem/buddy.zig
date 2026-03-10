const spinlock = @import("../../arch/spinlock.zig");

pub const MIN_ORDER: u5 = 12;
pub const MAX_ORDER: u5 = 20;

pub fn blockSize(order: u5) usize {
    return @as(usize, 1) << order;
}

pub const BuddyAllocator = struct {
    pool_start: [*]u8,
    pool_size: usize,
    hhdm_offset: u64,
    free_area_bitmap: [MAX_ORDER + 1][*]u32,
    free_area_size: [MAX_ORDER + 1]usize,
    max_blocks: [MAX_ORDER + 1]usize,
    lock: spinlock.Spinlock,

    pub fn init(self: *BuddyAllocator, pool: [*]u8, size: usize, hhdm: u64) void {
        self.lock = .{};
        self.pool_start = pool;
        self.pool_size = size;
        self.hhdm_offset = hhdm;

        const min_block = blockSize(MIN_ORDER);
        if (self.pool_size % min_block != 0) {
            self.pool_size -= self.pool_size % min_block;
        }

        var preliminary_max: [MAX_ORDER + 1]usize = undefined;
        var order: u5 = MIN_ORDER;
        while (order <= MAX_ORDER) : (order += 1) {
            preliminary_max[order] = self.pool_size / blockSize(order);
        }

        var total_bitmap_bytes: usize = 0;
        order = MIN_ORDER;
        while (order <= MAX_ORDER) : (order += 1) {
            const words = (preliminary_max[order] + 31) / 32;
            total_bitmap_bytes += words * @sizeOf(u32);
        }

        self.pool_size -= total_bitmap_bytes;
        if (self.pool_size % min_block != 0) {
            self.pool_size -= self.pool_size % min_block;
        }

        order = MIN_ORDER;
        while (order <= MAX_ORDER) : (order += 1) {
            self.max_blocks[order] = self.pool_size / blockSize(order);
        }

        var bitmap_ptr = @intFromPtr(self.pool_start) + self.pool_size + total_bitmap_bytes;
        order = MAX_ORDER;
        while (true) : (order -= 1) {
            const words = (self.max_blocks[order] + 31) / 32;
            bitmap_ptr -= words * @sizeOf(u32);
            self.free_area_bitmap[order] = @ptrFromInt(bitmap_ptr);
            self.free_area_size[order] = 0;
            for (0..words) |i| {
                self.free_area_bitmap[order][i] = 0xFFFFFFFF;
            }
            if (order == MIN_ORDER) break;
        }

        var top = MAX_ORDER;
        while (top > MIN_ORDER and self.max_blocks[top] == 0) : (top -= 1) {}

        if (self.max_blocks[top] > 0) {
            clearBit(self.free_area_bitmap[top], 0);
            self.free_area_size[top] = 1;
        }
    }

    pub fn alloc(self: *BuddyAllocator, size: usize) ?[*]u8 {
        if (size == 0 or size > self.pool_size) return null;
        self.lock.acquire();
        defer self.lock.release();
        const order = minimumOrder(size);
        return self.allocBlock(order);
    }

    pub fn free(self: *BuddyAllocator, ptr: [*]u8, order: u5) void {
        self.lock.acquire();
        defer self.lock.release();
        self.freeBlock(ptr, order);
    }

    pub fn getFreeMemory(self: *BuddyAllocator) usize {
        self.lock.acquire();
        defer self.lock.release();
        var total: usize = 0;
        var order: u5 = MIN_ORDER;
        while (order <= MAX_ORDER) : (order += 1) {
            total += self.free_area_size[order] * blockSize(order);
        }
        return total;
    }

    pub fn getTotalMemory(self: *const BuddyAllocator) usize {
        return self.pool_size;
    }

    fn allocBlock(self: *BuddyAllocator, order: u5) ?[*]u8 {
        if (order > MAX_ORDER) return null;

        if (self.free_area_size[order] == 0) {
            const larger = self.allocBlock(order + 1) orelse return null;
            const larger_idx = blockIndex(larger, self.pool_start, order + 1);
            const left = larger_idx * 2;
            const right = larger_idx * 2 + 1;
            if (left < self.max_blocks[order]) {
                clearBit(self.free_area_bitmap[order], left);
                self.free_area_size[order] += 1;
            }
            if (right < self.max_blocks[order]) {
                clearBit(self.free_area_bitmap[order], right);
                self.free_area_size[order] += 1;
            }
        }

        const idx = findFirstFree(self.free_area_bitmap[order], self.max_blocks[order]) orelse return null;
        setBit(self.free_area_bitmap[order], idx);
        self.free_area_size[order] -= 1;
        return blockAddr(self.pool_start, order, idx);
    }

    fn freeBlock(self: *BuddyAllocator, ptr: [*]u8, order: u5) void {
        var cur_ptr = ptr;
        var cur_order = order;
        var idx = blockIndex(cur_ptr, self.pool_start, cur_order);

        clearBit(self.free_area_bitmap[cur_order], idx);
        self.free_area_size[cur_order] += 1;

        while (cur_order < MAX_ORDER) {
            const buddy_offset = @as(usize, idx) * blockSize(cur_order) ^ blockSize(cur_order);
            const buddy = self.pool_start + buddy_offset;
            const buddy_idx = blockIndex(buddy, self.pool_start, cur_order);

            if (buddy_idx >= self.max_blocks[cur_order]) break;
            if (testBit(self.free_area_bitmap[cur_order], buddy_idx)) break;

            setBit(self.free_area_bitmap[cur_order], idx);
            setBit(self.free_area_bitmap[cur_order], buddy_idx);
            self.free_area_size[cur_order] -= 2;

            const merged = if (@intFromPtr(cur_ptr) < @intFromPtr(buddy)) cur_ptr else buddy;
            cur_order += 1;
            cur_ptr = merged;
            idx = blockIndex(merged, self.pool_start, cur_order);
            clearBit(self.free_area_bitmap[cur_order], idx);
            self.free_area_size[cur_order] += 1;
        }
    }
};

fn minimumOrder(size: usize) u5 {
    var order: u5 = MIN_ORDER;
    while (order < MAX_ORDER and blockSize(order) < size) : (order += 1) {}
    return order;
}

fn blockIndex(ptr: [*]u8, pool: [*]u8, order: u5) usize {
    return (@intFromPtr(ptr) - @intFromPtr(pool)) / blockSize(order);
}

fn blockAddr(pool: [*]u8, order: u5, idx: usize) [*]u8 {
    return pool + idx * blockSize(order);
}

fn setBit(bitmap: [*]u32, idx: usize) void {
    bitmap[idx / 32] |= @as(u32, 1) << @as(u5, @intCast(idx % 32));
}

fn clearBit(bitmap: [*]u32, idx: usize) void {
    bitmap[idx / 32] &= ~(@as(u32, 1) << @as(u5, @intCast(idx % 32)));
}

fn testBit(bitmap: [*]u32, idx: usize) bool {
    return bitmap[idx / 32] & (@as(u32, 1) << @as(u5, @intCast(idx % 32))) != 0;
}

fn findFirstFree(bitmap: [*]u32, max: usize) ?usize {
    var i: usize = 0;
    while (i < max) : (i += 1) {
        if (!testBit(bitmap, i)) return i;
    }
    return null;
}
