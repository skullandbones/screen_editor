/*
 * editor.rs - Core editor navigation, text mutation, and command dispatch
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 6 and Section 10.
 */

use crate::beautify::*;
use crate::block::*;
use crate::buffer::*;
use crate::config::*;
use crate::file_io::*;
use crate::hal_linux::*;
use crate::plugin_mgr::*;
use crate::search::*;
use crate::ui_browser::*;
use crate::ui_modal::*;
use crate::ui_render::*;

pub fn editor_sync_geometry() {
    let (rows, cols) = hal_console_get_size();
    let r = if rows >= 10 { rows } else { ROWS_24 };
    let c = if cols >= 40 { cols } else { COLS_80 };
    set_active_dims(r, c);
}

pub fn editor_apply_winch() {
    let cfg = get_config();
    let (nr, nc) = hal_console_get_native_size();
    if cfg.screen_mode == MODE_NATIVE {
        let r = if nr >= ROWS_24 { nr } else { ROWS_24 };
        let c = if nc >= COLS_80 { nc } else { COLS_80 };
        set_active_dims(r, c);
    } else if nc >= COLS_120 && nr >= ROWS_40 {
        set_active_dims(ROWS_40, COLS_120);
    } else if cfg.screen_mode == MODE_120X40 {
        set_active_dims(ROWS_40, COLS_120);
    } else {
        set_active_dims(ROWS_24, COLS_80);
    }
}

pub fn editor_init() {
    editor_apply_winch();
    set_is_splash_screen(1);
    set_exit_flag(0);
    set_block_bounds(BLOCK_MODE_OFF, 0, 0, 0, 0);
}

pub fn calc_visual_col() -> usize {
    let mut tab_w = get_config().tab_width as usize;
    if tab_w == 0 {
        tab_w = 8;
    }
    let b = buf_state().lock().unwrap();
    let max_idx = b.cur_col.min(b.active_line_buf.len());
    let mut vis = 0usize;
    for i in 0..max_idx {
        if b.active_line_buf[i] == b'\t' {
            let spaces = tab_w - (vis % tab_w);
            vis += spaces;
        } else {
            vis += 1;
        }
    }
    if vis > MAX_LINE_CHARS {
        MAX_LINE_CHARS
    } else {
        vis
    }
}

pub fn adjust_col_to_target() {
    let mut tab_w = get_config().tab_width as usize;
    if tab_w == 0 {
        tab_w = 8;
    }
    let mut b = buf_state().lock().unwrap();
    let target = b.target_vis_col;
    let mut vis_acc = 0usize;
    let mut char_idx = 0usize;
    let line_len = b.active_line_buf.len();

    while char_idx < line_len && vis_acc < target {
        if b.active_line_buf[char_idx] == b'\t' {
            let spaces = tab_w - (vis_acc % tab_w);
            vis_acc += spaces;
            char_idx += 1;
        } else {
            vis_acc += 1;
            char_idx += 1;
        }
    }
    b.cur_col = char_idx;
}

pub fn update_horizontal_pan() -> u8 {
    let vis_col = calc_visual_col();
    let (_, active_cols) = get_active_dims();
    let cols = active_cols as usize;
    let pan_step = 40usize;

    let mut b = buf_state().lock().unwrap();
    let old_pan = b.view_left_col;
    let right_limit = b.view_left_col + cols.saturating_sub(1);

    let mut need_pan_right = false;
    if vis_col > right_limit {
        need_pan_right = true;
    } else if vis_col == right_limit {
        if (b.cur_col + 1) < b.active_line_buf.len() {
            need_pan_right = true;
        }
    }

    if need_pan_right {
        b.view_left_col = ((vis_col.saturating_sub(1)) / pan_step) * pan_step;
        if b.view_left_col == 0 {
            b.view_left_col = pan_step;
        }
        if b.view_left_col + cols > MAX_LINE_CHARS {
            b.view_left_col = MAX_LINE_CHARS.saturating_sub(cols);
        }
    } else if vis_col < b.view_left_col {
        if vis_col == 0 {
            b.view_left_col = 0;
        } else {
            b.view_left_col =
                ((vis_col.saturating_sub(1)) / pan_step) * pan_step;
        }
    }

    if b.view_left_col != old_pan {
        1
    } else {
        0
    }
}

