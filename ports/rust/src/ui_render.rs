/*
 * ui_render.rs - Viewport, Universal Status Bar, and Tier 1 Workspaces
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 4, 5, 7 and golden SE.COM.
 */

use crate::block::*;
use crate::buffer::*;
use crate::config::*;
use crate::editor::*;
use crate::file_io::*;
use crate::hal_linux::*;
use crate::plugin_mgr::*;
use crate::ui_browser::*;
use crate::ui_modal::*;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

static ACTIVE_ROWS: AtomicU8 = AtomicU8::new(ROWS_24);
static ACTIVE_COLS: AtomicU8 = AtomicU8::new(COLS_80);
static ACTIVE_TEXT_ROWS: AtomicU8 = AtomicU8::new(TEXT_ROWS_24);
static IS_SPLASH_SCREEN: AtomicU8 = AtomicU8::new(1);
static EXIT_FLAG: AtomicU8 = AtomicU8::new(0);
static RESIZE_PENDING: AtomicBool = AtomicBool::new(false);

pub fn get_active_dims() -> (u8, u8) {
    (
        ACTIVE_ROWS.load(Ordering::Relaxed),
        ACTIVE_COLS.load(Ordering::Relaxed),
    )
}

pub fn get_active_dims_with_text() -> (u8, u8, u8) {
    (
        ACTIVE_ROWS.load(Ordering::Relaxed),
        ACTIVE_COLS.load(Ordering::Relaxed),
        ACTIVE_TEXT_ROWS.load(Ordering::Relaxed),
    )
}

pub fn set_active_dims(rows: u8, cols: u8) {
    ACTIVE_ROWS.store(rows, Ordering::Relaxed);
    ACTIVE_COLS.store(cols, Ordering::Relaxed);
    ACTIVE_TEXT_ROWS.store(rows.saturating_sub(1), Ordering::Relaxed);
}

pub fn get_is_splash_screen() -> u8 {
    IS_SPLASH_SCREEN.load(Ordering::Relaxed)
}

pub fn set_is_splash_screen(val: u8) {
    IS_SPLASH_SCREEN.store(val, Ordering::Relaxed);
}

pub fn get_exit_flag() -> u8 {
    EXIT_FLAG.load(Ordering::Relaxed)
}

pub fn set_exit_flag(val: u8) {
    EXIT_FLAG.store(val, Ordering::Relaxed);
}

pub fn get_resize_pending() -> bool {
    RESIZE_PENDING.load(Ordering::Relaxed)
}

pub fn set_resize_pending(val: bool) {
    RESIZE_PENDING.store(val, Ordering::Relaxed);
}

pub fn clear_screen() {
    hal_console_set_attr(ATTR_NORMAL);
    hal_console_clear();
}

pub fn locate_cursor() {
    if get_is_splash_screen() != 0 {
        return;
    }
    let (active_rows, active_cols, active_text_rows) =
        get_active_dims_with_text();
    let (cur_row, view_top_row, view_left_col) = {
        let b = buf_state().lock().unwrap();
        (b.cur_row, b.view_top_row, b.view_left_col)
    };

    let mut screen_row = 1i32 + (cur_row as i32 - view_top_row as i32);
    if screen_row < 1 {
        screen_row = 1;
    }
    if screen_row > active_text_rows as i32 {
        screen_row = active_text_rows as i32;
    }

    let vis_col = calc_visual_col();
    let mut screen_col = 1i32 + (vis_col as i32 - view_left_col as i32);
    if screen_col < 1 {
        screen_col = 1;
    }
    if screen_col > active_cols as i32 {
        screen_col = active_cols as i32;
    }
    let _ = active_rows;
    hal_console_locate(screen_row as u8, screen_col as u8);
}

