const vfs = @import("../fs/vfs.zig");
const elf = @import("elf.zig");
const mem = @import("mem/allocator.zig");
const log = @import("log.zig");

const STACK_SIZE: usize = 64 * 1024;
var process_stack: [STACK_SIZE]u8 align(16) = undefined;

pub fn runElf(path: []const u8) i32 {
    if (!vfs.exists(path)) {
        log.debug("exec: not found: {s}\n", .{path});
        return -1;
    }
    if (vfs.isDir(path)) {
        log.debug("exec: is directory\n", .{});
        return -2;
    }

    // Zero-copy: get slice directly into ISO module memory.
    const elf_data = vfs.read(path) orelse {
        log.debug("exec: vfs.read failed\n", .{});
        return -3;
    };

    if (!elf.validate(elf_data)) {
        log.debug("exec: not a valid ELF\n", .{});
        return -7;
    }

    const range = elf.vaddressRange(elf_data) orelse {
        log.debug("exec: no LOAD segments\n", .{});
        return -8;
    };
    const total: usize = @intCast((range.max - range.min + 0xFFF) & ~@as(u64, 0xFFF));

    const load_raw = mem.kmalloc(total + 0x1000) orelse {
        log.debug("exec: out of memory ({d} bytes)\n", .{total});
        return -9;
    };
    const aligned: usize = (@intFromPtr(load_raw) + 0xFFF) & ~@as(usize, 0xFFF);
    const load: [*]u8 = @ptrFromInt(aligned);

    @memset(load[0..total], 0);

    if (!elf.loadProgramRelative(load, range.min, elf_data)) {
        mem.kfree(load_raw);
        log.debug("exec: load failed\n", .{});
        return -10;
    }

    const entry_vaddr = elf.header(elf_data).entry;
    const entry_addr: usize = aligned + @as(usize, @intCast(entry_vaddr - range.min));

    const stack_top_addr = (@intFromPtr(&process_stack) + STACK_SIZE) & ~@as(usize, 0xF);

    log.debug("exec: entry=0x{x} sp=0x{x}\n", .{ entry_addr, stack_top_addr });

    var saved_rsp: u64 = undefined;
    asm volatile ("movq %%rsp, %[s]"
        : [s] "=r" (saved_rsp),
    );

    asm volatile (
        \\movq %[sp], %%rsp
        \\callq *%[entry]
        \\movq %[saved], %%rsp
        :
        : [sp] "r" (@as(u64, @intCast(stack_top_addr))),
          [entry] "r" (@as(u64, @intCast(entry_addr))),
          [saved] "r" (saved_rsp),
        : .{ .memory = true, .rax = true, .rcx = true, .rdx = true, .rsi = true, .rdi = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true }
    );

    log.debug("exec: returned\n", .{});
    mem.kfree(load_raw);
    return 0;
}
