/*
 * main.rs - Linux Native Rust Profile entry point for SE (se-rs)
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md and golden SE.COM.
 */

mod beautify;
mod block;
mod buffer;
mod config;
mod editor;
mod file_io;
mod hal_linux;
mod plugin_mgr;
mod search;
mod ui_browser;
mod ui_modal;
mod ui_render;

use crate::buffer::*;
use crate::config::*;
use crate::editor::*;
use crate::file_io::*;
use crate::hal_linux::*;
use crate::ui_render::*;
use std::env;

fn print_usage(prog: &str) {
    println!(
        "SE.COM {} - Screen Editor (Linux Native Profile)",
        SE_VERSION_STR
    );
    println!("Usage: {} [options] [filename]", prog);
    println!("Options:");
    println!("  --config <file>   Load configuration from specified file");
    println!("  --help, -h        Display this help message");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let prog = args.first().map(|s| s.as_str()).unwrap_or("se-rs");

    let mut cfg_path: Option<String> = None;
    let mut file_path: Option<String> = None;

    let mut i = 1usize;
    while i < args.len() {
        let arg = &args[i];
        if arg == "--help" || arg == "-h" {
            print_usage(prog);
            return;
        } else if arg == "--config" && i + 1 < args.len() {
            cfg_path = Some(args[i + 1].clone());
            i += 1;
        } else if !arg.starts_with('-') {
            file_path = Some(arg.clone());
        }
        i += 1;
    }

    config_init_defaults();
    if let Some(ref cp) = cfg_path {
        let _ = config_load_file(cp);
    } else {
        let _ = config_load();
    }

    buffer_init();
    hal_console_init();
    editor_init();

    if let Some(ref fp) = file_path {
        let _ = file_load(fp);
        set_is_splash_screen(0);
        clear_screen();
        render_all_lines();
    } else {
        clear_screen();
        show_splash_screen();
    }

    while get_exit_flag() == 0 {
        if get_resize_pending() {
            set_resize_pending(false);
            clear_screen();
            editor_sync_geometry();
            if get_is_splash_screen() != 0 {
                show_splash_screen();
            } else {
                render_all_lines();
            }
        }

        let k = hal_keyboard_get_key();
        if k != 0 {
            editor_handle_key(k);
        }
    }

    hal_console_cleanup();
}