pub fn render_line(doc_row: usize) {
    let (_, active_cols, active_text_rows) = get_active_dims_with_text();
    let (view_top_row, view_left_col, tot_lines) = {
        let b = buf_state().lock().unwrap();
        (b.view_top_row, b.view_left_col, b.lines.len())
    };

    if doc_row < view_top_row {
        return;
    }
    let rel = doc_row - view_top_row;
    if rel >= active_text_rows as usize {
        return;
    }
    let screen_row = (rel + 1) as u8;
    hal_console_locate(screen_row, 1);

    if doc_row >= tot_lines {
        hal_console_set_attr(ATTR_NORMAL);
        hal_console_putc(b'~');
        hal_console_clear_eol();
        return;
    }

    let text = get_line_bytes(doc_row);
    let len = text.len();
    let mut tab_w = get_config().tab_width as usize;
    if tab_w == 0 {
        tab_w = 8;
    }

    let max_vis = active_cols as usize;
    let pan_left = view_left_col;
    let mut vis_col = 0usize;
    let mut printed = 0usize;
    let mut in_inv = false;
    let row_in_blk = is_line_in_block(doc_row) != 0;

    for i in 0..len {
        if printed >= max_vis {
            break;
        }
        let ch = text[i];
        let char_inv = row_in_blk && (is_char_in_block(doc_row, i) != 0);

        if char_inv && !in_inv {
            hal_console_set_attr(ATTR_INVERSE);
            in_inv = true;
        } else if !char_inv && in_inv {
            hal_console_set_attr(ATTR_NORMAL);
            in_inv = false;
        }

        if ch == b'\t' {
            let spaces = tab_w - (vis_col % tab_w);
            for _ in 0..spaces {
                if vis_col >= pan_left && printed < max_vis {
                    hal_console_putc(b' ');
                    printed += 1;
                }
                vis_col += 1;
            }
        } else {
            if vis_col >= pan_left && printed < max_vis {
                let out_ch = if (0x20..=0x7E).contains(&ch) {
                    ch
                } else {
                    b'.'
                };
                hal_console_putc(out_ch);
                printed += 1;
            }
            vis_col += 1;
        }
    }

    if in_inv {
        hal_console_set_attr(ATTR_NORMAL);
    }
    if printed < max_vis {
        hal_console_clear_eol();
    }
}

pub fn render_all_lines() {
    let (_, _, active_text_rows) = get_active_dims_with_text();
    let view_top_row = buf_state().lock().unwrap().view_top_row;
    for r in 0..active_text_rows as usize {
        render_line(view_top_row + r);
    }
    render_status_bar();
    locate_cursor();
}

