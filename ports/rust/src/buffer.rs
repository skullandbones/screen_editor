/*
 * buffer.rs - Document line buffer and active line workspace
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Supports up to 32,768 lines and 1,000 characters per line.
 */

use crate::config::*;
use std::sync::{Mutex, OnceLock};

pub const MAX_DOC_LINES_DEFAULT: usize = 32768;

pub struct BufferState {
    pub lines: Vec<Vec<u8>>,
    pub max_doc_lines: usize,
    pub view_top_row: usize,
    pub view_left_col: usize,
    pub cur_row: usize,
    pub cur_col: usize,
    pub target_vis_col: usize,
    pub insert_mode: u8,
    pub file_modified: u8,
    pub active_line_buf: Vec<u8>,
    pub active_line_dirty: u8,
    pub current_filename: String,
    pub file_format: u8,
    pub is_loading_file: u8,
}

static BUFFER_STATE: OnceLock<Mutex<BufferState>> = OnceLock::new();

pub fn buf_state() -> &'static Mutex<BufferState> {
    BUFFER_STATE.get_or_init(|| {
        Mutex::new(BufferState {
            lines: vec![Vec::new()],
            max_doc_lines: MAX_DOC_LINES_DEFAULT,
            view_top_row: 0,
            view_left_col: 0,
            cur_row: 0,
            cur_col: 0,
            target_vis_col: 0,
            insert_mode: 1,
            file_modified: 0,
            active_line_buf: Vec::new(),
            active_line_dirty: 0,
            current_filename: String::new(),
            file_format: FMT_LINUX,
            is_loading_file: 0,
        })
    })
}

pub fn buffer_init() -> i32 {
    buffer_reset_empty();
    0
}

pub fn buffer_reset_empty() {
    let mut b = buf_state().lock().unwrap();
    b.lines.clear();
    b.lines.push(Vec::new());
    b.view_top_row = 0;
    b.view_left_col = 0;
    b.cur_row = 0;
    b.cur_col = 0;
    b.target_vis_col = 0;
    b.insert_mode = 1;
    b.file_modified = 0;
    b.active_line_buf.clear();
    b.active_line_dirty = 0;
    b.current_filename.clear();
    b.file_format = FMT_LINUX;
    b.is_loading_file = 0;
}

pub fn unpack_line(row: usize) {
    let mut b = buf_state().lock().unwrap();
    if row >= b.lines.len() {
        b.active_line_buf.clear();
        b.active_line_dirty = 0;
        return;
    }
    let mut line = b.lines[row].clone();
    if line.len() > MAX_LINE_CHARS {
        line.truncate(MAX_LINE_CHARS);
    }
    b.active_line_buf = line;
    b.active_line_dirty = 0;
}

pub fn pack_line(row: usize) {
    let mut b = buf_state().lock().unwrap();
    if b.active_line_dirty == 0 || row >= b.lines.len() {
        return;
    }
    let mut line = b.active_line_buf.clone();
    if line.len() > MAX_LINE_CHARS {
        line.truncate(MAX_LINE_CHARS);
    }
    b.lines[row] = line;
    b.active_line_dirty = 0;
}

pub fn insert_line_at(row: usize, text: &[u8]) -> i32 {
    let mut b = buf_state().lock().unwrap();
    if b.lines.len() >= b.max_doc_lines || row > b.lines.len() {
        return -1;
    }
    let copy_len = text.len().min(MAX_LINE_CHARS);
    b.lines.insert(row, text[..copy_len].to_vec());
    0
}

pub fn delete_line_at(row: usize) -> i32 {
    let mut b = buf_state().lock().unwrap();
    if b.lines.len() <= 1 || row >= b.lines.len() {
        return -1;
    }
    b.lines.remove(row);
    0
}

pub fn get_line_len(row: usize) -> usize {
    let b = buf_state().lock().unwrap();
    if row >= b.lines.len() {
        return 0;
    }
    if row == b.cur_row {
        return b.active_line_buf.len();
    }
    b.lines[row].len()
}

pub fn get_line_bytes(row: usize) -> Vec<u8> {
    let b = buf_state().lock().unwrap();
    if row >= b.lines.len() {
        return Vec::new();
    }
    if row == b.cur_row {
        return b.active_line_buf.clone();
    }
    b.lines[row].clone()
}

pub fn set_line_bytes(row: usize, data: &[u8]) {
    let mut b = buf_state().lock().unwrap();
    if row >= b.lines.len() {
        return;
    }
    let copy_len = data.len().min(MAX_LINE_CHARS);
    b.lines[row] = data[..copy_len].to_vec();
    if row == b.cur_row {
        b.active_line_buf = b.lines[row].clone();
        b.active_line_dirty = 0;
    }
}

pub fn get_total_lines() -> usize {
    buf_state().lock().unwrap().lines.len()
}

pub fn get_cur_pos() -> (usize, usize) {
    let b = buf_state().lock().unwrap();
    (b.cur_row, b.cur_col)
}
