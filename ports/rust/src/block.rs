/*
 * block.rs - Text block selection, direct manipulation, and Block Operations
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 9 and golden SE.COM.
 */

use crate::buffer::*;
use crate::config::*;
use crate::editor::*;
use crate::file_io::*;
use crate::hal_linux::*;
use crate::ui_browser::*;
use crate::ui_modal::*;
use crate::ui_render::*;
use std::sync::{Mutex, OnceLock};

pub const BLOCK_MODE_OFF: u8 = 0;
pub const BLOCK_MODE_SELECTING: u8 = 1;
pub const BLOCK_MODE_SOLIDIFIED: u8 = 2;

#[derive(Clone, Copy, Default)]
pub struct BlockState {
    pub block_mode: u8,
    pub start_row: usize,
    pub start_col: usize,
    pub end_row: usize,
    pub end_col: usize,
    pub norm_start_row: usize,
    pub norm_start_col: usize,
    pub norm_end_row: usize,
    pub norm_end_col: usize,
}

static BLOCK_STATE: OnceLock<Mutex<BlockState>> = OnceLock::new();

pub fn blk_state() -> &'static Mutex<BlockState> {
    BLOCK_STATE.get_or_init(|| Mutex::new(BlockState::default()))
}

pub fn get_block_mode() -> u8 {
    blk_state().lock().unwrap().block_mode
}

pub fn set_block_bounds(
    mode: u8,
    sr: usize,
    sc: usize,
    er: usize,
    ec: usize,
) {
    {
        let mut bs = blk_state().lock().unwrap();
        bs.block_mode = mode;
        bs.start_row = sr;
        bs.start_col = sc;
        bs.end_row = er;
        bs.end_col = ec;
    }
    normalize_block_bounds();
}

pub fn toggle_block_mode() {
    let mode = get_block_mode();
    if mode == BLOCK_MODE_OFF {
        let (cr, cc) = get_cur_pos();
        {
            let mut bs = blk_state().lock().unwrap();
            bs.block_mode = BLOCK_MODE_SELECTING;
            bs.start_row = cr;
            bs.start_col = cc;
            bs.end_row = cr;
            bs.end_col = cc;
        }
        normalize_block_bounds();
    } else {
        cancel_block();
    }
}

pub fn cancel_block() {
    {
        let mut bs = blk_state().lock().unwrap();
        bs.block_mode = BLOCK_MODE_OFF;
    }
    render_all_lines();
}

pub fn solidify_block() {
    let mode = get_block_mode();
    if mode == BLOCK_MODE_SELECTING {
        let (cr, cc) = get_cur_pos();
        {
            let mut bs = blk_state().lock().unwrap();
            bs.end_row = cr;
            bs.end_col = cc;
            bs.block_mode = BLOCK_MODE_SOLIDIFIED;
        }
        normalize_block_bounds();
        let bs = *blk_state().lock().unwrap();
        if bs.norm_start_row == bs.norm_end_row
            && bs.norm_start_col == bs.norm_end_col
        {
            cancel_block();
        }
    }
}

pub fn normalize_block_bounds() {
    let (cr, cc) = get_cur_pos();
    let mut bs = blk_state().lock().unwrap();
    if bs.block_mode == BLOCK_MODE_SELECTING {
        bs.end_row = cr;
        bs.end_col = cc;
    }
    if bs.start_row < bs.end_row
        || (bs.start_row == bs.end_row && bs.start_col <= bs.end_col)
    {
        bs.norm_start_row = bs.start_row;
        bs.norm_start_col = bs.start_col;
        bs.norm_end_row = bs.end_row;
        bs.norm_end_col = bs.end_col;
    } else {
        bs.norm_start_row = bs.end_row;
        bs.norm_start_col = bs.end_col;
        bs.norm_end_row = bs.start_row;
        bs.norm_end_col = bs.start_col;
    }
}

pub fn get_norm_bounds() -> (usize, usize, usize, usize) {
    normalize_block_bounds();
    let bs = blk_state().lock().unwrap();
    (
        bs.norm_start_row,
        bs.norm_start_col,
        bs.norm_end_row,
        bs.norm_end_col,
    )
}

