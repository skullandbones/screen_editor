/*
 * ui_modal.rs - Tier 2 Centered Framed Modal Dialogs (Archetypes A, B, C)
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 8 and golden SE.COM.
 */

use crate::buffer::*;
use crate::config::*;
use crate::editor::*;
use crate::file_io::*;
use crate::hal_linux::*;
use crate::ui_browser::*;
use crate::ui_render::*;

pub const MODAL_RES_YES: u8 = 1;
pub const MODAL_RES_NO: u8 = 2;
pub const MODAL_RES_CANCEL: u8 = 3;

const MODAL_BOX_WIDTH: u8 = 50;

pub fn modal_draw_frame(
    top: u8,
    left: u8,
    width: u8,
    height: u8,
    title: &str,
) {
    let w = width as usize;
    let h = height as usize;
    let inner_w = w.saturating_sub(2);
    let border = format!("+{}+", "-".repeat(inner_w));

    for r in 0..h {
        hal_console_locate(top + r as u8, left);
        if r == 0 || r == 2 || r == h - 1 {
            hal_console_puts(&border);
        } else {
            let empty = format!("|{}|", " ".repeat(inner_w));
            hal_console_puts(&empty);
        }
    }

    if !title.is_empty() {
        let t_trunc = if title.len() > inner_w {
            &title[..inner_w]
        } else {
            title
        };
        let pad = (inner_w.saturating_sub(t_trunc.len())) / 2;
        hal_console_locate(top + 1, left + 1 + pad as u8);
        hal_console_set_attr(ATTR_BOLD);
        hal_console_puts(t_trunc);
        hal_console_set_attr(ATTR_NORMAL);
    }
}

pub fn modal_alert(title: &str, line1: &str, line2: &str) {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
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
    let inner_w = (width - 2) as usize;

    modal_draw_frame(top, left, width, height, title);

    if !line1.is_empty() {
        let l1 = if line1.len() > inner_w {
            &line1[..inner_w]
        } else {
            line1
        };
        let pad = (inner_w.saturating_sub(l1.len())) / 2;
        hal_console_locate(top + 3, left + 1 + pad as u8);
        hal_console_puts(l1);
    }

    if !line2.is_empty() {
        let l2 = if line2.len() > inner_w {
            &line2[..inner_w]
        } else {
            line2
        };
        let pad = (inner_w.saturating_sub(l2.len())) / 2;
        hal_console_locate(top + 4, left + 1 + pad as u8);
        hal_console_puts(l2);
    }

    let footer = "Press any key to continue";
    let f_pad = (inner_w.saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 5, left + 1 + f_pad as u8);
    hal_console_set_attr(ATTR_INVERSE);
    hal_console_puts(footer);
    hal_console_set_attr(ATTR_NORMAL);

    hal_console_set_cursor_vis(0);
    while hal_keyboard_get_key() == 0 {}
    hal_console_set_cursor_vis(1);
    render_all_lines();
}

pub fn modal_notify_status(title: &str, msg: &str) {
    modal_alert(title, msg, "");
}

pub fn modal_file_not_found(filename: &str) {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
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

    modal_draw_frame(top, left, width, height, "File Not Found");

    let fname = if filename.is_empty() {
        "(none)"
    } else {
        filename
    };
    let line1 = format!("'{}' was not found.", fname);
    let l1_trunc = if line1.len() > 44 {
        &line1[..44]
    } else {
        &line1
    };
    hal_console_locate(top + 3, left + 4);
    hal_console_puts(l1_trunc);

    hal_console_locate(top + 4, left + 4);
    hal_console_puts("Specified file not found on disk.");

    let footer = "Press any key to continue";
    let inner_w = (width - 2) as usize;
    let f_pad = (inner_w.saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 5, left + 1 + f_pad as u8);
    hal_console_set_attr(ATTR_INVERSE);
    hal_console_puts(footer);
    hal_console_set_attr(ATTR_NORMAL);

    hal_console_set_cursor_vis(0);
    while hal_keyboard_get_key() == 0 {}
    hal_console_set_cursor_vis(1);
}

