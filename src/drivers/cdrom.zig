var iso_data: ?[]const u8 = null;

pub fn init() bool {
    return true;
}

pub fn setIsoData(data: []const u8) void {
    iso_data = data;
}

pub fn getData() ?[]const u8 {
    return iso_data;
}

pub fn readSectors(lba: u32, count: u32) ?[]const u8 {
    const data = iso_data orelse return null;
    const offset = @as(usize, lba) * 2048;
    const size = @as(usize, count) * 2048;
    if (offset >= data.len) return null;
    return data[offset..@min(offset + size, data.len)];
}
