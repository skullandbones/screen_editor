/*
 * search.rs - Text search, find next, and search & replace engine
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 8.3 and Section 9.
 */

use crate::block::*;
use crate::buffer::*;
use crate::config::*;
use crate::editor::*;
use crate::hal_linux::*;
use crate::ui_modal::*;
use crate::ui_render::*;
use std::sync::{Mutex, OnceLock};

struct SearchState {
    query: String,
    replace_str: String,
}

static SEARCH_STATE: OnceLock<Mutex<SearchState>> = OnceLock::new();

fn search_state() -> &'static Mutex<SearchState> {
    SEARCH_STATE.get_or_init(|| {
        Mutex::new(SearchState {
            query: String::new(),
            replace_str: String::new(),
        })
    })
}

fn find_subslice_ci(
    haystack: &[u8],
    needle: &[u8],
    start_idx: usize,
) -> Option<usize> {
    if needle.is_empty() || start_idx + needle.len() > haystack.len() {
        return None;
    }
    let end_limit = haystack.len() - needle.len();
    for i in start_idx..=end_limit {
        let mut matched = true;
        for j in 0..needle.len() {
            if !haystack[i + j].eq_ignore_ascii_case(&needle[j]) {
                matched = false;
                break;
            }
        }
        if matched {
            return Some(i);
        }
    }
    None
}

fn find_next_from(
    start_row: usize,
    start_col: usize,
    query: &str,
) -> Option<(usize, usize)> {
    let q_bytes = query.as_bytes();
    if q_bytes.is_empty() {
        return None;
    }
    let (cr, _) = get_cur_pos();
    pack_line(cr);
    let tot = get_total_lines();

    for r in start_row..tot {
        let line = get_line_bytes(r);
        let c_start = if r == start_row { start_col } else { 0 };
        if let Some(col) = find_subslice_ci(&line, q_bytes, c_start) {
            return Some((r, col));
        }
    }

    for r in 0..=start_row.min(tot.saturating_sub(1)) {
        let line = get_line_bytes(r);
        if let Some(col) = find_subslice_ci(&line, q_bytes, 0) {
            return Some((r, col));
        }
    }
    None
}

fn jump_and_highlight_match(m_row: usize, m_col: usize, qlen: usize) {
    let (_, _, text_rows) = get_active_dims_with_text();
    let t_rows = text_rows as usize;
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_row = m_row;
        b.cur_col = m_col + qlen;
        if b.cur_row < b.view_top_row
            || b.cur_row >= b.view_top_row + t_rows
        {
            let half = t_rows / 2;
            b.view_top_row = b.cur_row.saturating_sub(half);
        }
    }
    unpack_line(m_row);
    set_block_bounds(BLOCK_MODE_SOLIDIFIED, m_row, m_col, m_row, m_col + qlen);
    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    update_horizontal_pan();
}

fn draw_find_field(
    top: u8,
    left: u8,
    buf: &[u8],
    cursor_pos: usize,
    max_vis: usize,
) {
    hal_console_locate(top + 3, left + 13);
    hal_console_putc(b'[');
    hal_console_set_attr(ATTR_INVERSE);
    let mut scroll_off = 0usize;
    if cursor_pos >= max_vis {
        scroll_off = cursor_pos - max_vis + 1;
    }
    for i in 0..max_vis {
        let idx = scroll_off + i;
        if idx < buf.len() {
            hal_console_putc(buf[idx]);
        } else {
            hal_console_putc(b' ');
        }
    }
    hal_console_set_attr(ATTR_NORMAL);
    hal_console_putc(b']');
    let cur_vis = (cursor_pos - scroll_off) as u8;
    hal_console_locate(top + 3, left + 14 + cur_vis);
}

