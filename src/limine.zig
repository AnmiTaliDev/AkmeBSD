const common_magic_0: u64 = 0xc7b1dd30df4c8b88;
const common_magic_1: u64 = 0x0a82e883a194f07b;

pub const Uuid = extern struct {
    a: u32,
    b: u16,
    c: u16,
    d: [8]u8,
};

pub const File = extern struct {
    revision: u64,
    address: ?*anyopaque,
    size: u64,
    path: ?[*:0]u8,
    string: ?[*:0]u8,
    media_type: u32,
    unused: u32,
    tftp_ip: u32,
    tftp_port: u32,
    partition_index: u32,
    mbr_disk_id: u32,
    gpt_disk_uuid: Uuid,
    gpt_part_uuid: Uuid,
    part_uuid: Uuid,
};

pub const MemmapEntry = extern struct {
    base: u64,
    length: u64,
    type: u64,

    pub const usable: u64 = 0;
    pub const reserved: u64 = 1;
    pub const acpi_reclaimable: u64 = 2;
    pub const acpi_nvs: u64 = 3;
    pub const bad_memory: u64 = 4;
    pub const bootloader_reclaimable: u64 = 5;
    pub const executable_and_modules: u64 = 6;
    pub const framebuffer: u64 = 7;
};

pub const MemmapResponse = extern struct {
    revision: u64,
    entry_count: u64,
    entries: ?[*]?*MemmapEntry,
};

pub const MemmapRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x67cf3d9d378a806f, 0xe304acdfc50c3c62,
    },
    revision: u64 = 0,
    response: ?*MemmapResponse = null,
};

pub const HhdmResponse = extern struct {
    revision: u64,
    offset: u64,
};

pub const HhdmRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x48dcf1cb8ad2b852, 0x63984e959a98244b,
    },
    revision: u64 = 0,
    response: ?*HhdmResponse = null,
};

pub const VideoMode = extern struct {
    pitch: u64,
    width: u64,
    height: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
};

pub const Framebuffer = extern struct {
    address: ?*anyopaque,
    width: u64,
    height: u64,
    pitch: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
    unused: [7]u8,
    edid_size: u64,
    edid: ?*anyopaque,
    mode_count: u64,
    modes: ?[*]?*VideoMode,
};

pub const FramebufferResponse = extern struct {
    revision: u64,
    framebuffer_count: u64,
    framebuffers: ?[*]?*Framebuffer,
};

pub const FramebufferRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x9d5827dcd881dd75, 0xa3148604f6fab11b,
    },
    revision: u64 = 0,
    response: ?*FramebufferResponse = null,
};

pub const ModuleResponse = extern struct {
    revision: u64,
    module_count: u64,
    modules: ?[*]?*File,
};

pub const ModuleRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x3e7e279702be32af, 0xca1c4f3bd1280cee,
    },
    revision: u64 = 0,
    response: ?*ModuleResponse = null,
    internal_module_count: u64 = 0,
    internal_modules: ?[*]?*anyopaque = null,
};

pub const RsdpResponse = extern struct {
    revision: u64,
    address: ?*anyopaque,
};

pub const RsdpRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0xc5e77b6b397e7b43, 0x27637845accdcf3c,
    },
    revision: u64 = 0,
    response: ?*RsdpResponse = null,
};

pub const BootloaderInfoResponse = extern struct {
    revision: u64,
    name: ?[*:0]u8,
    version: ?[*:0]u8,
};

pub const BootloaderInfoRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0xf55038d8e2a1202f, 0x279426fcf5f59740,
    },
    revision: u64 = 0,
    response: ?*BootloaderInfoResponse = null,
};

pub const ExecutableAddressResponse = extern struct {
    revision: u64,
    physical_base: u64,
    virtual_base: u64,
};

pub const ExecutableAddressRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x71ba76863cc55f63, 0xb2644a48c516a487,
    },
    revision: u64 = 0,
    response: ?*ExecutableAddressResponse = null,
};

pub const MpInfo = extern struct {
    processor_id: u32,
    lapic_id: u32,
    reserved: u64,
    goto_address: ?*const fn (?*MpInfo) callconv(.x86_64_sysv) void,
    extra_argument: u64,
};

pub const MpResponse = extern struct {
    revision: u64,
    flags: u32,
    bsp_lapic_id: u32,
    cpu_count: u64,
    cpus: ?[*]?*MpInfo,
};

pub const MpRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x95a67b819a1b857e, 0xa0b61b723b6a73e0,
    },
    revision: u64 = 0,
    response: ?*MpResponse = null,
    flags: u64 = 0,
};

pub const PagingModeResponse = extern struct {
    revision: u64,
    mode: u64,
};

pub const PagingModeRequest = extern struct {
    id: [4]u64 = .{
        common_magic_0, common_magic_1,
        0x95c1a0edab0944cb, 0xa4e5cb3842f7488a,
    },
    revision: u64 = 0,
    response: ?*PagingModeResponse = null,
    mode: u64 = 0,
    max_mode: u64 = 0,
    min_mode: u64 = 0,
};