pub fn move_up() {
    let (cr, _) = get_cur_pos();
    if cr == 0 {
        return;
    }
    pack_line(cr);
    let new_row = cr - 1;
    let mut scrolled = false;
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_row = new_row;
        if new_row < b.view_top_row {
            b.view_top_row = new_row;
            scrolled = true;
        }
    }
    unpack_line(new_row);
    adjust_col_to_target();
    let panned = update_horizontal_pan() != 0;
    if scrolled || panned || get_block_mode() == BLOCK_MODE_SELECTING {
        render_all_lines();
    } else {
        render_status_bar();
        locate_cursor();
    }
}

pub fn move_down() {
    let (cr, _) = get_cur_pos();
    let tot = get_total_lines();
    if cr + 1 >= tot {
        return;
    }
    pack_line(cr);
    let new_row = cr + 1;
    let (_, _, text_rows) = get_active_dims_with_text();
    let t_rows = text_rows as usize;
    let mut scrolled = false;
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_row = new_row;
        if new_row >= b.view_top_row + t_rows {
            b.view_top_row = new_row + 1 - t_rows;
            scrolled = true;
        }
    }
    unpack_line(new_row);
    adjust_col_to_target();
    let panned = update_horizontal_pan() != 0;
    if scrolled || panned || get_block_mode() == BLOCK_MODE_SELECTING {
        render_all_lines();
    } else {
        render_status_bar();
        locate_cursor();
    }
}

pub fn move_left() {
    let (cr, cc) = get_cur_pos();
    if cc > 0 {
        buf_state().lock().unwrap().cur_col = cc - 1;
        let vis = calc_visual_col();
        buf_state().lock().unwrap().target_vis_col = vis;
        if update_horizontal_pan() != 0
            || get_block_mode() == BLOCK_MODE_SELECTING
        {
            render_all_lines();
        } else {
            render_status_bar();
            locate_cursor();
        }
    } else if cr > 0 {
        pack_line(cr);
        let new_row = cr - 1;
        let mut scrolled = false;
        {
            let mut b = buf_state().lock().unwrap();
            b.cur_row = new_row;
            if new_row < b.view_top_row {
                b.view_top_row = new_row;
                scrolled = true;
            }
        }
        unpack_line(new_row);
        {
            let mut b = buf_state().lock().unwrap();
            b.cur_col = b.active_line_buf.len();
        }
        let vis = calc_visual_col();
        buf_state().lock().unwrap().target_vis_col = vis;
        if update_horizontal_pan() != 0
            || scrolled
            || get_block_mode() == BLOCK_MODE_SELECTING
        {
            render_all_lines();
        } else {
            render_status_bar();
            locate_cursor();
        }
    }
}

pub fn move_right() {
    let (cr, cc) = get_cur_pos();
    let line_len = get_line_len(cr);
    let tot = get_total_lines();
    if cc < line_len {
        buf_state().lock().unwrap().cur_col = cc + 1;
        let vis = calc_visual_col();
        buf_state().lock().unwrap().target_vis_col = vis;
        if update_horizontal_pan() != 0
            || get_block_mode() == BLOCK_MODE_SELECTING
        {
            render_all_lines();
        } else {
            render_status_bar();
            locate_cursor();
        }
    } else if cr + 1 < tot {
        pack_line(cr);
        let new_row = cr + 1;
        let (_, _, text_rows) = get_active_dims_with_text();
        let t_rows = text_rows as usize;
        let mut scrolled = false;
        {
            let mut b = buf_state().lock().unwrap();
            b.cur_row = new_row;
            b.cur_col = 0;
            b.target_vis_col = 0;
            if new_row >= b.view_top_row + t_rows {
                b.view_top_row = new_row + 1 - t_rows;
                scrolled = true;
            }
        }
        unpack_line(new_row);
        if update_horizontal_pan() != 0
            || scrolled
            || get_block_mode() == BLOCK_MODE_SELECTING
        {
            render_all_lines();
        } else {
            render_status_bar();
            locate_cursor();
        }
    }
}

