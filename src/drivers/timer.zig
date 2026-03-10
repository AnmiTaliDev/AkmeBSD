const io = @import("../arch/io.zig");

pub fn initPit() void {
    const divisor: u16 = 1193182 / 1000;
    io.outb(0x43, 0x36);
    io.outb(0x40, @intCast(divisor & 0xFF));
    io.outb(0x40, @intCast(divisor >> 8));
}

pub fn readCount() u16 {
    io.outb(0x43, 0x00);
    const lo = io.inb(0x40);
    const hi = io.inb(0x40);
    return (@as(u16, hi) << 8) | lo;
}
