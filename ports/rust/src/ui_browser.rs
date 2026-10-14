/*
 * ui_browser.rs - Tier 1 Full-Screen File Open, Insert, Save, and Save Block
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md Section 7.5-7.10 and golden SE.COM.
 */

use crate::buffer::*;
use crate::config::*;
use crate::hal_linux::*;
use crate::ui_modal::*;
use crate::ui_render::*;

const BROWSER_MODE_OPEN: u8 = 0;
const BROWSER_MODE_SAVE: u8 = 1;
const BROWSER_MODE_INSERT: u8 = 2;
const BROWSER_MODE_SAVE_BLOCK: u8 = 3;

const GRID_WIDTH: usize = 70;
const GRID_COLS: usize = 5;
const GRID_CELL_W: usize = 14;
const GRID_ROWS: usize = 12;
const PAGE_ITEMS: usize = GRID_COLS * GRID_ROWS;
const INPUT_FIELD_MAX: usize = 20;
const MAX_BROWSER_FILES: usize = 256;

fn match_wildcard(pattern: &[u8], text: &[u8]) -> bool {
    let mut pi = 0usize;
    let mut ti = 0usize;
    let mut star_p: Option<usize> = None;
    let mut star_t = 0usize;

    while ti < text.len() {
        if pi < pattern.len()
            && (pattern[pi] == b'?'
                || pattern[pi].eq_ignore_ascii_case(&text[ti]))
        {
            pi += 1;
            ti += 1;
        } else if pi < pattern.len() && pattern[pi] == b'*' {
            star_p = Some(pi);
            pi += 1;
            star_t = ti;
        } else if let Some(sp) = star_p {
            pi = sp + 1;
            star_t += 1;
            ti = star_t;
        } else {
            return false;
        }
    }
    while pi < pattern.len() && pattern[pi] == b'*' {
        pi += 1;
    }
    pi == pattern.len()
}

fn is_filter_spec(input: &str) -> bool {
    if input.is_empty() {
        return false;
    }
    if input.contains('*') || input.contains('?') {
        return true;
    }
    let bytes = input.as_bytes();
    if bytes.len() == 2 && bytes[1] == b':' {
        return true;
    }
    if bytes.len() >= 2 && bytes.len() <= 3 && bytes[bytes.len() - 1] == b':' {
        let mut all_digits = true;
        for &b in &bytes[..bytes.len() - 1] {
            if !b.is_ascii_digit() {
                all_digits = false;
                break;
            }
        }
        if all_digits {
            return true;
        }
    }
    false
}

fn scan_filtered_files(filter_spec: &str) -> Vec<String> {
    let raw_list = hal_storage_list_dir(".", MAX_BROWSER_FILES);
    let mut pat = filter_spec;
    while let Some(idx) = pat.find(':') {
        pat = &pat[idx + 1..];
    }
    if pat.is_empty() || pat == "*.*" || pat == "*" {
        return raw_list;
    }
    let pat_bytes = pat.as_bytes();
    raw_list
        .into_iter()
        .filter(|name| match_wildcard(pat_bytes, name.as_bytes()))
        .collect()
}

fn render_browser_prompt(
    top_row: u8,
    left_pad: usize,
    mode: u8,
    input_buf: &[u8],
    input_pos: usize,
    focus_grid: bool,
) {
    let prompt_lbl = match mode {
        BROWSER_MODE_SAVE => "  Enter filename to save: [",
        BROWSER_MODE_SAVE_BLOCK => "  Save block as filename: [",
        BROWSER_MODE_INSERT => "  Insert file at cursor:  [",
        _ => "  Enter filename to open: [",
    };

    let mut prompt_line = String::from(prompt_lbl);
    let mut scroll_off = 0usize;
    if input_pos >= INPUT_FIELD_MAX {
        scroll_off = input_pos - INPUT_FIELD_MAX + 1;
    }
    for i in 0..INPUT_FIELD_MAX {
        let idx = scroll_off + i;
        if idx < input_buf.len() {
            prompt_line.push(input_buf[idx] as char);
        } else {
            prompt_line.push(' ');
        }
    }
    prompt_line.push(']');

    hal_console_locate(top_row + 19, 1);
    hal_console_putc(b'~');
    for _ in 0..left_pad {
        hal_console_putc(b' ');
    }
    hal_console_puts(&prompt_line);
    hal_console_clear_eol();

    if focus_grid {
        hal_console_set_cursor_vis(0);
    } else {
        let prompt_col =
            (2 + left_pad + 27 + (input_pos - scroll_off)) as u8;
        hal_console_locate(top_row + 19, prompt_col);
        hal_console_set_cursor_vis(1);
    }
}