pub fn page_up() {
    let (cr, _) = get_cur_pos();
    if cr == 0 {
        return;
    }
    pack_line(cr);
    let (_, _, text_rows) = get_active_dims_with_text();
    let step = if text_rows > 1 {
        (text_rows - 1) as usize
    } else {
        1
    };
    let new_row;
    {
        let mut b = buf_state().lock().unwrap();
        new_row = b.cur_row.saturating_sub(step);
        b.cur_row = new_row;
        b.view_top_row = b.view_top_row.saturating_sub(step);
        if b.cur_row < b.view_top_row {
            b.view_top_row = b.cur_row;
        }
    }
    unpack_line(new_row);
    adjust_col_to_target();
    update_horizontal_pan();
    render_all_lines();
}

pub fn page_down() {
    let (cr, _) = get_cur_pos();
    let tot = get_total_lines();
    if cr + 1 >= tot {
        return;
    }
    pack_line(cr);
    let (_, _, text_rows) = get_active_dims_with_text();
    let t_rows = text_rows as usize;
    let step = if t_rows > 1 { t_rows - 1 } else { 1 };
    let new_row;
    {
        let mut b = buf_state().lock().unwrap();
        new_row = (b.cur_row + step).min(tot - 1);
        b.cur_row = new_row;
        b.view_top_row += step;
        if b.view_top_row + t_rows > tot {
            if tot > t_rows {
                b.view_top_row = tot - t_rows;
            } else {
                b.view_top_row = 0;
            }
        }
        if b.cur_row >= b.view_top_row + t_rows {
            b.view_top_row = b.cur_row + 1 - t_rows;
        }
    }
    unpack_line(new_row);
    adjust_col_to_target();
    update_horizontal_pan();
    render_all_lines();
}

pub fn do_ctrl_a_home() {
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_col = 0;
        b.target_vis_col = 0;
    }
    if update_horizontal_pan() != 0
        || get_block_mode() == BLOCK_MODE_SELECTING
    {
        render_all_lines();
    } else {
        render_status_bar();
        locate_cursor();
    }
}

pub fn do_ctrl_e_end() {
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_col = b.active_line_buf.len();
    }
    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    if update_horizontal_pan() != 0
        || get_block_mode() == BLOCK_MODE_SELECTING
    {
        render_all_lines();
    } else {
        render_status_bar();
        locate_cursor();
    }
}

pub fn do_ctrl_t_top() {
    let (cr, _) = get_cur_pos();
    pack_line(cr);
    {
        let mut b = buf_state().lock().unwrap();
        b.cur_row = 0;
        b.cur_col = 0;
        b.target_vis_col = 0;
        b.view_top_row = 0;
        b.view_left_col = 0;
    }
    unpack_line(0);
    render_all_lines();
}

pub fn do_ctrl_g_bottom() {
    let (cr, _) = get_cur_pos();
    pack_line(cr);
    let (_, _, text_rows) = get_active_dims_with_text();
    let t_rows = text_rows as usize;
    let new_row;
    {
        let mut b = buf_state().lock().unwrap();
        let tot = b.lines.len();
        new_row = tot.saturating_sub(1);
        b.cur_row = new_row;
        b.cur_col = 0;
        b.target_vis_col = 0;
        b.view_left_col = 0;
        if tot > t_rows {
            b.view_top_row = tot - t_rows;
        } else {
            b.view_top_row = 0;
        }
    }
    unpack_line(new_row);
    render_all_lines();
}