pub fn modal_confirm(title: &str, desc: &str, question: &str) -> u8 {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
    let height: u8 = 8;
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
    let inner_w = (width - 2) as usize;

    modal_draw_frame(top, left, width, height, title);

    if !desc.is_empty() {
        let d_trunc = if desc.len() > inner_w {
            &desc[..inner_w]
        } else {
            desc
        };
        let pad = (inner_w.saturating_sub(d_trunc.len())) / 2;
        hal_console_locate(top + 3, left + 1 + pad as u8);
        hal_console_puts(d_trunc);
    }

    if !question.is_empty() {
        let q_trunc = if question.len() > inner_w {
            &question[..inner_w]
        } else {
            question
        };
        let pad = (inner_w.saturating_sub(q_trunc.len())) / 2;
        hal_console_locate(top + 4, left + 1 + pad as u8);
        hal_console_set_attr(ATTR_BOLD);
        hal_console_puts(q_trunc);
        hal_console_set_attr(ATTR_NORMAL);
    }

    let opts = "[Y]es      [N]o      [ESC]=Cancel";
    let o_pad = (inner_w.saturating_sub(opts.len())) / 2;
    hal_console_locate(top + 6, left + 1 + o_pad as u8);
    hal_console_puts(opts);

    let mut sel = 0u8;
    loop {
        hal_console_locate(top + 6, left + 1 + o_pad as u8);
        if sel == 0 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[Y]es");
        hal_console_set_attr(ATTR_NORMAL);
        hal_console_puts("      ");
        if sel == 1 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[N]o");
        hal_console_set_attr(ATTR_NORMAL);
        hal_console_puts("      ");
        if sel == 2 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[ESC]=Cancel");
        hal_console_set_attr(ATTR_NORMAL);

        hal_console_set_cursor_vis(0);
        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == b'y' || k == b'Y' {
            hal_console_set_cursor_vis(1);
            return MODAL_RES_YES;
        }
        if k == b'n' || k == b'N' {
            hal_console_set_cursor_vis(1);
            return MODAL_RES_NO;
        }
        if k == KEY_ESC {
            hal_console_set_cursor_vis(1);
            return MODAL_RES_CANCEL;
        }
        if k == KEY_LEFT {
            sel = if sel > 0 { sel - 1 } else { 2 };
        } else if k == KEY_RIGHT || k == KEY_TAB {
            sel = (sel + 1) % 3;
        } else if k == KEY_ENTER {
            hal_console_set_cursor_vis(1);
            return match sel {
                0 => MODAL_RES_YES,
                1 => MODAL_RES_NO,
                _ => MODAL_RES_CANCEL,
            };
        }
    }
}

