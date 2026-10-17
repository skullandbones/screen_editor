/*
 * config.rs - SE.CFG configuration parser and global constants
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 * Adheres strictly to UI_UX_DESIGN.md and golden SE.COM.
 */

use std::fs;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

pub const SE_VERSION_STR: &str = "v1.1.2";

pub const COLS_80: u8 = 80;
pub const ROWS_24: u8 = 24;
pub const TEXT_ROWS_24: u8 = 23;

pub const COLS_120: u8 = 120;
pub const ROWS_40: u8 = 40;

pub const MODE_80X24: u8 = 0;
pub const MODE_120X40: u8 = 1;
pub const MODE_NATIVE: u8 = 2;

pub const MAX_LINE_CHARS: usize = 1000;
pub const MAX_INPUT_LINE_CHARS: usize = 1000;
pub const MAX_FILENAME_LEN: usize = 64;

pub const KEY_CTRL_A: u8 = 0x01;
pub const KEY_CTRL_B: u8 = 0x02;
pub const KEY_CTRL_C: u8 = 0x03;
pub const KEY_CTRL_D: u8 = 0x04;
pub const KEY_CTRL_E: u8 = 0x05;
pub const KEY_CTRL_F: u8 = 0x06;
pub const KEY_CTRL_G: u8 = 0x07;
pub const KEY_TAB: u8 = 0x09;
pub const KEY_CTRL_K: u8 = 0x0B;
pub const KEY_CTRL_L: u8 = 0x0C;
pub const KEY_ENTER: u8 = 0x0D;
pub const KEY_CTRL_N: u8 = 0x0E;
pub const KEY_CTRL_O: u8 = 0x0F;
pub const KEY_CTRL_P: u8 = 0x10;
pub const KEY_CTRL_Q: u8 = 0x11;
pub const KEY_CTRL_R: u8 = 0x12;
pub const KEY_CTRL_S: u8 = 0x13;
pub const KEY_CTRL_T: u8 = 0x14;
pub const KEY_CTRL_U: u8 = 0x15;
pub const KEY_CTRL_V: u8 = 0x16;
pub const KEY_CTRL_W: u8 = 0x17;
pub const KEY_CTRL_X: u8 = 0x18;
pub const KEY_CTRL_Y: u8 = 0x19;
pub const KEY_ESC: u8 = 0x1B;
pub const KEY_BS: u8 = 0x7F;
pub const KEY_BS_ALT: u8 = 0x08;

pub const KEY_UP: u8 = 0x80;
pub const KEY_DOWN: u8 = 0x81;
pub const KEY_LEFT: u8 = 0x82;
pub const KEY_RIGHT: u8 = 0x83;
pub const KEY_HOME: u8 = 0x84;
pub const KEY_END: u8 = 0x85;
pub const KEY_PGUP: u8 = 0x86;
pub const KEY_PGDN: u8 = 0x87;
pub const KEY_DEL: u8 = 0x88;
pub const KEY_INS: u8 = 0x89;

pub const FMT_CPM: u8 = 0;
pub const FMT_LINUX: u8 = 1;

pub const RAMDRV_MODE_OVERWRITE: u8 = 0;
pub const RAMDRV_MODE_PROTECTED: u8 = 1;
pub const RAMDRV_MODE_HIBERNATE: u8 = 2;
pub const RAMDRV_MODE_DISABLED: u8 = 3;

pub const PLUGIN_MODE_AUTOLOAD: u8 = 0;
pub const PLUGIN_MODE_ONDEMAND: u8 = 1;
pub const PLUGIN_MODE_DISABLED: u8 = 2;

pub const CONFIG_FILENAME: &str = "SE.CFG";

#[derive(Clone, Copy, Debug)]
pub struct SeConfig {
    pub screen_mode: u8,
    pub tab_width: u8,
    pub lines_mode: u8,
    pub ramdrive_mode: u8,
    pub plugin_mode: u8,
    pub auto_indent: u8,
    pub config_loaded: u8,
}

impl Default for SeConfig {
    fn default() -> Self {
        Self {
            screen_mode: MODE_80X24,
            tab_width: 8,
            lines_mode: 0,
            ramdrive_mode: RAMDRV_MODE_PROTECTED,
            plugin_mode: PLUGIN_MODE_AUTOLOAD,
            auto_indent: 1,
            config_loaded: 0,
        }
    }
}

static CONFIG_STATE: OnceLock<Mutex<SeConfig>> = OnceLock::new();

fn state() -> &'static Mutex<SeConfig> {
    CONFIG_STATE.get_or_init(|| Mutex::new(SeConfig::default()))
}

pub fn get_config() -> SeConfig {
    *state().lock().unwrap()
}

