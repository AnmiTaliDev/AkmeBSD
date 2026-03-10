const std = @import("std");
const limine = @import("limine.zig");
const serial = @import("drivers/serial.zig");
const render = @import("kernel/vge/render.zig");
const fb = @import("kernel/vge/fb.zig");
const mem = @import("kernel/mem/allocator.zig");
const vfs = @import("fs/vfs.zig");
const iso = @import("fs/iso9660.zig");
const cdrom = @import("drivers/cdrom.zig");
const keyboard = @import("drivers/keyboard.zig");
const log = @import("kernel/log.zig");
const exec = @import("kernel/exec.zig");
const panic_mod = @import("arch/panic.zig");

export var module_request: limine.ModuleRequest = .{};

export fn _start() noreturn {
    kmain();
}

fn enableSse() void {
    asm volatile (
        \\mov %%cr0, %%rax
        \\and $0xFFFB, %%ax
        \\or $0x2, %%ax
        \\mov %%rax, %%cr0
        \\mov %%cr4, %%rax
        \\or $0x600, %%rax
        \\mov %%rax, %%cr4
        ::: .{ .rax = true, .memory = true }
    );
}

export fn kmain() noreturn {
    enableSse();
    _ = serial.init();
    serial.print(":: Akme kernel starting\n");

    vfs.init();
    mem.init();

    {
        var buf: [32]u8 = undefined;
        const s = mem.formatSize(mem.getTotal(), &buf);
        serial.print(":: Memory initialized (");
        serial.print(s);
        serial.print(")\n");
    }

    log.init();
    keyboard.init();
    _ = cdrom.init();

    if (module_request.response) |resp| {
        log.debug("Limine modules: {d}\n", .{resp.module_count});
        for (0..resp.module_count) |i| {
            const mod = resp.modules.?[i] orelse continue;
            log.debug("Module {d}: size={d}\n", .{ i, mod.size });
            if (mod.size > 0x8005) {
                const addr: [*]const u8 = @ptrCast(mod.address orelse continue);
                if (addr[0x8001] == 'C' and addr[0x8002] == 'D' and addr[0x8003] == '0' and
                    addr[0x8004] == '0' and addr[0x8005] == '1')
                {
                    const data = addr[0..mod.size];
                    cdrom.setIsoData(data);
                    iso.init(data);
                    log.debug("ISO9660 found in module {d}\n", .{i});
                }
            }
        }
    }

    if (iso.isReady()) {
        iso.mountToVfs("/");
        log.debug("ISO mounted to /\n", .{});
        fb.initFont();
        render.init();
        render.clear();
    } else {
        log.debug("ISO9660 not found\n", .{});
        render.init();
    }

    render.print(":: Base kernel initialization complete\n", 7);

    const result = exec.runElf("/bin/test");
    if (result == 0) {
        log.info("Program started successfully\n", .{});
    } else {
        log.err("Failed to start program: {d}\n", .{result});
    }

    render.print(":: Kernel halted\n", 7);
    while (true) asm volatile ("hlt");
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    panic_mod.panic(msg);
}