pub fn modal_confirm_overwrite() -> u8 {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
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
    let inner_w = (width - 2) as usize;

    modal_draw_frame(top, left, width, height, "Overwrite File");

    let desc = "Existing file contents will be lost";
    let d_pad = (inner_w.saturating_sub(desc.len())) / 2;
    hal_console_locate(top + 3, left + 1 + d_pad as u8);
    hal_console_puts(desc);

    let question = "File already exists. Overwrite? ";
    let q_pad = (inner_w.saturating_sub(question.len())) / 2;
    hal_console_locate(top + 4, left + 1 + q_pad as u8);
    hal_console_set_attr(ATTR_BOLD);
    hal_console_puts(question);
    hal_console_set_attr(ATTR_NORMAL);

    let opts = "[Y]es     [N]o     [ESC]=Cancel";
    let o_pad = (inner_w.saturating_sub(opts.len())) / 2;
    let mut sel = 0u8;

    loop {
        hal_console_locate(top + 5, left + 1 + o_pad as u8);
        if sel == 0 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[Y]es");
        hal_console_set_attr(ATTR_NORMAL);
        hal_console_puts("     ");
        if sel == 1 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[N]o");
        hal_console_set_attr(ATTR_NORMAL);
        hal_console_puts("     ");
        if sel == 2 {
            hal_console_set_attr(ATTR_INVERSE);
        }
        hal_console_puts("[ESC]=Cancel");
        hal_console_set_attr(ATTR_NORMAL);

        hal_console_locate(
            top + 4,
            left + 1 + q_pad as u8 + question.len() as u8,
        );
        hal_console_set_cursor_vis(1);

        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == b'y' || k == b'Y' {
            return MODAL_RES_YES;
        }
        if k == b'n' || k == b'N' {
            return MODAL_RES_NO;
        }
        if k == KEY_ESC {
            return MODAL_RES_CANCEL;
        }
        if k == KEY_LEFT {
            sel = if sel > 0 { sel - 1 } else { 2 };
        } else if k == KEY_RIGHT || k == KEY_TAB {
            sel = (sel + 1) % 3;
        } else if k == KEY_ENTER {
            return match sel {
                0 => MODAL_RES_YES,
                1 => MODAL_RES_NO,
                _ => MODAL_RES_CANCEL,
            };
        }
    }
}

fn draw_input_field(
    row: u8,
    col: u8,
    buf: &[u8],
    cursor_pos: usize,
    max_vis: usize,
) {
    hal_console_locate(row, col);
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
    hal_console_locate(row, col + 1 + cur_vis);
}

