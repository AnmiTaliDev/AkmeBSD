// Minimal freestanding test — pure position-independent inline asm.
// No external symbol references; all immediates embedded in the asm.
// Works correctly after loadProgramRelative() relocation to HHDM.
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        // Serial port (COM1 = 0x3F8) initialisation
        \\  mov $0x3F9, %%dx
        \\  xor %%al, %%al
        \\  out %%al, %%dx

        \\  mov $0x3FB, %%dx
        \\  mov $0x80, %%al
        \\  out %%al, %%dx

        \\  mov $0x3F8, %%dx
        \\  mov $0x03, %%al
        \\  out %%al, %%dx

        \\  mov $0x3F9, %%dx
        \\  xor %%al, %%al
        \\  out %%al, %%dx

        \\  mov $0x3FB, %%dx
        \\  mov $0x03, %%al
        \\  out %%al, %%dx

        \\  mov $0x3FA, %%dx
        \\  mov $0xC7, %%al
        \\  out %%al, %%dx

        \\  mov $0x3FC, %%dx
        \\  mov $0x0B, %%al
        \\  out %%al, %%dx

        // Print "Work!!!\r\n"
        \\  mov $0x3FD, %%dx
        \\.Lw1: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lw1
        \\  mov $0x3F8, %%dx
        \\  mov $87, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Lo1: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lo1
        \\  mov $0x3F8, %%dx
        \\  mov $111, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Lr1: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lr1
        \\  mov $0x3F8, %%dx
        \\  mov $114, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Lk1: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lk1
        \\  mov $0x3F8, %%dx
        \\  mov $107, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Le1: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Le1
        \\  mov $0x3F8, %%dx
        \\  mov $33, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Le2: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Le2
        \\  mov $0x3F8, %%dx
        \\  mov $33, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Le3: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Le3
        \\  mov $0x3F8, %%dx
        \\  mov $33, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Lcr: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lcr
        \\  mov $0x3F8, %%dx
        \\  mov $13, %%al
        \\  out %%al, %%dx
        \\  mov $0x3FD, %%dx

        \\.Lnl: in %%dx, %%al
        \\  test $0x20, %%al
        \\  jz .Lnl
        \\  mov $0x3F8, %%dx
        \\  mov $10, %%al
        \\  out %%al, %%dx

        // Halt loop
        \\.Lhalt: hlt
        \\  jmp .Lhalt
        ::: .{ .memory = true, .rax = true, .rdx = true }
    );
}