pub fn render_status_bar() {
    let (active_rows, active_cols) = get_active_dims();
    let cfg = get_config();

    let (
        cur_name,
        file_modified,
        is_loading,
        file_format,
        view_left_col,
        insert_mode,
        cur_row,
        tot_lines,
    ) = {
        let b = buf_state().lock().unwrap();
        (
            b.current_filename.clone(),
            b.file_modified,
            b.is_loading_file,
            b.file_format,
            b.view_left_col,
            b.insert_mode,
            b.cur_row,
            b.lines.len(),
        )
    };

    let base_name = if cur_name.is_empty() {
        "(Untitled)"
    } else {
        cur_name.rsplit('/').next().unwrap_or(&cur_name)
    };

    let mut raw_name = String::from(base_name);
    if file_modified != 0 {
        if raw_name.len() > 13 {
            raw_name.truncate(13);
        }
        raw_name.push('*');
    } else if raw_name.len() > 14 {
        raw_name.truncate(14);
    }

    let geom_str = if cfg.screen_mode == MODE_120X40 {
        String::from("120x40")
    } else if cfg.screen_mode == MODE_80X24 {
        String::from(" 80x24")
    } else {
        format!("{:>3}x{:<2}", active_cols, active_rows)
    };

    let fmt_str = if is_loading != 0 {
        "     "
    } else if file_format == FMT_CPM {
        "CP/M "
    } else {
        "Linux"
    };

    let blk_mode = get_block_mode();
    let field4 = if get_is_splash_screen() != 0 {
        format!("Free: {} KB", hal_storage_get_free_kb())
    } else if blk_mode == BLOCK_MODE_SELECTING {
        let (sr, sc, er, ec) = get_norm_bounds();
        if sr == er {
            let chars = ec.saturating_sub(sc);
            format!(
                "Sel: {} {}",
                chars,
                if chars == 1 { "char" } else { "chars" }
            )
        } else {
            let lines = (er - sr) + 1;
            format!(
                "Sel: {} {}",
                lines,
                if lines == 1 { "line" } else { "lines" }
            )
        }
    } else if blk_mode == BLOCK_MODE_SOLIDIFIED {
        let (sr, sc, er, ec) = get_norm_bounds();
        if sr == er {
            let chars = ec.saturating_sub(sc);
            if chars == 1 {
                String::from("Block: 1 char")
            } else if chars >= 100 {
                format!("Block: {}c", chars)
            } else {
                format!("Block: {} chars", chars)
            }
        } else {
            let lines = (er - sr) + 1;
            if lines == 1 {
                String::from("Block: 1 line")
            } else if lines >= 100 {
                format!("Block: {}L", lines)
            } else {
                format!("Block: {} lines", lines)
            }
        }
    } else if view_left_col > 0 {
        format!("[Pan +{}]", view_left_col)
    } else if insert_mode == 0 {
        String::from("Overwrite mode")
    } else {
        String::from("^K: Editor keys")
    };

    let vis_col = calc_visual_col().min(999);
    let cur_line = (cur_row + 1).min(9999);
    let tot_disp = tot_lines.max(1).min(9999);

    let field5 = if is_loading != 0 {
        String::from("Line    1/---- Col   0")
    } else {
        format!("Line {:>4}/{:<4} Col {:<3}", cur_line, tot_disp, vis_col)
    };

    let core = format!(
        "| {:<14.14} | {:<6.6} | {} | {:<15.15} | {:<22.22} |",
        raw_name, geom_str, fmt_str, field4, field5
    );

    let cols = active_cols as usize;
    let core_len = core.len();
    let left_pad = if cols > core_len {
        (cols - core_len) / 2
    } else {
        0
    };
    let right_pad = cols.saturating_sub(core_len + left_pad);

    let mut full_bar = String::with_capacity(cols);
    for _ in 0..left_pad {
        full_bar.push(' ');
    }
    if core_len <= cols {
        full_bar.push_str(&core);
    } else {
        full_bar.push_str(&core[..cols]);
    }
    for _ in 0..right_pad {
        full_bar.push(' ');
    }

    hal_console_locate(active_rows, 1);
    hal_console_set_attr(ATTR_INVERSE);
    hal_console_puts(&full_bar);
    hal_console_set_attr(ATTR_NORMAL);
}

pub fn render_centered_text_block(lines: &[&str], block_width: u8) {
    let (active_rows, active_cols) = get_active_dims();
    let avail_rows = active_rows.saturating_sub(1) as usize;
    let line_count = lines.len();
    let top_row = if avail_rows > line_count {
        ((avail_rows - line_count) / 2) + 1
    } else {
        1
    };
    let avail_cols = active_cols.saturating_sub(1) as usize;
    let bw = block_width as usize;
    let left_pad = if avail_cols > bw {
        (avail_cols - bw) / 2
    } else {
        0
    };

    hal_console_set_attr(ATTR_NORMAL);
    for r in 1..active_rows as usize {
        hal_console_locate(r as u8, 1);
        hal_console_putc(b'~');
        if r >= top_row && r < top_row + line_count {
            let line = lines[r - top_row];
            if !line.is_empty() {
                for _ in 0..left_pad {
                    hal_console_putc(b' ');
                }
                hal_console_puts(line);
            }
        }
        hal_console_clear_eol();
    }
    render_status_bar();
}

