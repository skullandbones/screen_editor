/*
 * hal_linux.rs - Linux Hardware Abstraction Layer (Console, Keyboard, Storage)
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Uses zero external crates via inline libc FFI declarations.
 */

use crate::config::*;
use std::fs;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

pub const ATTR_NORMAL: u8 = 0;
pub const ATTR_INVERSE: u8 = 1;
pub const ATTR_DIM: u8 = 2;
pub const ATTR_BOLD: u8 = 3;

const STDIN_FILENO: i32 = 0;
const STDOUT_FILENO: i32 = 1;
const TCSAFLUSH: i32 = 2;
const TIOCGWINSZ: u64 = 0x5413;
const POLLIN: i16 = 0x0001;
const SIGWINCH: i32 = 28;

const BRKINT: u32 = 0o000002;
const ICRNL: u32 = 0o000400;
const INPCK: u32 = 0o000020;
const ISTRIP: u32 = 0o000040;
const IXON: u32 = 0o002000;
const OPOST: u32 = 0o000001;
const CS8: u32 = 0o000060;
const ECHO: u32 = 0o000010;
const ICANON: u32 = 0o000002;
const IEXTEN: u32 = 0o100000;
const ISIG: u32 = 0o000001;
const VTIME: usize = 5;
const VMIN: usize = 6;

#[repr(C)]
#[derive(Clone, Copy)]
struct Termios {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [u8; 32],
    c_ispeed: u32,
    c_ospeed: u32,
}

#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn tcgetattr(fd: i32, termios_p: *mut Termios) -> i32;
    fn tcsetattr(
        fd: i32,
        optional_actions: i32,
        termios_p: *const Termios,
    ) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn poll(fds: *mut PollFd, nfds: u64, timeout: i32) -> i32;
    fn read(fd: i32, buf: *mut std::ffi::c_void, count: usize) -> isize;
    fn write(fd: i32, buf: *const std::ffi::c_void, count: usize) -> isize;
    fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    fn atexit(func: extern "C" fn()) -> i32;
}

struct ConsoleState {
    orig_termios: Termios,
    raw_mode_active: bool,
    out_buf: Vec<u8>,
}

static CONSOLE_STATE: OnceLock<Mutex<ConsoleState>> = OnceLock::new();

fn console_state() -> &'static Mutex<ConsoleState> {
    CONSOLE_STATE.get_or_init(|| {
        Mutex::new(ConsoleState {
            orig_termios: Termios {
                c_iflag: 0,
                c_oflag: 0,
                c_cflag: 0,
                c_lflag: 0,
                c_line: 0,
                c_cc: [0; 32],
                c_ispeed: 0,
                c_ospeed: 0,
            },
            raw_mode_active: false,
            out_buf: Vec::with_capacity(16384),
        })
    })
}

extern "C" fn on_sigwinch(_sig: i32) {
    crate::ui_render::set_resize_pending(true);
}

extern "C" fn atexit_cleanup() {
    hal_console_cleanup();
}

pub fn hal_console_flush() {
    let mut st = console_state().lock().unwrap();
    if !st.out_buf.is_empty() {
        unsafe {
            let _ = write(
                STDOUT_FILENO,
                st.out_buf.as_ptr() as *const std::ffi::c_void,
                st.out_buf.len(),
            );
        }
        st.out_buf.clear();
    }
}

fn buf_write(data: &[u8]) {
    let mut need_flush = false;
    {
        let mut st = console_state().lock().unwrap();
        if st.out_buf.len() + data.len() > 16384 {
            need_flush = true;
        } else {
            st.out_buf.extend_from_slice(data);
        }
    }
    if need_flush {
        hal_console_flush();
        let mut st = console_state().lock().unwrap();
        st.out_buf.extend_from_slice(data);
    }
}

pub fn hal_console_init() {
    {
        let mut st = console_state().lock().unwrap();
        unsafe {
            if tcgetattr(STDIN_FILENO, &mut st.orig_termios) == 0 {
                let mut raw = st.orig_termios;
                raw.c_iflag &= !(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
                raw.c_oflag &= !OPOST;
                raw.c_cflag |= CS8;
                raw.c_lflag &= !(ECHO | ICANON | IEXTEN | ISIG);
                raw.c_cc[VMIN] = 0;
                raw.c_cc[VTIME] = 1;
                let _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
                st.raw_mode_active = true;
            }
            let _ = atexit(atexit_cleanup);
            let _ = signal(SIGWINCH, on_sigwinch);
        }
    }
    buf_write(b"\x1b[0m\x1b[?25h\x1b[2J\x1b[H");
    hal_console_flush();
}

pub fn hal_console_cleanup() {
    let mut was_active = false;
    let orig;
    {
        let mut st = console_state().lock().unwrap();
        orig = st.orig_termios;
        if st.raw_mode_active {
            was_active = true;
            st.raw_mode_active = false;
        }
    }
    if was_active {
        buf_write(
            b"\x1b[0m\x1b[?25h\x1b[2J\x1b[H\
              Exiting SE. Returned to OS prompt.\r\n",
        );
        hal_console_flush();
        unsafe {
            let _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig);
        }
    }
}

