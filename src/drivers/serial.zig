const io = @import("../arch/io.zig");

const PORT: u16 = 0x3F8;

pub fn init() bool {
    io.outb(PORT + 1, 0x00);
    io.outb(PORT + 3, 0x80);
    io.outb(PORT + 0, 0x03);
    io.outb(PORT + 1, 0x00);
    io.outb(PORT + 3, 0x03);
    io.outb(PORT + 2, 0xC7);
    io.outb(PORT + 4, 0x0B);
    io.outb(PORT + 4, 0x1E);
    io.outb(PORT + 0, 0xAE);

    if (io.inb(PORT + 0) != 0xAE) return false;

    io.outb(PORT + 4, 0x0F);
    return true;
}

fn isTransmitEmpty() bool {
    return io.inb(PORT + 5) & 0x20 != 0;
}

pub fn writeByte(c: u8) void {
    while (!isTransmitEmpty()) {}
    io.outb(PORT, c);
}

pub fn print(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') writeByte('\r');
        writeByte(c);
    }
}

pub fn received() bool {
    return io.inb(PORT + 5) & 1 != 0;
}

pub fn readByte() u8 {
    while (!received()) {}
    return io.inb(PORT);
}