pub fn show_splash_screen() {
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);

    let mut need_render = true;
    loop {
        if get_resize_pending() {
            set_resize_pending(false);
            clear_screen();
            editor_sync_geometry();
            need_render = true;
        }

        if need_render {
            let cfg = get_config();
            let (active_rows, active_cols) = get_active_dims();
            let screen_line = if cfg.screen_mode == MODE_80X24 {
                String::from("  Active Screen : [80x24 (Classic Terminal)]")
            } else if cfg.screen_mode == MODE_120X40 {
                String::from("  Active Screen : [120x40 (Modern Default)]")
            } else {
                format!(
                    "  Active Screen : [{}x{} (Native Terminal)]",
                    active_cols, active_rows
                )
            };

            let ram_val = match cfg.ramdrive_mode {
                RAMDRV_MODE_OVERWRITE => "Overwrite (Scratch)",
                RAMDRV_MODE_HIBERNATE => "Hibernate (Backed)",
                RAMDRV_MODE_DISABLED => "Disabled (TPA Only)",
                _ => "Preserved (Active)",
            };
            let ram_line = format!("  RAM Drive (A:): [{}]", ram_val);

            let plug_val = if cfg.plugin_mode == PLUGIN_MODE_DISABLED {
                "Disabled"
            } else {
                "Operational"
            };
            let plug_line = format!("  Plugin System : [{}]", plug_val);

            let max_val = if cfg.lines_mode != 0 {
                "32,768 lines"
            } else {
                "16,384 lines"
            };
            let lines_line = format!("  Max Lines     : [{}]", max_val);

            let splash_lines: [&str; 21] = [
                "                SE - Screen Editor                ",
                "",
                "SE is freely distributable under the MIT License",
                "",
                "  type   [E]  or  [Enter] to edit",
                "  type   [O]  or  [^O]    to open a file",
                "  type   [S]  or  [^S]    to save a file",
                "  type   [U]              for memory usage",
                "  type   [C]              for configuration",
                "  type   [P]  or  [^P]    for plugins",
                "  type   [1]              set 80x24",
                "  type   [2]              set 120x40",
                "  type   [3]              set native",
                "  type   [H]  or  [?]     for help",
                "  type   [A]              for about",
                "  type   [Q]  or  [^Q]    to exit",
                "",
                &screen_line,
                &ram_line,
                &plug_line,
                &lines_line,
            ];

            render_centered_text_block(&splash_lines, 50);
            need_render = false;
        }

        let mut k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == b':' {
            let mut k2 = hal_keyboard_get_key();
            while k2 == 0 {
                k2 = hal_keyboard_get_key();
            }
            k = k2;
        }

        if k == b'e' || k == b'E' || k == KEY_ENTER {
            set_is_splash_screen(0);
            hal_console_set_cursor_vis(1);
            render_all_lines();
            return;
        } else if k == b'1' {
            clear_screen();
            set_config(|c| c.screen_mode = MODE_80X24);
            editor_sync_geometry();
            need_render = true;
        } else if k == b'2' {
            clear_screen();
            set_config(|c| c.screen_mode = MODE_120X40);
            editor_sync_geometry();
            need_render = true;
        } else if k == b'3' {
            clear_screen();
            set_config(|c| c.screen_mode = MODE_NATIVE);
            editor_sync_geometry();
            need_render = true;
        } else if k == b'q' || k == b'Q' || k == KEY_CTRL_Q {
            let res = modal_confirm_save_changes();
            if res != MODAL_RES_CANCEL {
                set_exit_flag(1);
                return;
            }
            need_render = true;
        } else if k == b'h'
            || k == b'H'
            || k == b'?'
            || k == KEY_CTRL_K
        {
            show_help_screen();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b'u' || k == b'U' {
            show_mem_info_screen();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b'c' || k == b'C' {
            show_config_screen();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b'a' || k == b'A' {
            show_about_screen();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b'p' || k == b'P' {
            plugin_manager_ui();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == KEY_CTRL_P {
            show_plugin_palette();
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b'o' || k == b'O' || k == KEY_CTRL_O {
            let res = modal_confirm_save_changes();
            if res != MODAL_RES_CANCEL {
                if let Some(fname) = ui_browser_open_dialog() {
                    if file_load(&fname) == 0 {
                        set_is_splash_screen(0);
                        hal_console_set_cursor_vis(1);
                        render_all_lines();
                        return;
                    }
                }
            }
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        } else if k == b's' || k == b'S' || k == KEY_CTRL_S {
            if let Some(fname) = ui_browser_save_dialog() {
                let (cr, _) = get_cur_pos();
                pack_line(cr);
                let fmt = buf_state().lock().unwrap().file_format;
                let _ = file_save(Some(&fname), fmt);
            }
            set_is_splash_screen(1);
            hal_console_set_cursor_vis(0);
            need_render = true;
        }
    }
}

const HELP_LINES: [&str; 22] = [
    "               SE - EDITOR MODE KEYS                ",
    "               ---------------------                ",
    "",
    "  Cursor Navigation:",
    "    Arrow Keys      : Move Cursor Up / Down / Left / Right",
    "    Ctrl+A / Home   : Beginning of Line",
    "    Ctrl+E / End    : End of Line",
    "    Ctrl+U / PgUp   : Page Up",
    "    Ctrl+V / PgDn   : Page Down",
    "    Ctrl+T          : Top of Document (First Line)",
    "    Ctrl+G          : Bottom of Document (Last Line)",
    "    Ctrl+L          : Goto Line Number...",
    "",
    "  Editing & File Commands:",
    "    Insert          : Toggle Insert / Overwrite Mode",
    "    Backspace       : Delete char left / Cancel selection",
    "    Delete / Ctrl+D : Delete char right / Delete block",
    "    Ctrl+B          : Start selection (Enter to solidify)",
    "    Ctrl+C / Ctrl+X : Copy/Move solidified block",
    "    Ctrl+F / Ctrl+N : Find String / Find Next",
    "    Ctrl+R / Ctrl+P : Replace / Context Plugin",
    "    Ctrl+S / Ctrl+O : Save File/Block / Open/Insert File",
];

pub fn show_help_screen() {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);
    render_centered_text_block(&HELP_LINES, 58);

    let (active_rows, active_cols) = get_active_dims();
    let avail_rows = active_rows.saturating_sub(1);
    let prompt = "Press any key to continue";
    let p_col =
        (((active_cols as usize).saturating_sub(prompt.len())) / 2 + 1) as u8;
    hal_console_locate(avail_rows, p_col);
    hal_console_set_attr(ATTR_INVERSE);
    hal_console_puts(prompt);
    hal_console_set_attr(ATTR_NORMAL);

    while hal_keyboard_get_key() == 0 {}
    set_is_splash_screen(prev_splash);
    hal_console_set_cursor_vis(1);
    if prev_splash == 0 {
        render_all_lines();
    }
}

const ABOUT_LINES: [&str; 9] = [
    "                  SE - Screen Editor                  ",
    "            version 1.1.0 (2026-10-09) (Rust)         ",
    "                   by Dean Jenkins                    ",
    "",
    "   Google Antigravity 2.19.1 & Gemini FLASH 3.8 high  ",
    "                  created the code                    ",
    "      Open source software under the MIT License      ",
    "",
    "              Press any key to continue               ",
];

pub fn show_about_screen() {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);
    render_centered_text_block(&ABOUT_LINES, 54);
    while hal_keyboard_get_key() == 0 {}
    set_is_splash_screen(prev_splash);
    hal_console_set_cursor_vis(1);
    if prev_splash == 0 {
        render_all_lines();
    }
}

pub fn show_mem_info_screen() {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);
    let tot = get_total_lines();
    let max_lines = buf_state().lock().unwrap().max_doc_lines;
    let line_buf = format!(
        "  Active Document Lines : {} / {}",
        tot, max_lines
    );
    let free_buf = format!(
        "  Available Memory      : {} KB (Virtual Heap)",
        hal_storage_get_free_kb()
    );
    let mem_lines: [&str; 9] = [
        "            SE - Memory Usage & Capacity            ",
        "            ----------------------------            ",
        "",
        "  Platform Profile      : Linux Native (POSIX)      ",
        &line_buf,
        "  Max Line Width        : 1000 characters           ",
        &free_buf,
        "",
        "             Press any key to return...             ",
    ];
    render_centered_text_block(&mem_lines, 52);
    while hal_keyboard_get_key() == 0 {}
    set_is_splash_screen(prev_splash);
    hal_console_set_cursor_vis(1);
    if prev_splash == 0 {
        render_all_lines();
    }
}

pub fn show_config_screen() {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);

    loop {
        let cfg = get_config();
        let status_line = if cfg.config_loaded != 0 {
            "  Config Status: Loaded from SE.CFG"
        } else {
            "  Config Status: Defaults"
        };

        let geom_val = match cfg.screen_mode {
            MODE_80X24 => "80x24",
            MODE_NATIVE => "Native",
            _ => "120x40",
        };
        let geom_line = format!("  1. Screen Geometry  : {}", geom_val);

        let ram_val = match cfg.ramdrive_mode {
            RAMDRV_MODE_OVERWRITE => "Overwrite",
            RAMDRV_MODE_HIBERNATE => "Hibernate",
            RAMDRV_MODE_DISABLED => "Disabled",
            _ => "Protected",
        };
        let ram_line = format!("  2. RAM Drive Mode   : {}", ram_val);

        let lines_val = if cfg.lines_mode != 0 { "32K" } else { "16K" };
        let lines_line = format!("  3. Max Doc Lines    : {}", lines_val);

        let tab_line = format!("  4. Tab Width        : {}", cfg.tab_width);

        let plug_val = match cfg.plugin_mode {
            PLUGIN_MODE_ONDEMAND => "Demand",
            PLUGIN_MODE_DISABLED => "Disabled",
            _ => "Autoload",
        };
        let plug_line = format!("  5. Plugin Manager   : {}", plug_val);

        let cfg_lines: [&str; 12] = [
            "            SE - Configuration Manager            ",
            "            --------------------------            ",
            "",
            status_line,
            "",
            &geom_line,
            &ram_line,
            &lines_line,
            &tab_line,
            &plug_line,
            "",
            "  [1-5]=Toggle Option  [S]=Save Config  [ESC]=Exit",
        ];

        render_centered_text_block(&cfg_lines, 52);

        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ESC || k == KEY_ENTER || k == b'q' || k == b'Q' {
            break;
        }
        if k == b'1' {
            clear_screen();
            set_config(|c| {
                c.screen_mode = match c.screen_mode {
                    MODE_80X24 => MODE_120X40,
                    MODE_120X40 => MODE_NATIVE,
                    _ => MODE_80X24,
                };
            });
            editor_sync_geometry();
        } else if k == b'2' {
            set_config(|c| {
                c.ramdrive_mode = (c.ramdrive_mode + 1) % 4;
            });
        } else if k == b'3' {
            set_config(|c| {
                c.lines_mode = if c.lines_mode != 0 { 0 } else { 1 };
            });
        } else if k == b'4' {
            set_config(|c| {
                c.tab_width = if c.tab_width == 4 { 8 } else { 4 };
            });
        } else if k == b'5' {
            set_config(|c| {
                c.plugin_mode = (c.plugin_mode + 1) % 3;
            });
        } else if k == b's' || k == b'S' {
            let _ = config_save();
        }
    }

    set_is_splash_screen(prev_splash);
    hal_console_set_cursor_vis(1);
    if prev_splash == 0 {
        render_all_lines();
    }
}
