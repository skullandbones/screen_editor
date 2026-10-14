/*
 * plugin_mgr.rs - Built-in plugins, Archetype D Plugin Palette, and Manager
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 8.4 and Section 12.
 */

use crate::beautify::*;
use crate::buffer::*;
use crate::config::*;
use crate::hal_linux::*;
use crate::ui_modal::*;
use crate::ui_render::*;

fn run_rot13_line() {
    let mut b = buf_state().lock().unwrap();
    for ch in &mut b.active_line_buf {
        if *ch >= b'a' && *ch <= b'z' {
            *ch = b'a' + ((*ch - b'a' + 13) % 26);
        } else if *ch >= b'A' && *ch <= b'Z' {
            *ch = b'A' + ((*ch - b'A' + 13) % 26);
        }
    }
    b.active_line_dirty = 1;
    b.file_modified = 1;
    let cr = b.cur_row;
    drop(b);
    pack_line(cr);
}

fn run_wordcount() {
    let (cr, _) = get_cur_pos();
    pack_line(cr);
    let tot = get_total_lines();
    let mut words = 0usize;
    let mut chars = 0usize;

    for r in 0..tot {
        let line = get_line_bytes(r);
        chars += line.len();
        let mut in_word = false;
        for &c in &line {
            if c == b' ' || c == b'\t' {
                in_word = false;
            } else if !in_word {
                in_word = true;
                words += 1;
            }
        }
    }

    let msg = format!(
        "Lines: {}  Words: {}  Chars: {}",
        tot, words, chars
    );
    modal_alert("Document Statistics", &msg, "");
}

const PALETTE_ITEMS: [&str; 3] = [
    "1. ROT13    - Cipher Active Line",
    "2. WORDCNT  - Document Word Count",
    "3. BEAUTIFY - Format Z80/C Source",
];

pub fn show_plugin_palette() {
    let (active_rows, active_cols) = get_active_dims();
    let width: u8 = 50;
    let height: u8 = 9;
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

    modal_draw_frame(top, left, width, height, "Plugin Palette");
    hal_console_locate(top + 3, left + 3);
    hal_console_puts("Select a plugin to execute:");

    let footer = "[Up/Down]=Select  [Enter]=Run  [ESC]=Cancel";
    let inner_w = (width - 2) as usize;
    let f_pad = (inner_w.saturating_sub(footer.len())) / 2;
    hal_console_locate(top + 7, left + 1 + f_pad as u8);
    hal_console_puts(footer);

    let mut sel = 0usize;
    hal_console_set_cursor_vis(0);

    loop {
        for i in 0..3 {
            hal_console_locate(top + 4 + i as u8, left + 3);
            if i == sel {
                hal_console_set_attr(ATTR_INVERSE);
                hal_console_puts("> ");
            } else {
                hal_console_set_attr(ATTR_NORMAL);
                hal_console_puts("  ");
            }
            hal_console_puts(&format!("{:<40}", PALETTE_ITEMS[i]));
            hal_console_set_attr(ATTR_NORMAL);
        }

        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }
        if k == KEY_ESC {
            hal_console_set_cursor_vis(1);
            if get_is_splash_screen() == 0 {
                render_all_lines();
            }
            return;
        }
        if k == KEY_UP {
            sel = if sel > 0 { sel - 1 } else { 2 };
        } else if k == KEY_DOWN || k == KEY_TAB {
            sel = (sel + 1) % 3;
        } else if k == b'1' {
            sel = 0;
            break;
        } else if k == b'2' {
            sel = 1;
            break;
        } else if k == b'3' {
            sel = 2;
            break;
        } else if k == KEY_ENTER {
            break;
        }
    }

    hal_console_set_cursor_vis(1);
    if sel == 0 {
        run_rot13_line();
        if get_is_splash_screen() == 0 {
            render_all_lines();
        }
    } else if sel == 1 {
        if get_is_splash_screen() == 0 {
            render_all_lines();
        }
        run_wordcount();
    } else if sel == 2 {
        beautify_buffer();
    }
}

const PLUG_LINES: [&str; 12] = [
    "            SE.COM - Modular Plugin Manager           ",
    "            -------------------------------           ",
    "",
    "  Slot 1 (4KB)  : ROT13     [Built-in: Line ROT13]    ",
    "  Slot 2 (4KB)  : WORDCNT   [Built-in: Word Count]    ",
    "  Slot 3 (16KB) : BEAUTIFY  [Built-in: Code Format]   ",
    "  Slot 4 (32KB) : (Empty)                             ",
    "",
    "  [1] Run ROT13 on Active Line                        ",
    "  [2] Run Document Word Count                         ",
    "  [3] Run Code Beautifier (^Y)                        ",
    "  [ESC] Return to Editor                              ",
];

pub fn plugin_manager_ui() {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    hal_console_set_cursor_vis(0);
    render_centered_text_block(&PLUG_LINES, 54);
    loop {
        let k = hal_keyboard_get_key();
        if k == KEY_ESC || k == KEY_ENTER || k == b'q' || k == b'Q' {
            break;
        }
        if k == b'1' {
            run_rot13_line();
            break;
        }
        if k == b'2' {
            set_is_splash_screen(prev_splash);
            hal_console_set_cursor_vis(1);
            if prev_splash == 0 {
                render_all_lines();
            }
            run_wordcount();
            return;
        }
        if k == b'3' {
            set_is_splash_screen(prev_splash);
            hal_console_set_cursor_vis(1);
            beautify_buffer();
            return;
        }
    }
    set_is_splash_screen(prev_splash);
    hal_console_set_cursor_vis(1);
    if prev_splash == 0 {
        render_all_lines();
    }
}