pub fn do_ctrl_f_find() {
    let mut prefill = get_selected_text().unwrap_or_else(|| {
        search_state().lock().unwrap().query.clone()
    });
    if prefill.len() > 63 {
        prefill.truncate(63);
    }

    let (active_rows, active_cols) = get_active_dims();
    let width: u8 = 50;
    let height: u8 = 7;
    let max_vis: usize = 30;
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

    modal_draw_frame(top, left, width, height, "Find Text");
    hal_console_locate(top + 3, left + 7);
    hal_console_puts("Find: ");

    let footer = "[Enter]=Find          [ESC]=Cancel";
    let f_pad = ((width as usize - 2).saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 5, left + 1 + f_pad as u8);
    hal_console_puts(footer);

    let mut buf = prefill.into_bytes();
    let mut cursor_pos = buf.len();
    hal_console_set_cursor_vis(1);
    draw_find_field(top, left, &buf, cursor_pos, max_vis);

    loop {
        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ESC {
            render_all_lines();
            return;
        }
        if k == KEY_ENTER {
            break;
        }
        if k == KEY_LEFT {
            if cursor_pos > 0 {
                cursor_pos -= 1;
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if k == KEY_RIGHT {
            if cursor_pos < buf.len() {
                cursor_pos += 1;
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if k == KEY_HOME || k == KEY_CTRL_A {
            if cursor_pos > 0 {
                cursor_pos = 0;
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if k == KEY_END || k == KEY_CTRL_E {
            if cursor_pos < buf.len() {
                cursor_pos = buf.len();
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if k == KEY_BS || k == KEY_BS_ALT {
            if cursor_pos > 0 {
                buf.remove(cursor_pos - 1);
                cursor_pos -= 1;
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if k == KEY_DEL || k == KEY_CTRL_D {
            if cursor_pos < buf.len() {
                buf.remove(cursor_pos);
                draw_find_field(top, left, &buf, cursor_pos, max_vis);
            }
        } else if (0x20..=0x7E).contains(&k) && buf.len() < 63 {
            buf.insert(cursor_pos, k);
            cursor_pos += 1;
            draw_find_field(top, left, &buf, cursor_pos, max_vis);
        }
    }

    if buf.is_empty() {
        render_all_lines();
        return;
    }

    let query = String::from_utf8_lossy(&buf).into_owned();
    search_state().lock().unwrap().query = query.clone();

    let (cr, cc) = get_cur_pos();
    if let Some((mr, mc)) = find_next_from(cr, cc, &query) {
        jump_and_highlight_match(mr, mc, query.len());
        render_all_lines();
    } else {
        render_all_lines();
        modal_alert("Find Text", "Search string not found.", "");
    }
}

pub fn do_ctrl_n_next() {
    let query = search_state().lock().unwrap().query.clone();
    if query.is_empty() {
        do_ctrl_f_find();
        return;
    }
    let (cr, cc) = get_cur_pos();
    if let Some((mr, mc)) = find_next_from(cr, cc + 1, &query) {
        jump_and_highlight_match(mr, mc, query.len());
        render_all_lines();
    } else {
        modal_alert("Find Next", "No further occurrences found.", "");
    }
}

pub fn do_ctrl_r_replace() {
    let (mut q_buf, mut r_buf) = {
        let st = search_state().lock().unwrap();
        (st.query.clone(), st.replace_str.clone())
    };
    if let Some(sel) = get_selected_text() {
        q_buf = sel;
    }

    let k1 = modal_prompt_text(
        "Replace Text (Step 1/2)",
        "Find string:",
        &mut q_buf,
        63,
    );
    if k1 == KEY_ESC || q_buf.is_empty() {
        render_all_lines();
        return;
    }

    let k2 = modal_prompt_text(
        "Replace Text (Step 2/2)",
        "Replace with:",
        &mut r_buf,
        63,
    );
    if k2 == KEY_ESC {
        render_all_lines();
        return;
    }

    {
        let mut st = search_state().lock().unwrap();
        st.query = q_buf.clone();
        st.replace_str = r_buf.clone();
    }

    let qlen = q_buf.len();
    let r_bytes = r_buf.as_bytes();
    let rlen = r_bytes.len();
    let mut replace_all = false;
    let mut replaced_count = 0usize;
    let (mut cur_r, mut cur_c) = get_cur_pos();

    while let Some((mr, mc)) = find_next_from(cur_r, cur_c, &q_buf) {
        jump_and_highlight_match(mr, mc, qlen);
        render_all_lines();

        let mut do_rep = true;
        if !replace_all {
            let (active_rows, active_cols) = get_active_dims();
            let width: u8 = 50;
            let height: u8 = 7;
            let avail_rows = active_rows.saturating_sub(1);
            let top = if avail_rows > height {
                avail_rows - height
            } else {
                1
            };
            let left = if active_cols > width {
                ((active_cols - width) / 2) + 1
            } else {
                1
            };
            modal_draw_frame(top, left, width, height, "Confirm Replace");
            hal_console_locate(top + 3, left + 4);
            hal_console_puts("Replace this occurrence?");
            hal_console_locate(top + 5, left + 4);
            hal_console_puts("[Y]es   [N]o   [A]ll   [ESC]=Quit");
            hal_console_set_cursor_vis(0);

            loop {
                let k = hal_keyboard_get_key();
                if k == b'y' || k == b'Y' || k == KEY_ENTER {
                    do_rep = true;
                    break;
                } else if k == b'n' || k == b'N' {
                    do_rep = false;
                    break;
                } else if k == b'a' || k == b'A' {
                    replace_all = true;
                    do_rep = true;
                    break;
                } else if k == KEY_ESC || k == b'q' || k == b'Q' {
                    hal_console_set_cursor_vis(1);
                    cancel_block();
                    let msg = format!(
                        "Replaced {} occurrence(s).",
                        replaced_count
                    );
                    modal_notify_status("Replace Complete", &msg);
                    return;
                }
            }
            hal_console_set_cursor_vis(1);
        }

        if do_rep {
            unpack_line(mr);
            let mut next_col = mc + qlen;
            {
                let mut b = buf_state().lock().unwrap();
                if b.active_line_buf.len() + rlen - qlen <= MAX_INPUT_LINE_CHARS
                {
                    b.active_line_buf.splice(
                        mc..mc + qlen,
                        r_bytes.iter().copied(),
                    );
                    b.active_line_dirty = 1;
                    b.file_modified = 1;
                    b.cur_col = mc + rlen;
                    next_col = mc + rlen;
                    replaced_count += 1;
                }
            }
            pack_line(mr);
            cur_r = mr;
            cur_c = next_col;
        } else {
            cur_r = mr;
            cur_c = mc + qlen;
        }

        if replaced_count > 10000 {
            break;
        }
    }

    cancel_block();
    render_all_lines();
    let msg = format!("Replaced {} occurrence(s).", replaced_count);
    modal_notify_status("Replace Complete", &msg);
}
