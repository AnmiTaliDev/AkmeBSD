pub const Spinlock = struct {
    state: u32 = 0,

    pub fn acquire(self: *Spinlock) void {
        while (true) {
            if (@cmpxchgWeak(u32, &self.state, 0, 1, .acquire, .monotonic) == null) return;
            while (@atomicLoad(u32, &self.state, .monotonic) != 0) {
                asm volatile ("pause" ::: .{ .memory = true });
            }
        }
    }

    pub fn release(self: *Spinlock) void {
        @atomicStore(u32, &self.state, 0, .release);
    }

    pub fn tryAcquire(self: *Spinlock) bool {
        return @cmpxchgStrong(u32, &self.state, 0, 1, .acquire, .monotonic) == null;
    }
};
