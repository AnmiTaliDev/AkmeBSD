const vfs = @import("../../fs/vfs.zig");
const psf = @import("psf.zig");
const render = @import("render.zig");

const FONT_HEIGHT: usize = 16;
const FONT_PATH = "/usr/share/fonts/general.psf";

var system_font: [256][FONT_HEIGHT]u8 = [_][FONT_HEIGHT]u8{[_]u8{0} ** FONT_HEIGHT} ** 256;
var font_height: u32 = 16;
var font_loaded: bool = false;

pub fn initFont() void {
    if (vfs.exists(FONT_PATH)) {
        if (vfs.read(FONT_PATH)) |data| {
            if (psf.parse(data, &system_font)) {
                font_height = FONT_HEIGHT;
                font_loaded = true;
                return;
            }
        }
    }
    const builtin = render.getBuiltinFont();
    font_height = 8;
    for (0..128) |i| {
        for (0..8) |row| {
            system_font[i][row] = builtin[i][row];
        }
    }
    font_loaded = true;
}

pub fn glyphFor(c: u8) []const u8 {
    return &system_font[c];
}

pub fn fontHeight() u32 {
    return font_height;
}