pub fn hal_console_putc(c: u8) {
    buf_write(&[c]);
}

pub fn hal_console_puts(s: &str) {
    buf_write(s.as_bytes());
}

pub fn hal_console_clear() {
    buf_write(b"\x1b[2J\x1b[H");
}

pub fn hal_console_clear_eol() {
    buf_write(b"\x1b[K");
}

pub fn hal_console_locate(row: u8, col: u8) {
    let seq = format!("\x1b[{};{}H", row, col);
    buf_write(seq.as_bytes());
}

pub fn hal_console_set_attr(attr: u8) {
    match attr {
        ATTR_INVERSE => buf_write(b"\x1b[7m"),
        ATTR_DIM => buf_write(b"\x1b[2m"),
        ATTR_BOLD => buf_write(b"\x1b[1m"),
        _ => buf_write(b"\x1b[0m"),
    }
}

pub fn hal_console_set_cursor_vis(visible: u8) {
    if visible != 0 {
        buf_write(b"\x1b[?25h");
    } else {
        buf_write(b"\x1b[?25l");
    }
}

pub fn hal_console_get_native_size() -> (u8, u8) {
    let mut ws = Winsize {
        ws_row: 0,
        ws_col: 0,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let mut r = ROWS_24;
    let mut c = COLS_80;
    unsafe {
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &mut ws) == 0 && ws.ws_col >= 40 {
            c = if ws.ws_col > 240 {
                240
            } else {
                ws.ws_col as u8
            };
            r = if ws.ws_row > 100 {
                100
            } else if ws.ws_row < 10 {
                ROWS_24
            } else {
                ws.ws_row as u8
            };
        }
    }
    (r, c)
}

pub fn hal_console_get_size() -> (u8, u8) {
    let cfg = get_config();
    if cfg.screen_mode == MODE_80X24 {
        (ROWS_24, COLS_80)
    } else if cfg.screen_mode == MODE_120X40 {
        (ROWS_40, COLS_120)
    } else {
        hal_console_get_native_size()
    }
}

/* Keyboard State & Atomic Escape Sequence Parser */

struct KeyBuffer {
    buf: [u8; 256],
    head: usize,
    tail: usize,
}

static KEY_BUF: OnceLock<Mutex<KeyBuffer>> = OnceLock::new();

fn key_buf() -> &'static Mutex<KeyBuffer> {
    KEY_BUF.get_or_init(|| {
        Mutex::new(KeyBuffer {
            buf: [0; 256],
            head: 0,
            tail: 0,
        })
    })
}

fn fill_raw_buf(timeout_ms: i32) -> i32 {
    {
        let kb = key_buf().lock().unwrap();
        if kb.head < kb.tail {
            return (kb.tail - kb.head) as i32;
        }
    }
    let mut pfd = PollFd {
        fd: STDIN_FILENO,
        events: POLLIN,
        revents: 0,
    };
    let ret = unsafe { poll(&mut pfd, 1, timeout_ms) };
    if ret <= 0 || (pfd.revents & POLLIN) == 0 {
        return 0;
    }
    let mut temp = [0u8; 256];
    let n = unsafe {
        read(
            STDIN_FILENO,
            temp.as_mut_ptr() as *mut std::ffi::c_void,
            temp.len(),
        )
    };
    if n <= 0 {
        return 0;
    }
    let count = n as usize;
    let mut kb = key_buf().lock().unwrap();
    kb.buf[..count].copy_from_slice(&temp[..count]);
    kb.head = 0;
    kb.tail = count;
    count as i32
}

fn get_raw_byte(timeout_ms: i32) -> i32 {
    {
        let mut kb = key_buf().lock().unwrap();
        if kb.head < kb.tail {
            let b = kb.buf[kb.head];
            kb.head += 1;
            return b as i32;
        }
    }
    if fill_raw_buf(timeout_ms) > 0 {
        let mut kb = key_buf().lock().unwrap();
        if kb.head < kb.tail {
            let b = kb.buf[kb.head];
            kb.head += 1;
            return b as i32;
        }
    }
    -1
}

