const FONT_HEIGHT: usize = 16;

const Psf1Header = extern struct {
    magic: u16,
    mode: u8,
    charsize: u8,
};

const Psf2Header = extern struct {
    magic: u32,
    version: u32,
    headersize: u32,
    flags: u32,
    length: u32,
    charsize: u32,
    height: u32,
    width: u32,
};

const PSF1_MAGIC: u16 = 0x0436;
const PSF2_MAGIC: u32 = 0x864ab572;
const PSF1_MODE512: u8 = 0x01;

pub fn parse(data: []const u8, font: *[256][FONT_HEIGHT]u8) bool {
    if (data.len < 4) return false;

    if (data.len >= @sizeOf(Psf2Header)) {
        const h: *align(1) const Psf2Header = @ptrCast(data.ptr);
        if (h.magic == PSF2_MAGIC and h.headersize >= @sizeOf(Psf2Header)) {
            if (h.width != 8 or h.height < 8 or h.length < 256) return false;
            const expected = @as(usize, h.headersize) + @as(usize, h.length) * @as(usize, h.charsize);
            if (expected > data.len) return false;
            const glyphs = data[@as(usize, h.headersize)..];
            const copy_h = @min(h.height, FONT_HEIGHT);
            const bpr = (@as(usize, h.width) + 7) / 8;
            for (font) |*g| @memset(g, 0);
            for (0..@min(h.length, 256)) |i| {
                const glyph = glyphs[i * h.charsize ..];
                for (0..copy_h) |row| {
                    if (row * bpr < h.charsize) font[i][row] = glyph[row * bpr];
                }
            }
            return true;
        }
    }

    if (data.len >= @sizeOf(Psf1Header)) {
        const h: *align(1) const Psf1Header = @ptrCast(data.ptr);
        if (h.magic == PSF1_MAGIC) {
            const glyph_count: usize = if (h.mode & PSF1_MODE512 != 0) 512 else 256;
            const bitmap_sz = glyph_count * @as(usize, h.charsize);
            if (@sizeOf(Psf1Header) + bitmap_sz > data.len) return false;
            if (h.charsize < 8 or glyph_count < 256) return false;
            const bitmap = data[@sizeOf(Psf1Header)..];
            const copy_h = @min(@as(usize, h.charsize), FONT_HEIGHT);
            for (font) |*g| @memset(g, 0);
            for (0..256) |i| {
                for (0..copy_h) |row| {
                    font[i][row] = bitmap[i * h.charsize + row];
                }
            }
            return true;
        }
    }

    return false;
}