pub fn insert_char(c: u8) {
    let row;
    {
        let mut b = buf_state().lock().unwrap();
        row = b.cur_row;
        if b.insert_mode != 0 {
            if b.active_line_buf.len() >= MAX_INPUT_LINE_CHARS {
                return;
            }
            let col = b.cur_col.min(b.active_line_buf.len());
            b.active_line_buf.insert(col, c);
            b.cur_col = col + 1;
        } else {
            let col = b.cur_col;
            if col >= MAX_INPUT_LINE_CHARS {
                return;
            }
            if col == b.active_line_buf.len() {
                b.active_line_buf.push(c);
            } else if col < b.active_line_buf.len() {
                b.active_line_buf[col] = c;
            }
            b.cur_col = col + 1;
        }
        b.active_line_dirty = 1;
        b.file_modified = 1;
    }
    let vis = calc_visual_col();
    buf_state().lock().unwrap().target_vis_col = vis;
    if update_horizontal_pan() != 0 {
        render_all_lines();
    } else {
        render_line(row);
        render_status_bar();
        locate_cursor();
    }
}

pub fn do_enter_split() {
    let cfg = get_config();
    let (cr, cc) = get_cur_pos();
    let line = get_line_bytes(cr);
    let mut indent = Vec::new();
    if cfg.auto_indent != 0 {
        for &ch in &line[..cc.min(line.len())] {
            if ch == b' ' || ch == b'\t' {
                indent.push(ch);
            } else {
                break;
            }
        }
    }
    let tail = &line[cc.min(line.len())..];
    let mut next_line = indent.clone();
    let avail = MAX_LINE_CHARS.saturating_sub(next_line.len());
    next_line.extend_from_slice(&tail[..tail.len().min(avail)]);

    {
        let mut b = buf_state().lock().unwrap();
        let col = cc.min(b.active_line_buf.len());
        b.active_line_buf.truncate(col);
        b.active_line_dirty = 1;
    }
    pack_line(cr);

    if insert_line_at(cr + 1, &next_line) == 0 {
        let (_, _, text_rows) = get_active_dims_with_text();
        let t_rows = text_rows as usize;
        let new_row = cr + 1;
        {
            let mut b = buf_state().lock().unwrap();
            b.cur_row = new_row;
            if new_row >= b.view_top_row + t_rows {
                b.view_top_row = new_row + 1 - t_rows;
            }
            b.cur_col = indent.len();
            b.file_modified = 1;
        }
        unpack_line(new_row);
        let vis = calc_visual_col();
        buf_state().lock().unwrap().target_vis_col = vis;
        update_horizontal_pan();
        render_all_lines();
    }
}

pub fn do_backspace() {
    let (cr, cc) = get_cur_pos();
    if cc > 0 {
        {
            let mut b = buf_state().lock().unwrap();
            let col = cc.min(b.active_line_buf.len());
            if col > 0 {
                b.active_line_buf.remove(col - 1);
                b.cur_col = col - 1;
                b.active_line_dirty = 1;
                b.file_modified = 1;
            }
        }
        let vis = calc_visual_col();
        buf_state().lock().unwrap().target_vis_col = vis;
        if update_horizontal_pan() != 0 {
            render_all_lines();
        } else {
            render_line(cr);
            render_status_bar();
            locate_cursor();
        }
    } else if cr > 0 {
        let prev_len = get_line_len(cr - 1);
        let cur_len = get_line_len(cr);
        if prev_len + cur_len <= MAX_INPUT_LINE_CHARS {
            let cur_bytes = get_line_bytes(cr);
            pack_line(cr);
            let _ = delete_line_at(cr);
            let new_row = cr - 1;
            {
                let mut b = buf_state().lock().unwrap();
                b.cur_row = new_row;
                if new_row < b.view_top_row {
                    b.view_top_row = new_row;
                }
            }
            unpack_line(new_row);
            {
                let mut b = buf_state().lock().unwrap();
                b.active_line_buf.extend_from_slice(&cur_bytes);
                b.cur_col = prev_len;
                b.active_line_dirty = 1;
                b.file_modified = 1;
            }
            pack_line(new_row);
            let vis = calc_visual_col();
            buf_state().lock().unwrap().target_vis_col = vis;
            update_horizontal_pan();
            render_all_lines();
        }
    }
}