pub fn is_line_in_block(row: usize) -> u8 {
    if get_block_mode() == BLOCK_MODE_OFF {
        return 0;
    }
    let (sr, _, er, _) = get_norm_bounds();
    if row >= sr && row <= er {
        1
    } else {
        0
    }
}

pub fn is_char_in_block(row: usize, col: usize) -> u8 {
    if get_block_mode() == BLOCK_MODE_OFF {
        return 0;
    }
    let (sr, sc, er, ec) = get_norm_bounds();
    if row < sr || row > er {
        return 0;
    }
    if sr == er {
        if col >= sc && col < ec {
            1
        } else {
            0
        }
    } else if row == sr {
        if col >= sc {
            1
        } else {
            0
        }
    } else if row == er {
        if col < ec {
            1
        } else {
            0
        }
    } else {
        1
    }
}

pub fn is_cursor_in_block() -> u8 {
    if get_block_mode() == BLOCK_MODE_OFF {
        return 0;
    }
    let (cr, cc) = get_cur_pos();
    is_char_in_block(cr, cc)
}

pub fn get_selected_text() -> Option<String> {
    if get_block_mode() == BLOCK_MODE_OFF {
        return None;
    }
    let (sr, sc, er, ec) = get_norm_bounds();
    let cr = get_cur_pos().0;
    pack_line(cr);

    let line = get_line_bytes(sr);
    let start_col = sc.min(line.len());
    let end_col = if sr == er {
        ec.min(line.len())
    } else {
        line.len()
    };
    if end_col > start_col {
        let len = (end_col - start_col).min(63);
        Some(
            String::from_utf8_lossy(&line[start_col..start_col + len])
                .into_owned(),
        )
    } else {
        None
    }
}

pub fn do_delete_block() {
    if get_block_mode() == BLOCK_MODE_OFF {
        return;
    }
    let (cr, _) = get_cur_pos();
    pack_line(cr);
    let (sr, sc, er, ec) = get_norm_bounds();

    if sr == er {
        unpack_line(sr);
        {
            let mut b = buf_state().lock().unwrap();
            let line_len = b.active_line_buf.len();
            let s = sc.min(line_len);
            let e = ec.min(line_len);
            if e > s {
                b.active_line_buf.drain(s..e);
                b.active_line_dirty = 1;
                b.file_modified = 1;
            }
            b.cur_row = sr;
            b.cur_col = s;
        }
        pack_line(sr);
    } else {
        let end_line = get_line_bytes(er);
        let tail = if ec < end_line.len() {
            end_line[ec..].to_vec()
        } else {
            Vec::new()
        };

        for r in (sr + 1..=er).rev() {
            let _ = delete_line_at(r);
        }

        unpack_line(sr);
        {
            let mut b = buf_state().lock().unwrap();
            if sc < b.active_line_buf.len() {
                b.active_line_buf.truncate(sc);
            }
            if b.active_line_buf.len() + tail.len() <= MAX_INPUT_LINE_CHARS {
                b.active_line_buf.extend_from_slice(&tail);
            }
            b.active_line_dirty = 1;
            b.file_modified = 1;
            b.cur_row = sr;
            b.cur_col = sc.min(b.active_line_buf.len());
        }
        pack_line(sr);
    }

    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    cancel_block();
    render_all_lines();
}

pub fn do_copy_block() {
    let mode = get_block_mode();
    if mode == BLOCK_MODE_OFF {
        return;
    }
    if mode == BLOCK_MODE_SELECTING {
        solidify_block();
        if get_block_mode() == BLOCK_MODE_OFF {
            return;
        }
    }
    if is_cursor_in_block() != 0 {
        return;
    }

    let (cr, _) = get_cur_pos();
    pack_line(cr);
    let (sr, sc, er, ec) = get_norm_bounds();

    let mut extracted = Vec::new();
    for r in sr..=er {
        let line = get_line_bytes(r);
        let c_start = if r == sr { sc.min(line.len()) } else { 0 };
        let c_end = if r == er {
            ec.min(line.len())
        } else {
            line.len()
        };
        if c_end > c_start {
            extracted.extend_from_slice(&line[c_start..c_end]);
        }
        if r < er {
            extracted.push(b'\n');
        }
    }

    if extracted.is_empty() {
        return;
    }

    for &ch in &extracted {
        if ch == b'\n' {
            let (row, col) = get_cur_pos();
            pack_line(row);
            let line = get_line_bytes(row);
            let left = line[..col.min(line.len())].to_vec();
            let right = line[col.min(line.len())..].to_vec();
            if insert_line_at(row + 1, &right) == 0 {
                set_line_bytes(row, &left);
                {
                    let mut b = buf_state().lock().unwrap();
                    b.cur_row = row + 1;
                    b.cur_col = 0;
                    b.file_modified = 1;
                }
                unpack_line(row + 1);
            }
        } else {
            insert_char(ch);
        }
    }

    let (row, _) = get_cur_pos();
    pack_line(row);
    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    render_all_lines();
}

