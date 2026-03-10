pub const CpuidResult = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

pub fn cpuid(leaf: u32, subleaf: u32) CpuidResult {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

pub fn vendorString(buf: *[12]u8) void {
    const r = cpuid(0, 0);
    const ebx_bytes = @as([4]u8, @bitCast(r.ebx));
    const edx_bytes = @as([4]u8, @bitCast(r.edx));
    const ecx_bytes = @as([4]u8, @bitCast(r.ecx));
    @memcpy(buf[0..4], &ebx_bytes);
    @memcpy(buf[4..8], &edx_bytes);
    @memcpy(buf[8..12], &ecx_bytes);
}

pub fn hasFeature(ecx_bit: u5) bool {
    const r = cpuid(1, 0);
    return (r.ecx >> ecx_bit) & 1 == 1;
}