pub fn modal_prompt_text(
    title: &str,
    prompt_label: &str,
    buf_str: &mut String,
    max_len: usize,
) -> u8 {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
    let height: u8 = 7;
    let max_vis: usize = 24;
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
    let inner_w = (width - 2) as usize;

    modal_draw_frame(top, left, width, height, title);

    hal_console_locate(top + 3, left + 3);
    hal_console_puts(prompt_label);

    let field_col = left + 4 + prompt_label.len() as u8;
    let footer = "[Enter]=Confirm        [ESC]=Cancel";
    let f_pad = (inner_w.saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 5, left + 1 + f_pad as u8);
    hal_console_puts(footer);

    let mut buf = buf_str.as_bytes().to_vec();
    if buf.len() > max_len {
        buf.truncate(max_len);
    }
    let mut cursor_pos = buf.len();
    hal_console_set_cursor_vis(1);
    draw_input_field(top + 3, field_col, &buf, cursor_pos, max_vis);

    loop {
        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ENTER || k == KEY_ESC {
            *buf_str = String::from_utf8_lossy(&buf).into_owned();
            return k;
        }
        if k == KEY_LEFT {
            if cursor_pos > 0 {
                cursor_pos -= 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_RIGHT {
            if cursor_pos < buf.len() {
                cursor_pos += 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_HOME || k == KEY_CTRL_A {
            if cursor_pos > 0 {
                cursor_pos = 0;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_END || k == KEY_CTRL_E {
            if cursor_pos < buf.len() {
                cursor_pos = buf.len();
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_BS || k == KEY_BS_ALT {
            if cursor_pos > 0 {
                buf.remove(cursor_pos - 1);
                cursor_pos -= 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_DEL || k == KEY_CTRL_D {
            if cursor_pos < buf.len() {
                buf.remove(cursor_pos);
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if (0x20..=0x7E).contains(&k) && buf.len() < max_len {
            buf.insert(cursor_pos, k);
            cursor_pos += 1;
            draw_input_field(top + 3, field_col, &buf, cursor_pos, max_vis);
        }
    }
}

pub fn modal_goto_line() -> bool {
    let (active_rows, active_cols) = get_active_dims();
    let width = MODAL_BOX_WIDTH;
    let height: u8 = 7;
    let max_vis: usize = 5;
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
    let inner_w = (width - 2) as usize;

    modal_draw_frame(top, left, width, height, "Goto Line");
    hal_console_locate(top + 3, left + 16);
    hal_console_puts("Goto line: ");

    let field_col = left + 27;
    let footer = "[Enter]=Goto Line     [ESC]=Cancel";
    let f_pad = (inner_w.saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 5, left + 1 + f_pad as u8);
    hal_console_puts(footer);

    let mut buf: Vec<u8> = Vec::new();
    let mut cursor_pos = 0usize;
    hal_console_set_cursor_vis(1);
    draw_input_field(top + 3, field_col, &buf, cursor_pos, max_vis);

    loop {
        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ESC {
            if get_is_splash_screen() == 0 {
                render_all_lines();
            }
            return false;
        }
        if k == KEY_ENTER {
            break;
        }
        if k == KEY_LEFT {
            if cursor_pos > 0 {
                cursor_pos -= 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_RIGHT {
            if cursor_pos < buf.len() {
                cursor_pos += 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_HOME || k == KEY_CTRL_A {
            if cursor_pos > 0 {
                cursor_pos = 0;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_END || k == KEY_CTRL_E {
            if cursor_pos < buf.len() {
                cursor_pos = buf.len();
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_BS || k == KEY_BS_ALT {
            if cursor_pos > 0 {
                buf.remove(cursor_pos - 1);
                cursor_pos -= 1;
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k == KEY_DEL || k == KEY_CTRL_D {
            if cursor_pos < buf.len() {
                buf.remove(cursor_pos);
                draw_input_field(
                    top + 3,
                    field_col,
                    &buf,
                    cursor_pos,
                    max_vis,
                );
            }
        } else if k.is_ascii_digit() && buf.len() < max_vis {
            buf.insert(cursor_pos, k);
            cursor_pos += 1;
            draw_input_field(top + 3, field_col, &buf, cursor_pos, max_vis);
        }
    }

    let mut jumped = false;
    let s = String::from_utf8_lossy(&buf);
    if let Ok(target) = s.trim().parse::<usize>() {
        if target > 0 {
            let (cr, _) = get_cur_pos();
            pack_line(cr);
            let (_, _, text_rows) = get_active_dims_with_text();
            let t_rows = text_rows as usize;
            let new_row;
            {
                let mut b = buf_state().lock().unwrap();
                let tot = b.lines.len();
                let clamped = target.min(tot);
                new_row = clamped - 1;
                b.cur_row = new_row;
                b.cur_col = 0;
                b.target_vis_col = 0;
                b.view_left_col = 0;
                if b.cur_row < b.view_top_row
                    || b.cur_row >= b.view_top_row + t_rows
                {
                    let half = t_rows / 2;
                    b.view_top_row = b.cur_row.saturating_sub(half);
                }
            }
            unpack_line(new_row);
            update_horizontal_pan();
            jumped = true;
        }
    }
    if get_is_splash_screen() == 0 {
        render_all_lines();
    }
    jumped
}

pub fn modal_confirm_save_changes() -> u8 {
    let modified = buf_state().lock().unwrap().file_modified;
    if modified == 0 {
        return MODAL_RES_NO;
    }

    let res = modal_confirm(
        "Unsaved Modifications",
        "Any unsaved edits will be lost if discarded.",
        "Save changes?",
    );
    if res == MODAL_RES_YES {
        let (cr, _) = get_cur_pos();
        pack_line(cr);
        let (has_name, fmt) = {
            let b = buf_state().lock().unwrap();
            (!b.current_filename.is_empty(), b.file_format)
        };
        if !has_name {
            if let Some(fname) = ui_browser_save_dialog() {
                let fmt_now = buf_state().lock().unwrap().file_format;
                let _ = file_save(Some(&fname), fmt_now);
            } else {
                return MODAL_RES_CANCEL;
            }
        } else {
            let _ = file_save(None, fmt);
        }
    }
    res
}