pub fn do_move_block() {
    let mode = get_block_mode();
    if mode == BLOCK_MODE_OFF {
        return;
    }
    if mode == BLOCK_MODE_SELECTING {
        solidify_block();
        if get_block_mode() == BLOCK_MODE_OFF {
            return;
        }
    }
    if is_cursor_in_block() != 0 {
        return;
    }

    let (orig_cr, orig_cc) = get_cur_pos();
    pack_line(orig_cr);
    let (sr, sc, er, ec) = get_norm_bounds();

    let mut extracted = Vec::new();
    for r in sr..=er {
        let line = get_line_bytes(r);
        let c_start = if r == sr { sc.min(line.len()) } else { 0 };
        let c_end = if r == er {
            ec.min(line.len())
        } else {
            line.len()
        };
        if c_end > c_start {
            extracted.extend_from_slice(&line[c_start..c_end]);
        }
        if r < er {
            extracted.push(b'\n');
        }
    }

    if extracted.is_empty() {
        return;
    }

    let mut target_row = orig_cr;
    let mut target_col = orig_cc;
    if orig_cr > er || (orig_cr == er && orig_cc >= ec) {
        if orig_cr == er {
            if sr == er {
                target_col = orig_cc.saturating_sub(ec.saturating_sub(sc));
            } else {
                target_row = sr;
                target_col = sc + orig_cc.saturating_sub(ec);
            }
        } else {
            target_row = orig_cr.saturating_sub(er.saturating_sub(sr));
        }
    }

    do_delete_block();

    {
        let mut b = buf_state().lock().unwrap();
        let tot = b.lines.len();
        if target_row >= tot {
            target_row = tot.saturating_sub(1);
        }
        b.cur_row = target_row;
    }
    unpack_line(target_row);
    {
        let mut b = buf_state().lock().unwrap();
        if target_col > b.active_line_buf.len() {
            target_col = b.active_line_buf.len();
        }
        b.cur_col = target_col;
    }

    let new_sr = target_row;
    let new_sc = target_col;

    for &ch in &extracted {
        if ch == b'\n' {
            let (row, col) = get_cur_pos();
            pack_line(row);
            let line = get_line_bytes(row);
            let left = line[..col.min(line.len())].to_vec();
            let right = line[col.min(line.len())..].to_vec();
            if insert_line_at(row + 1, &right) == 0 {
                set_line_bytes(row, &left);
                {
                    let mut b = buf_state().lock().unwrap();
                    b.cur_row = row + 1;
                    b.cur_col = 0;
                    b.file_modified = 1;
                }
                unpack_line(row + 1);
            }
        } else {
            insert_char(ch);
        }
    }

    let (end_r, end_c) = get_cur_pos();
    pack_line(end_r);
    set_block_bounds(BLOCK_MODE_SOLIDIFIED, new_sr, new_sc, end_r, end_c);
    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    render_all_lines();
}

