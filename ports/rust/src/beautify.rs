/*
 * beautify.rs - Built-in Z80 assembly & C code beautifier engine
 *
 * Part of SE.COM / Linux Native Rust Profile (se-rs).
 */

use crate::buffer::*;
use crate::config::*;
use crate::ui_modal::*;
use crate::ui_render::*;

const Z80_MNEMONICS: [&str; 69] = [
    "LD", "ADD", "ADC", "SUB", "SBC", "AND", "OR", "XOR", "CP", "INC", "DEC",
    "JP", "JR", "CALL", "RET", "RETI", "RETN", "RST", "DJNZ", "PUSH", "POP",
    "EX", "EXX", "LDI", "LDIR", "LDD", "LDDR", "CPI", "CPIR", "CPD", "CPDR",
    "INI", "INIR", "IND", "INDR", "OUTI", "OTIR", "OUTD", "OTDR", "IN", "OUT",
    "RLCA", "RLA", "RRCA", "RRA", "RLC", "RL", "RRC", "RR", "SLA", "SRA",
    "SRL", "BIT", "SET", "RES", "DAA", "CPL", "NEG", "CCF", "SCF", "NOP",
    "HALT", "DI", "EI", "IM", "DB", "DW", "DS", "EQU",
];

fn is_z80_mnemonic(word: &str) -> bool {
    let upper = word.to_ascii_uppercase();
    if upper == "ORG"
        || upper == "INCLUDE"
        || upper == "ALIGN"
        || upper == "PUBLIC"
        || upper == "EXTERN"
    {
        return true;
    }
    Z80_MNEMONICS.contains(&upper.as_str())
}

fn beautify_z80_line(src: &[u8]) -> Vec<u8> {
    let mut s = String::from_utf8_lossy(src).into_owned();
    while s.ends_with(' ') || s.ends_with('\t') {
        s.pop();
    }
    let trimmed = s.trim_start();
    if trimmed.is_empty() || trimmed.starts_with(';') {
        return s.into_bytes();
    }

    let mut label = String::new();
    let mut rest = trimmed;

    if let Some((tok, after)) =
        trimmed.split_once(|c: char| c == ' ' || c == '\t')
    {
        if tok.ends_with(':') || !is_z80_mnemonic(tok) {
            label = String::from(tok);
            rest = after.trim_start();
        }
    } else if trimmed.ends_with(':') {
        return trimmed.as_bytes().to_vec();
    }

    let mut out = if !label.is_empty() {
        format!("{}\t", label)
    } else {
        String::from("\t")
    };
    out.push_str(rest);
    if out.len() > MAX_LINE_CHARS {
        out.truncate(MAX_LINE_CHARS);
    }
    out.into_bytes()
}

pub fn beautify_buffer() {
    let (cr, _) = get_cur_pos();
    pack_line(cr);

    let (is_asm, tot) = {
        let b = buf_state().lock().unwrap();
        let name = b.current_filename.to_ascii_lowercase();
        let asm = name.ends_with(".asm")
            || name.ends_with(".inc")
            || name.ends_with(".z80");
        (asm, b.lines.len())
    };

    let mut changed = 0usize;
    for r in 0..tot {
        let orig = get_line_bytes(r);
        let formatted = if is_asm {
            beautify_z80_line(&orig)
        } else {
            let mut trimmed = orig.clone();
            while trimmed.last() == Some(&b' ')
                || trimmed.last() == Some(&b'\t')
            {
                trimmed.pop();
            }
            trimmed
        };
        if formatted != orig {
            set_line_bytes(r, &formatted);
            changed += 1;
        }
    }

    if changed > 0 {
        buf_state().lock().unwrap().file_modified = 1;
    }
    unpack_line(cr);
    render_all_lines();
    modal_notify_status(
        "Beautify Complete",
        "Document formatting applied.",
    );
}
