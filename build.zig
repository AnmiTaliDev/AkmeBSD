const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .kernel,
        .red_zone = false,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.bin",
        .root_module = kernel_mod,
        .use_lld = true,
        .use_llvm = true,
    });
    kernel.setLinkerScript(b.path("link.ld"));
    kernel.entry = .{ .symbol_name = "_start" };

    const kernel_install = b.addInstallArtifact(kernel, .{
        .dest_dir = .{ .override = .{ .custom = "boot" } },
    });

    const user_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test/main.zig"),
        .target = user_target,
        .optimize = optimize,
    });

    const test_elf = b.addExecutable(.{
        .name = "test",
        .root_module = test_mod,
        .use_lld = true,
        .use_llvm = true,
    });
    test_elf.setLinkerScript(b.path("user.ld"));
    test_elf.entry = .{ .symbol_name = "_start" };

    const test_install = b.addInstallArtifact(test_elf, .{
        .dest_dir = .{ .override = .{ .custom = "." } },
    });

    const copy_limine = b.addSystemCommand(&.{
        "sh", "-c",
        "cp -r limine/* zig-out/boot/ 2>/dev/null || true",
    });
    copy_limine.step.dependOn(&kernel_install.step);

    const copy_test = b.addSystemCommand(&.{
        "sh", "-c",
        "mkdir -p rootfs/bin && cp zig-out/test rootfs/bin/test",
    });
    copy_test.step.dependOn(&test_install.step);

    const make_rootfs_img = b.addSystemCommand(&.{
        "xorriso", "-as", "mkisofs",
        "-quiet", "-iso-level", "3",
        "-o", "zig-out/boot/rootfs.img",
        "rootfs/",
    });
    make_rootfs_img.step.dependOn(&copy_limine.step);
    make_rootfs_img.step.dependOn(&copy_test.step);

    const iso_name = "dist/akme-amd64.iso";

    const mkdir_dist = b.addSystemCommand(&.{ "mkdir", "-p", "dist" });

    const make_iso = b.addSystemCommand(&.{
        "xorriso", "-as", "mkisofs",
        "-b",              "limine-bios-cd.bin",
        "-no-emul-boot",
        "-boot-load-size", "4",
        "-boot-info-table",
        "--protective-msdos-label",
        "-iso-level",      "3",
        "-partition_offset", "64",
        "-quiet",
        "-o",              iso_name,
        "zig-out/boot/",
    });
    make_iso.step.dependOn(&mkdir_dist.step);
    make_iso.step.dependOn(&make_rootfs_img.step);

    const limine_install = b.addSystemCommand(&.{
        "limine", "bios-install", iso_name,
    });
    limine_install.step.dependOn(&make_iso.step);

    const iso_step = b.step("iso", "Build bootable ISO");
    iso_step.dependOn(&limine_install.step);

    b.default_step = iso_step;

    const run = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-m",      "1024M",
        "-serial", "file:qemu.log",
        "-cdrom",  iso_name,
        "-cpu",    "core2duo",
    });
    run.step.dependOn(&limine_install.step);

    const run_step = b.step("run", "Run in QEMU");
    run_step.dependOn(&run.step);
}