pub fn set_config<F: FnOnce(&mut SeConfig)>(f: F) {
    let mut cfg = state().lock().unwrap();
    f(&mut cfg);
}

pub fn config_init_defaults() {
    let mut cfg = state().lock().unwrap();
    *cfg = SeConfig::default();
}

pub fn config_load_file(path: &str) -> i32 {
    let content = match fs::read_to_string(Path::new(path)) {
        Ok(c) => c,
        Err(_) => return -1,
    };

    let mut cfg = state().lock().unwrap();
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let key = k.trim().to_ascii_uppercase();
            let val = v.trim().to_ascii_uppercase();
            match key.as_str() {
                "SCREEN" | "GEOMETRY" => {
                    if val == "80X24" || val == "0" {
                        cfg.screen_mode = MODE_80X24;
                    } else if val == "120X40" || val == "1" {
                        cfg.screen_mode = MODE_120X40;
                    } else if val == "NATIVE" || val == "2" {
                        cfg.screen_mode = MODE_NATIVE;
                    }
                }
                "TAB" | "TABS" | "TAB_WIDTH" => {
                    if val == "4" {
                        cfg.tab_width = 4;
                    } else if val == "8" {
                        cfg.tab_width = 8;
                    }
                }
                "LINES" | "MAX_LINES" => {
                    if val == "16K" || val == "16384" || val == "0" {
                        cfg.lines_mode = 0;
                    } else if val == "32K" || val == "32768" || val == "1" {
                        cfg.lines_mode = 1;
                    }
                }
                "RAMDRIVE" => {
                    if val == "OVERWRITE" || val == "OVR" || val == "0" {
                        cfg.ramdrive_mode = RAMDRV_MODE_OVERWRITE;
                    } else if val == "PROTECT"
                        || val == "PROTECTED"
                        || val == "PRESERVE"
                        || val == "PROT"
                        || val == "1"
                    {
                        cfg.ramdrive_mode = RAMDRV_MODE_PROTECTED;
                    } else if val == "HIBERNATE" || val == "HIB" || val == "2" {
                        cfg.ramdrive_mode = RAMDRV_MODE_HIBERNATE;
                    } else if val == "DISABLE"
                        || val == "DISABLED"
                        || val == "OFF"
                        || val == "3"
                    {
                        cfg.ramdrive_mode = RAMDRV_MODE_DISABLED;
                    }
                }
                "PLUGIN" | "PLUGINS" => {
                    if val == "AUTOLOAD" || val == "AUTO" || val == "0" {
                        cfg.plugin_mode = PLUGIN_MODE_AUTOLOAD;
                    } else if val == "ONDEMAND"
                        || val == "DEMAND"
                        || val == "1"
                    {
                        cfg.plugin_mode = PLUGIN_MODE_ONDEMAND;
                    } else if val == "DISABLED"
                        || val == "DISABLE"
                        || val == "OFF"
                        || val == "2"
                    {
                        cfg.plugin_mode = PLUGIN_MODE_DISABLED;
                    }
                }
                "AUTO_INDENT" => {
                    if let Ok(n) = val.parse::<u8>() {
                        cfg.auto_indent = if n != 0 { 1 } else { 0 };
                    }
                }
                _ => {}
            }
        }
    }
    cfg.config_loaded = 1;
    0
}

pub fn config_save_file(path: &str) -> i32 {
    let mut cfg = state().lock().unwrap();
    let screen_str = match cfg.screen_mode {
        MODE_80X24 => "80X24",
        MODE_NATIVE => "NATIVE",
        _ => "120X40",
    };
    let lines_str = if cfg.lines_mode != 0 { "32K" } else { "16K" };
    let ram_str = match cfg.ramdrive_mode {
        RAMDRV_MODE_OVERWRITE => "OVR",
        RAMDRV_MODE_HIBERNATE => "HIB",
        RAMDRV_MODE_DISABLED => "OFF",
        _ => "PROT",
    };
    let plug_str = match cfg.plugin_mode {
        PLUGIN_MODE_ONDEMAND => "DEMAND",
        PLUGIN_MODE_DISABLED => "DISABLED",
        _ => "AUTO",
    };

    let data = format!(
        "SCREEN={}\r\nTAB={}\r\nLINES={}\r\nRAMDRIVE={}\r\n\
         PLUGIN={}\r\nAUTO_INDENT={}\r\n",
        screen_str,
        cfg.tab_width,
        lines_str,
        ram_str,
        plug_str,
        cfg.auto_indent
    );

    if fs::write(Path::new(path), data.as_bytes()).is_ok() {
        cfg.config_loaded = 1;
        0
    } else {
        -1
    }
}

pub fn config_load() -> i32 {
    config_load_file(CONFIG_FILENAME)
}

pub fn config_save() -> i32 {
    config_save_file(CONFIG_FILENAME)
}
