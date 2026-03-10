const io = @import("../arch/io.zig");

const DATA_PORT: u16 = 0x60;
const STATUS_PORT: u16 = 0x64;
const BUFFER_SIZE: usize = 256;

const scancode_ascii = [57]u8{
    0,   27,  '1', '2', '3',  '4', '5', '6', '7', '8',
    '9', '0', '-', '=', '\x08', '\t', 'q', 'w', 'e', 'r',
    't', 'y', 'u', 'i', 'o',  'p', '[', ']', '\n', 0,
    'a', 's', 'd', 'f', 'g',  'h', 'j', 'k', 'l', ';',
    '\'', '`', 0, '\\', 'z', 'x', 'c', 'v', 'b', 'n',
    'm', ',', '.', '/',  0,   '*', 0,
};

const scancode_shifted = [57]u8{
    0,   27,  '!', '@', '#',  '$', '%', '^', '&', '*',
    '(', ')', '_', '+', '\x08', '\t', 'Q', 'W', 'E', 'R',
    'T', 'Y', 'U', 'I', 'O',  'P', '{', '}', '\n', 0,
    'A', 'S', 'D', 'F', 'G',  'H', 'J', 'K', 'L', ':',
    '"', '~', 0, '|', 'Z', 'X', 'C', 'V', 'B', 'N',
    'M', '<', '>', '?',  0,   '*', 0,
};

var buf: [BUFFER_SIZE]u8 = undefined;
var read_pos: usize = 0;
var write_pos: usize = 0;
var shift: bool = false;
var caps: bool = false;
var ctrl: bool = false;

pub fn init() void {
    read_pos = 0;
    write_pos = 0;
    shift = false;
    caps = false;
    ctrl = false;
}

fn bufPush(c: u8) void {
    const next = (write_pos + 1) % BUFFER_SIZE;
    if (next != read_pos) {
        buf[write_pos] = c;
        write_pos = next;
    }
}

fn bufPop() u8 {
    if (read_pos == write_pos) return 0;
    const c = buf[read_pos];
    read_pos = (read_pos + 1) % BUFFER_SIZE;
    return c;
}

pub fn poll() void {
    if (io.inb(STATUS_PORT) & 0x01 == 0) return;
    const sc = io.inb(DATA_PORT);
    const released = sc & 0x80 != 0;
    const code: u8 = sc & 0x7F;

    if (released) {
        if (code == 0x2A or code == 0x36) shift = false;
        if (code == 0x1D) ctrl = false;
        return;
    }

    if (code == 0x2A or code == 0x36) { shift = true; return; }
    if (code == 0x1D) { ctrl = true; return; }
    if (code == 0x3A) { caps = !caps; return; }

    if (code >= scancode_ascii.len) return;
    var ch = if (shift) scancode_shifted[code] else scancode_ascii[code];
    if (ch == 0) return;

    if (!shift and caps and ch >= 'a' and ch <= 'z') ch -= 32;
    if (ctrl and ch >= 'a' and ch <= 'z') ch = ch - 'a' + 1;
    if (ctrl and ch >= 'A' and ch <= 'Z') ch = ch - 'A' + 1;

    bufPush(ch);
}

pub fn hasChar() bool {
    poll();
    return read_pos != write_pos;
}

pub fn getChar() u8 {
    while (!hasChar()) {}
    return bufPop();
}

pub fn getLine(out: []u8) []u8 {
    var pos: usize = 0;
    while (pos < out.len - 1) {
        const c = getChar();
        if (c == '\n') break;
        if (c == '\x08' and pos > 0) {
            pos -= 1;
            continue;
        }
        if (c >= 32 and c <= 126) {
            out[pos] = c;
            pos += 1;
        }
    }
    out[pos] = 0;
    return out[0..pos];
}
