# SE — Python Native Implementation for Linux

A native Python 3 implementation of the classic Screen Editor (SE),
conforming strictly to `docs/UI_UX_DESIGN.md` with full WordStar keybindings,
universal status bar presence, column 0 tilde discipline, and centered
boxed modal pop-up dialogs.

## Features
- **Zero External Dependencies**: Pure standard library (`termios`, `tty`).
- **Display Geometries**: 80x24 standard terminal and 120x40 wide console.
- **Full WordStar & SE Keybinding Compatibility**:
  - `Ctrl+K`: Help screen / Editor mode keys
  - `Ctrl+Q`: Safe quit with unsaved changes verification
  - `Ctrl+S`: Save file
  - `Ctrl+O`: Open file
  - `Ctrl+F`: Find text modal
  - `Ctrl+N`: Find next
  - `Ctrl+R`: Replace text modal
  - `Ctrl+B`: Block selection mode
  - `Ctrl+C`: Copy block
  - `Ctrl+X`: Cut block
  - `Ctrl+T` / `Ctrl+G`: Jump to Top / Jump to Bottom
  - `Ctrl+U` / `Ctrl+V`: Page Up / Page Down
  - `Ctrl+A` / `Ctrl+E`: Home / End of line
- **Configuration Engine**: Compatible with `SE.CFG`.
- **Python Plugin Subsystem**: Reflects upper memory Host API vectors.

## Installation & Execution
Run directly without installation:
```bash
python3 ports/python/bin/se [filename]
```
Or install in development mode:
```bash
pip install -e ports/python
se [filename]
```