struct PrevBrowserGuard {
    prev_splash: u8,
}

impl Drop for PrevBrowserGuard {
    fn drop(&mut self) {
        set_is_splash_screen(self.prev_splash);
    }
}

fn ui_browser_workspace(mode: u8) -> Option<String> {
    let prev_splash = get_is_splash_screen();
    set_is_splash_screen(1);
    let _guard = PrevBrowserGuard { prev_splash };

    let mut filter_spec = String::from("*.*");
    let mut files = scan_filtered_files(&filter_spec);

    let mut input_buf: Vec<u8> = Vec::new();
    let mut input_pos: usize = 0;

    if mode == BROWSER_MODE_SAVE {
        let cur_name = buf_state().lock().unwrap().current_filename.clone();
        if !cur_name.is_empty() {
            let base = cur_name
                .rsplit('/')
                .next()
                .unwrap_or(&cur_name)
                .as_bytes();
            let copy_len = base.len().min(MAX_FILENAME_LEN - 1);
            input_buf.extend_from_slice(&base[..copy_len]);
            input_pos = input_buf.len();
        }
    }

    let mut cur_page: usize = 0;
    let mut grid_sel: usize = 0;
    let mut focus_grid = false;
    let mut need_full_render = true;

    let double_rule = "=".repeat(GRID_WIDTH - 1);
    let single_rule = "-".repeat(GRID_WIDTH - 1);

    let title = match mode {
        BROWSER_MODE_SAVE => "SAVE FILE (DIRECTORY)",
        BROWSER_MODE_SAVE_BLOCK => "SAVE BLOCK (DIRECTORY)",
        BROWSER_MODE_INSERT => "INSERT FILE (DIRECTORY)",
        _ => "OPEN FILE (DIRECTORY)",
    };

    loop {
        let total_pages = if files.is_empty() {
            1
        } else {
            (files.len() + PAGE_ITEMS - 1) / PAGE_ITEMS
        };
        if cur_page >= total_pages {
            cur_page = total_pages - 1;
        }

        let (active_rows, active_cols) = get_active_dims();
        let avail_rows = active_rows.saturating_sub(1) as usize;
        let block_h: usize = 22;
        let top_row = if avail_rows > block_h {
            (((avail_rows - block_h) / 2) + 1) as u8
        } else {
            1
        };
        let avail_cols = active_cols.saturating_sub(1) as usize;
        let left_pad = if avail_cols > GRID_WIDTH {
            (avail_cols - GRID_WIDTH) / 2
        } else {
            0
        };

        if need_full_render {
            for r in 1..active_rows {
                hal_console_locate(r, 1);
                hal_console_putc(b'~');
                hal_console_clear_eol();
            }

            hal_console_locate(top_row, 1);
            hal_console_putc(b'~');
            for _ in 0..left_pad {
                hal_console_putc(b' ');
            }
            hal_console_puts(&double_rule);

            hal_console_locate(top_row + 1, 1);
            hal_console_putc(b'~');
            let title_pad = (GRID_WIDTH.saturating_sub(title.len())) / 2;
            for _ in 0..(left_pad + title_pad) {
                hal_console_putc(b' ');
            }
            hal_console_set_attr(ATTR_BOLD);
            hal_console_puts(title);
            hal_console_set_attr(ATTR_NORMAL);

            hal_console_locate(top_row + 2, 1);
            hal_console_putc(b'~');
            for _ in 0..left_pad {
                hal_console_putc(b' ');
            }
            hal_console_puts(&double_rule);

            if files.is_empty() {
                hal_console_locate(top_row + 3, 1);
                hal_console_putc(b'~');
                for _ in 0..left_pad {
                    hal_console_putc(b' ');
                }
                hal_console_puts("  (No matching files found)");
            } else {
                let page_start = cur_page * PAGE_ITEMS;
                for gr in 0..GRID_ROWS {
                    hal_console_locate(top_row + 3 + gr as u8, 1);
                    hal_console_putc(b'~');
                    for _ in 0..left_pad {
                        hal_console_putc(b' ');
                    }
                    hal_console_puts("  ");
                    for gc in 0..GRID_COLS {
                        let idx = page_start + gr * GRID_COLS + gc;
                        if idx < files.len() {
                            if focus_grid && idx == grid_sel {
                                hal_console_set_attr(ATTR_INVERSE);
                            }
                            let fname = &files[idx];
                            let trunc = if fname.len() > GRID_CELL_W {
                                &fname[..GRID_CELL_W]
                            } else {
                                fname
                            };
                            hal_console_puts(&format!(
                                "{:<width$}",
                                trunc,
                                width = GRID_CELL_W
                            ));
                            if focus_grid && idx == grid_sel {
                                hal_console_set_attr(ATTR_NORMAL);
                            }
                        }
                    }
                }
            }

            hal_console_locate(top_row + 17, 1);
            hal_console_putc(b'~');
            for _ in 0..left_pad {
                hal_console_putc(b' ');
            }
            hal_console_puts(&single_rule);

            hal_console_locate(top_row + 18, 1);
            hal_console_putc(b'~');
            for _ in 0..left_pad {
                hal_console_putc(b' ');
            }
            if mode == BROWSER_MODE_SAVE || mode == BROWSER_MODE_SAVE_BLOCK {
                let fmt = buf_state().lock().unwrap().file_format;
                let fmt_lbl = if fmt == FMT_LINUX {
                    "Linux"
                } else {
                    "CP/M"
                };
                let guide = format!(
                    "  [ESC]=Cancel  [d:][u:][pattern] to list  \
                     [^F]=Toggle Format: [{}]",
                    fmt_lbl
                );
                hal_console_puts(&guide);
            } else {
                hal_console_puts(
                    "  [ESC]=Cancel  [d:][u:][pattern] to list \
                     (e.g. B:, *.TXT)",
                );
            }

            if total_pages > 1 {
                hal_console_locate(top_row + 21, 1);
                hal_console_putc(b'~');
                for _ in 0..left_pad {
                    hal_console_putc(b' ');
                }
                let page_str = format!(
                    "  [Page {}/{}]  <PgUp>/<PgDn>=Page",
                    cur_page + 1,
                    total_pages
                );
                hal_console_puts(&page_str);
            }

            render_status_bar();
            need_full_render = false;
        }

        render_browser_prompt(
            top_row,
            left_pad,
            mode,
            &input_buf,
            input_pos,
            focus_grid,
        );

        let k = hal_keyboard_get_key();
        if k == 0 {
            continue;
        }

        if k == KEY_ESC {
            hal_console_set_cursor_vis(1);
            return None;
        }

        if (mode == BROWSER_MODE_SAVE || mode == BROWSER_MODE_SAVE_BLOCK)
            && k == KEY_CTRL_F
        {
            {
                let mut b = buf_state().lock().unwrap();
                b.file_format = if b.file_format == FMT_CPM {
                    FMT_LINUX
                } else {
                    FMT_CPM
                };
            }
            need_full_render = true;
            continue;
        }

        if k == KEY_PGUP || k == KEY_CTRL_U {
            if cur_page > 0 {
                cur_page -= 1;
                grid_sel = cur_page * PAGE_ITEMS;
                need_full_render = true;
            }
            continue;
        }
        if k == KEY_PGDN || k == KEY_CTRL_V {
            if cur_page + 1 < total_pages {
                cur_page += 1;
                grid_sel = cur_page * PAGE_ITEMS;
                need_full_render = true;
            }
            continue;
        }

        if k == KEY_TAB {
            if !files.is_empty() {
                focus_grid = !focus_grid;
                need_full_render = true;
            }
            continue;
        }

        if focus_grid {
            if k == KEY_LEFT {
                if grid_sel > 0 {
                    grid_sel -= 1;
                }
                cur_page = grid_sel / PAGE_ITEMS;
                need_full_render = true;
            } else if k == KEY_RIGHT {
                if grid_sel + 1 < files.len() {
                    grid_sel += 1;
                }
                cur_page = grid_sel / PAGE_ITEMS;
                need_full_render = true;
            } else if k == KEY_UP {
                if grid_sel >= GRID_COLS {
                    grid_sel -= GRID_COLS;
                }
                cur_page = grid_sel / PAGE_ITEMS;
                need_full_render = true;
            } else if k == KEY_DOWN {
                if grid_sel + GRID_COLS < files.len() {
                    grid_sel += GRID_COLS;
                }
                cur_page = grid_sel / PAGE_ITEMS;
                need_full_render = true;
            } else if k == KEY_ENTER {
                let selected = files[grid_sel].clone();
                if mode == BROWSER_MODE_SAVE || mode == BROWSER_MODE_SAVE_BLOCK
                {
                    if hal_storage_file_exists(&selected) != 0 {
                        let ow = modal_confirm_overwrite();
                        if ow != MODAL_RES_YES {
                            need_full_render = true;
                            continue;
                        }
                    }
                }
                hal_console_set_cursor_vis(1);
                return Some(selected);
            } else if (0x20..=0x7E).contains(&k) {
                focus_grid = false;
                if input_buf.len() + 1 < MAX_FILENAME_LEN {
                    input_buf.insert(input_pos, k);
                    input_pos += 1;
                }
                need_full_render = true;
            }
            continue;
        }

        if k == KEY_ENTER {
            if input_buf.is_empty() {
                continue;
            }
            let entered = String::from_utf8_lossy(&input_buf).into_owned();
            if is_filter_spec(&entered) {
                filter_spec = entered;
                files = scan_filtered_files(&filter_spec);
                cur_page = 0;
                grid_sel = 0;
                input_buf.clear();
                input_pos = 0;
                need_full_render = true;
                continue;
            }
            if mode == BROWSER_MODE_OPEN || mode == BROWSER_MODE_INSERT {
                if hal_storage_file_exists(&entered) == 0 {
                    modal_file_not_found(&entered);
                    need_full_render = true;
                    continue;
                }
            } else if mode == BROWSER_MODE_SAVE
                || mode == BROWSER_MODE_SAVE_BLOCK
            {
                if hal_storage_file_exists(&entered) != 0 {
                    let ow = modal_confirm_overwrite();
                    if ow != MODAL_RES_YES {
                        need_full_render = true;
                        continue;
                    }
                }
            }
            hal_console_set_cursor_vis(1);
            return Some(entered);
        }

        if k == KEY_LEFT {
            if input_pos > 0 {
                input_pos -= 1;
            }
        } else if k == KEY_RIGHT {
            if input_pos < input_buf.len() {
                input_pos += 1;
            }
        } else if k == KEY_HOME || k == KEY_CTRL_A {
            input_pos = 0;
        } else if k == KEY_END || k == KEY_CTRL_E {
            input_pos = input_buf.len();
        } else if k == KEY_UP || k == KEY_DOWN {
            if !files.is_empty() {
                focus_grid = true;
                need_full_render = true;
            }
        } else if k == KEY_BS || k == KEY_BS_ALT {
            if input_pos > 0 {
                input_buf.remove(input_pos - 1);
                input_pos -= 1;
            }
        } else if k == KEY_DEL || k == KEY_CTRL_D {
            if input_pos < input_buf.len() {
                input_buf.remove(input_pos);
            }
        } else if (0x20..=0x7E).contains(&k) {
            if input_buf.len() + 1 < MAX_FILENAME_LEN {
                input_buf.insert(input_pos, k);
                input_pos += 1;
            }
        }
    }
}

pub fn ui_browser_open_dialog() -> Option<String> {
    ui_browser_workspace(BROWSER_MODE_OPEN)
}

pub fn ui_browser_save_dialog() -> Option<String> {
    ui_browser_workspace(BROWSER_MODE_SAVE)
}

pub fn ui_browser_insert_dialog() -> Option<String> {
    ui_browser_workspace(BROWSER_MODE_INSERT)
}

pub fn ui_browser_save_block_dialog() -> Option<String> {
    ui_browser_workspace(BROWSER_MODE_SAVE_BLOCK)
}
