const serial = @import("../drivers/serial.zig");

pub fn panic(msg: []const u8) noreturn {
    serial.print("\r\nPANIC: ");
    serial.print(msg);
    serial.print("\r\n");
    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}
