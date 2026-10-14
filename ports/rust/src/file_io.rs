/*
 * file_io.rs - File loading, insertion, saving, and block export
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 7.5-7.8 and Section 13.2.
 */

use crate::buffer::*;
use crate::config::*;
use std::fs;
use std::path::Path;

pub fn file_load(filename: &str) -> i32 {
    if filename.is_empty() {
        return -1;
    }
    let data = match fs::read(Path::new(filename)) {
        Ok(d) => d,
        Err(_) => {
            buffer_reset_empty();
            let mut b = buf_state().lock().unwrap();
            b.current_filename = String::from(filename);
            b.file_format = FMT_LINUX;
            return 0;
        }
    };

    buffer_reset_empty();
    {
        let mut b = buf_state().lock().unwrap();
        b.current_filename = String::from(filename);
        b.is_loading_file = 1;
    }

    let mut parsed_lines: Vec<Vec<u8>> = Vec::new();
    let mut cur = Vec::new();
    let mut saw_crlf = false;
    let mut saw_lf = false;

    let mut i = 0usize;
    while i < data.len() {
        let ch = data[i];
        if ch == 0x1A {
            break;
        }
        if ch == b'\r' {
            if i + 1 < data.len() && data[i + 1] == b'\n' {
                saw_crlf = true;
                i += 1;
            }
            parsed_lines.push(cur);
            cur = Vec::new();
        } else if ch == b'\n' {
            saw_lf = true;
            parsed_lines.push(cur);
            cur = Vec::new();
        } else {
            if cur.len() < MAX_INPUT_LINE_CHARS {
                cur.push(ch);
            }
        }
        i += 1;
    }
    if !cur.is_empty() || parsed_lines.is_empty() {
        parsed_lines.push(cur);
    }

    {
        let mut b = buf_state().lock().unwrap();
        if parsed_lines.len() > b.max_doc_lines {
            parsed_lines.truncate(b.max_doc_lines);
        }
        b.lines = parsed_lines;
        b.file_format = if saw_crlf {
            FMT_CPM
        } else if saw_lf {
            FMT_LINUX
        } else {
            FMT_LINUX
        };
        b.is_loading_file = 0;
        b.file_modified = 0;
        b.cur_row = 0;
        b.cur_col = 0;
        b.target_vis_col = 0;
        b.view_top_row = 0;
        b.view_left_col = 0;
    }
    unpack_line(0);
    0
}

pub fn file_insert(filename: &str) -> i32 {
    if filename.is_empty() {
        return -1;
    }
    let data = match fs::read(Path::new(filename)) {
        Ok(d) => d,
        Err(_) => return -1,
    };

    let (cr, _) = get_cur_pos();
    pack_line(cr);

    let mut cur = Vec::new();
    let mut insert_idx = cr;
    let mut i = 0usize;
    while i < data.len() {
        let ch = data[i];
        if ch == 0x1A {
            break;
        }
        if ch == b'\r' {
            if i + 1 < data.len() && data[i + 1] == b'\n' {
                i += 1;
            }
            if insert_line_at(insert_idx, &cur) == 0 {
                insert_idx += 1;
            }
            cur.clear();
        } else if ch == b'\n' {
            if insert_line_at(insert_idx, &cur) == 0 {
                insert_idx += 1;
            }
            cur.clear();
        } else if cur.len() < MAX_INPUT_LINE_CHARS {
            cur.push(ch);
        }
        i += 1;
    }
    if !cur.is_empty() {
        let _ = insert_line_at(insert_idx, &cur);
    }

    buf_state().lock().unwrap().file_modified = 1;
    unpack_line(cr);
    0
}

pub fn file_save(filename: Option<&str>, format: u8) -> i32 {
    let (cr, _) = get_cur_pos();
    pack_line(cr);

    let (target, lines) = {
        let b = buf_state().lock().unwrap();
        let t = match filename {
            Some(f) if !f.is_empty() => String::from(f),
            _ => b.current_filename.clone(),
        };
        (t, b.lines.clone())
    };
    if target.is_empty() {
        return -1;
    }

    let mut out = Vec::new();
    for line in &lines {
        out.extend_from_slice(line);
        if format == FMT_CPM {
            out.extend_from_slice(b"\r\n");
        } else {
            out.push(b'\n');
        }
    }

    if fs::write(Path::new(&target), &out).is_err() {
        return -1;
    }

    let mut b = buf_state().lock().unwrap();
    if let Some(f) = filename {
        if !f.is_empty() {
            b.current_filename = String::from(f);
        }
    }
    b.file_modified = 0;
    0
}

pub fn file_save_block(
    filename: &str,
    start_row: usize,
    end_row: usize,
    format: u8,
) -> i32 {
    if filename.is_empty() {
        return -1;
    }
    let (cr, _) = get_cur_pos();
    pack_line(cr);

    let lines = buf_state().lock().unwrap().lines.clone();
    if lines.is_empty() {
        return -1;
    }
    let sr = start_row.min(lines.len() - 1);
    let er = end_row.min(lines.len() - 1);
    if sr > er {
        return -1;
    }

    let mut out = Vec::new();
    for line in &lines[sr..=er] {
        out.extend_from_slice(line);
        if format == FMT_CPM {
            out.extend_from_slice(b"\r\n");
        } else {
            out.push(b'\n');
        }
    }

    if fs::write(Path::new(filename), &out).is_ok() {
        0
    } else {
        -1
    }
}