pub fn do_delete() {
    let (cr, cc) = get_cur_pos();
    let cur_len = get_line_len(cr);
    let tot = get_total_lines();
    if cc < cur_len {
        {
            let mut b = buf_state().lock().unwrap();
            b.active_line_buf.remove(cc);
            b.active_line_dirty = 1;
            b.file_modified = 1;
        }
        render_line(cr);
        render_status_bar();
        locate_cursor();
    } else if cr + 1 < tot {
        let next_bytes = get_line_bytes(cr + 1);
        if cur_len + next_bytes.len() <= MAX_INPUT_LINE_CHARS {
            {
                let mut b = buf_state().lock().unwrap();
                b.cur_col = cur_len;
                b.active_line_buf.extend_from_slice(&next_bytes);
                b.active_line_dirty = 1;
                b.file_modified = 1;
            }
            pack_line(cr);
            let _ = delete_line_at(cr + 1);
            let vis = calc_visual_col();
            buf_state().lock().unwrap().target_vis_col = vis;
            render_all_lines();
        }
    }
}

pub fn editor_handle_key(k: u8) {
    if k == 0 {
        return;
    }

    match k {
        KEY_UP => move_up(),
        KEY_DOWN => move_down(),
        KEY_LEFT => move_left(),
        KEY_RIGHT => move_right(),
        KEY_PGUP | KEY_CTRL_U => page_up(),
        KEY_PGDN | KEY_CTRL_V => page_down(),
        KEY_HOME | KEY_CTRL_A => do_ctrl_a_home(),
        KEY_END | KEY_CTRL_E => do_ctrl_e_end(),
        KEY_CTRL_T => do_ctrl_t_top(),
        KEY_CTRL_G => do_ctrl_g_bottom(),
        KEY_ENTER => {
            if get_block_mode() == BLOCK_MODE_SELECTING {
                solidify_block();
                render_status_bar();
                locate_cursor();
            } else {
                if get_block_mode() == BLOCK_MODE_SOLIDIFIED {
                    cancel_block();
                }
                do_enter_split();
            }
        }
        KEY_BS | KEY_BS_ALT => {
            if get_block_mode() == BLOCK_MODE_SELECTING {
                cancel_block();
            } else {
                if get_block_mode() == BLOCK_MODE_SOLIDIFIED {
                    cancel_block();
                }
                do_backspace();
            }
        }
        KEY_DEL | KEY_CTRL_D => {
            if get_block_mode() != BLOCK_MODE_OFF {
                do_delete_block();
            } else {
                do_delete();
            }
        }
        KEY_INS => {
            {
                let mut b = buf_state().lock().unwrap();
                b.insert_mode = if b.insert_mode != 0 { 0 } else { 1 };
            }
            render_status_bar();
            locate_cursor();
        }
        KEY_CTRL_B => {
            toggle_block_mode();
            render_status_bar();
            locate_cursor();
        }
        KEY_CTRL_C => do_copy_block(),
        KEY_CTRL_X => do_move_block(),
        KEY_CTRL_Y => beautify_buffer(),
        KEY_CTRL_F => do_ctrl_f_find(),
        KEY_CTRL_N => do_ctrl_n_next(),
        KEY_CTRL_R => do_ctrl_r_replace(),
        KEY_CTRL_P => show_plugin_palette(),
        KEY_CTRL_L => {
            let _ = modal_goto_line();
        }
        KEY_CTRL_O => {
            if get_block_mode() != BLOCK_MODE_OFF {
                if get_block_mode() == BLOCK_MODE_SELECTING {
                    solidify_block();
                }
                if let Some(fname) = ui_browser_insert_dialog() {
                    cancel_block();
                    let (cr, _) = get_cur_pos();
                    pack_line(cr);
                    let _ = file_insert(&fname);
                }
                render_all_lines();
            } else {
                let res = modal_confirm_save_changes();
                if res != MODAL_RES_CANCEL {
                    if let Some(fname) = ui_browser_open_dialog() {
                        cancel_block();
                        let _ = file_load(&fname);
                    }
                    render_all_lines();
                } else {
                    render_all_lines();
                }
            }
        }
        KEY_CTRL_S => {
            if get_block_mode() != BLOCK_MODE_OFF {
                if get_block_mode() == BLOCK_MODE_SELECTING {
                    solidify_block();
                }
                if get_block_mode() != BLOCK_MODE_OFF {
                    if let Some(fname) = ui_browser_save_block_dialog() {
                        let (cr, _) = get_cur_pos();
                        pack_line(cr);
                        let (sr, _, er, _) = get_norm_bounds();
                        let fmt = buf_state().lock().unwrap().file_format;
                        if file_save_block(&fname, sr, er, fmt) == 0 {
                            render_all_lines();
                            modal_notify_status(
                                "Save Complete",
                                "Block saved to disk.",
                            );
                        }
                    }
                }
                render_all_lines();
            } else {
                let (cr, _) = get_cur_pos();
                pack_line(cr);
                let (has_name, fmt) = {
                    let b = buf_state().lock().unwrap();
                    (!b.current_filename.is_empty(), b.file_format)
                };
                if !has_name {
                    if let Some(fname) = ui_browser_save_dialog() {
                        let fmt_now = buf_state().lock().unwrap().file_format;
                        if file_save(Some(&fname), fmt_now) == 0 {
                            render_all_lines();
                            modal_notify_status(
                                "Save Complete",
                                "Document saved to disk.",
                            );
                        } else {
                            render_all_lines();
                        }
                    } else {
                        render_all_lines();
                    }
                } else if file_save(None, fmt) == 0 {
                    modal_notify_status(
                        "Save Complete",
                        "Document saved to disk.",
                    );
                }
            }
        }
        KEY_CTRL_W => {
            let res = modal_confirm_save_changes();
            if res != MODAL_RES_CANCEL {
                cancel_block();
                buffer_reset_empty();
                show_splash_screen();
            } else {
                render_all_lines();
            }
        }
        KEY_CTRL_K => {
            if get_block_mode() != BLOCK_MODE_OFF {
                do_block_menu_popup();
            } else {
                show_help_screen();
            }
        }
        KEY_ESC => {
            if get_block_mode() != BLOCK_MODE_OFF {
                cancel_block();
            } else {
                show_splash_screen();
            }
        }
        KEY_CTRL_Q => {
            let res = modal_confirm_save_changes();
            if res != MODAL_RES_CANCEL {
                set_exit_flag(1);
            } else {
                render_all_lines();
            }
        }
        KEY_TAB => {
            if get_block_mode() == BLOCK_MODE_SELECTING {
                cancel_block();
                render_status_bar();
                locate_cursor();
            } else {
                if get_block_mode() == BLOCK_MODE_SOLIDIFIED {
                    cancel_block();
                }
                insert_char(b'\t');
            }
        }
        _ => {
            if (0x20..=0x7E).contains(&k) {
                if get_block_mode() == BLOCK_MODE_SELECTING {
                    cancel_block();
                    render_status_bar();
                    locate_cursor();
                } else {
                    if get_block_mode() == BLOCK_MODE_SOLIDIFIED {
                        cancel_block();
                    }
                    insert_char(k);
                }
            }
        }
    }
}