pub fn do_block_menu_popup() {
    if get_block_mode() == BLOCK_MODE_OFF {
        return;
    }
    let (sr, sc, er, ec) = get_norm_bounds();
    let mode = get_block_mode();
    let (active_rows, active_cols) = get_active_dims();

    let width: u8 = 50;
    let height: u8 = 7;
    let avail_rows = active_rows.saturating_sub(1);
    let top = if avail_rows > height {
        ((avail_rows - height) / 2) + 1
    } else {
        1
    };
    let left = if active_cols > width {
        ((active_cols - width) / 2) + 1
    } else {
        1
    };

    modal_draw_frame(top, left, width, height, "Block Operations");

    let prefix = if mode == BLOCK_MODE_SOLIDIFIED {
        "Marked Block:"
    } else {
        "Selection:"
    };

    let line4 = if sr == er {
        let chars = ec.saturating_sub(sc);
        format!(
            "  {} {} {}",
            prefix,
            chars,
            if chars == 1 { "char" } else { "chars" }
        )
    } else {
        let lines = (er - sr) + 1;
        format!(
            "  {} {} {}",
            prefix,
            lines,
            if lines == 1 { "line" } else { "lines" }
        )
    };

    let line5 = if mode == BLOCK_MODE_SOLIDIFIED {
        "  [^C]=Copy Block  [^X]=Move  [^D]=Del"
    } else {
        "  [Enter]=Lock/Set  [^X]=Move  [^D]=Del"
    };
    let line6 = "  [^S]=Save  [^B]=Clear  [ESC]=Close";

    let inner_w = (width - 2) as usize;
    hal_console_locate(top + 3, left + 1);
    hal_console_puts(&format!("{:<width$}", line4, width = inner_w));
    hal_console_locate(top + 4, left + 1);
    hal_console_puts(&format!("{:<width$}", line5, width = inner_w));
    hal_console_locate(top + 5, left + 1);
    hal_console_puts(&format!("{:<width$}", line6, width = inner_w));
    hal_console_set_cursor_vis(0);

    loop {
        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ESC {
            hal_console_set_cursor_vis(1);
            render_all_lines();
            return;
        }
        if k == KEY_ENTER && mode == BLOCK_MODE_SELECTING {
            hal_console_set_cursor_vis(1);
            solidify_block();
            render_all_lines();
            return;
        }
        if k == KEY_CTRL_B || k == b'b' || k == b'B' {
            hal_console_set_cursor_vis(1);
            cancel_block();
            return;
        }
        if k == KEY_CTRL_C || k == b'c' || k == b'C' {
            hal_console_set_cursor_vis(1);
            if mode == BLOCK_MODE_SELECTING {
                solidify_block();
            }
            if get_block_mode() != BLOCK_MODE_OFF {
                do_copy_block();
            } else {
                render_all_lines();
            }
            return;
        }
        if k == KEY_CTRL_X
            || k == b'x'
            || k == b'X'
            || k == b'm'
            || k == b'M'
        {
            hal_console_set_cursor_vis(1);
            if mode == BLOCK_MODE_SELECTING {
                solidify_block();
            }
            if get_block_mode() != BLOCK_MODE_OFF {
                do_move_block();
            } else {
                render_all_lines();
            }
            return;
        }
        if k == KEY_CTRL_D || k == KEY_DEL || k == b'd' || k == b'D' {
            hal_console_set_cursor_vis(1);
            do_delete_block();
            return;
        }
        if k == KEY_CTRL_S || k == b's' || k == b'S' {
            hal_console_set_cursor_vis(1);
            if mode == BLOCK_MODE_SELECTING {
                solidify_block();
            }
            if get_block_mode() != BLOCK_MODE_OFF {
                if let Some(fname) = ui_browser_save_block_dialog() {
                    let (cr, _) = get_cur_pos();
                    pack_line(cr);
                    let (bsr, _, ber, _) = get_norm_bounds();
                    let fmt = buf_state().lock().unwrap().file_format;
                    if file_save_block(&fname, bsr, ber, fmt) == 0 {
                        render_all_lines();
                        modal_notify_status(
                            "Save Complete",
                            "Block saved to disk.",
                        );
                    }
                }
            }
            render_all_lines();
            return;
        }
        if k == KEY_CTRL_O || k == b'r' || k == b'R' {
            hal_console_set_cursor_vis(1);
            if let Some(fname) = ui_browser_insert_dialog() {
                cancel_block();
                let (cr, _) = get_cur_pos();
                pack_line(cr);
                let _ = file_insert(&fname);
            }
            render_all_lines();
            return;
        }
    }
}