fn unget_raw_byte(b: i32) {
    if b < 0 {
        return;
    }
    let mut kb = key_buf().lock().unwrap();
    if kb.head > 0 {
        kb.head -= 1;
        let h = kb.head;
        kb.buf[h] = b as u8;
    } else if kb.tail < kb.buf.len() {
        let t = kb.tail;
        kb.buf.copy_within(0..t, 1);
        kb.buf[0] = b as u8;
        kb.tail = t + 1;
    }
}

fn drain_csi_sequence() {
    for _ in 0..32 {
        let b = get_raw_byte(25);
        if b < 0 {
            break;
        }
        if b == 0x1B {
            unget_raw_byte(b);
            break;
        }
        if (0x40..=0x7E).contains(&b) {
            break;
        }
    }
}

pub fn hal_keyboard_get_key() -> u8 {
    hal_console_flush();
    let b0 = get_raw_byte(50);
    if b0 < 0 {
        return 0;
    }
    let c = b0 as u8;
    if c == KEY_BS_ALT {
        return KEY_BS;
    }
    if c == b'\n' {
        return KEY_ENTER;
    }
    if c != KEY_ESC {
        return c;
    }

    let b1 = get_raw_byte(25);
    if b1 < 0 {
        return KEY_ESC;
    }

    if b1 == b'[' as i32 {
        let b2 = get_raw_byte(25);
        if b2 < 0 {
            return 0;
        }
        match b2 as u8 {
            b'A' => return KEY_UP,
            b'B' => return KEY_DOWN,
            b'C' => return KEY_RIGHT,
            b'D' => return KEY_LEFT,
            b'H' => return KEY_HOME,
            b'F' => return KEY_END,
            b'1'..=b'9' => {
                let b3 = get_raw_byte(25);
                if b3 == b'~' as i32 {
                    match b2 as u8 {
                        b'1' | b'7' => return KEY_HOME,
                        b'2' => return KEY_INS,
                        b'3' => return KEY_DEL,
                        b'4' | b'8' => return KEY_END,
                        b'5' => return KEY_PGUP,
                        b'6' => return KEY_PGDN,
                        _ => return 0,
                    }
                } else if b3 >= 0 && !(0x40..=0x7E).contains(&b3) {
                    drain_csi_sequence();
                }
                return 0;
            }
            b'0'..=b'?' => {
                drain_csi_sequence();
                return 0;
            }
            _ => {
                if !(0x40..=0x7E).contains(&b2) {
                    drain_csi_sequence();
                }
                return 0;
            }
        }
    } else if b1 == b'O' as i32 {
        let b2 = get_raw_byte(25);
        if b2 < 0 {
            return 0;
        }
        match b2 as u8 {
            b'H' => return KEY_HOME,
            b'F' => return KEY_END,
            b'A' => return KEY_UP,
            b'B' => return KEY_DOWN,
            b'C' => return KEY_RIGHT,
            b'D' => return KEY_LEFT,
            _ => return 0,
        }
    }

    unget_raw_byte(b1);
    KEY_ESC
}

/* Storage Operations */

pub fn hal_storage_get_free_kb() -> u16 {
    32
}

pub fn hal_storage_file_exists(filename: &str) -> u8 {
    if filename.is_empty() {
        return 0;
    }
    if Path::new(filename).exists() {
        1
    } else {
        0
    }
}

pub fn hal_storage_list_dir(path: &str, max_entries: usize) -> Vec<String> {
    let dir_path = if path.is_empty() { "." } else { path };
    let entries = match fs::read_dir(dir_path) {
        Ok(e) => e,
        Err(_) => return Vec::new(),
    };

    let mut dirs = Vec::new();
    let mut files = Vec::new();

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let full_path = entry.path();
        if full_path.is_dir() {
            dirs.push(name);
        } else if full_path.is_file() {
            files.push(name);
        }
    }

    let cmp_ci = |a: &String, b: &String| {
        a.to_ascii_lowercase().cmp(&b.to_ascii_lowercase())
    };
    dirs.sort_by(cmp_ci);
    files.sort_by(cmp_ci);

    let mut out = Vec::new();
    for d in dirs {
        if out.len() >= max_entries {
            break;
        }
        out.push(d);
    }
    for f in files {
        if out.len() >= max_entries {
            break;
        }
        out.push(f);
    }
    out
}
