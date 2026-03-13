# titan_one

Python package for controlling **Nintendo Switch** via a **Titan One** USB adapter.

Works from any Python (32- or 64-bit) — the package automatically bridges to the 32-bit `gcdapi.dll` using a lightweight PowerShell subprocess.

## Requirements

- Windows (with 32-bit PowerShell at `C:\Windows\SysWOW64\`)
- [Titan One](https://www.consoletuner.com/products/titan-one/) device connected via USB
- `gcdapi.dll` from your Gtuner3 installation
- **Gtuner3 must be closed** while using this package (Direct API conflict)

## Installation

```bash
pip install -e .
```

## Quick Start

```python
from titan_one import TitanOneController, SwitchButton

# Auto-discovers gcdapi.dll in parent Gtuner3 folder, or pass path explicitly:
# TitanOneController(dll_path=r"C:\path\to\gcdapi.dll")

with TitanOneController() as c:
    # Tap a button (press + release)
    c.press(SwitchButton.B)
    c.press(SwitchButton.A, duration=0.5)

    # Press multiple buttons simultaneously
    c.press(SwitchButton.L, SwitchButton.R, duration=0.2)

    # String names work too
    c.press("zl")

    # Hold without auto-release
    c.hold(SwitchButton.B)
    c.release(SwitchButton.B)

    # Analog sticks (-100 to 100)
    c.tilt_stick(SwitchButton.LX, 80, duration=0.3)
    c.set_stick(SwitchButton.LX, 50, SwitchButton.LY, -50, duration=0.2)

    # Release everything
    c.release_all()
```

## API Reference

### `TitanOneController(dll_path=None, auto_connect=True)`

| Method | Description |
|--------|-------------|
| `press(*buttons, value=100, duration=0.1)` | Tap one or more buttons |
| `hold(*buttons, value=100)` | Press and hold (no auto-release) |
| `release(*buttons)` | Release specific buttons |
| `release_all()` | Release all inputs |
| `tilt_stick(axis, value, duration=None)` | Move a stick axis |
| `set_stick(x_axis, x_val, y_axis, y_val, duration=None)` | Move both axes of a stick |
| `write(values_dict)` | Send a raw output frame |
| `connect()` / `disconnect()` | Manual lifecycle control |

### `SwitchButton` Enum

| Face | D-Pad | Shoulder | Sticks | System |
|------|-------|----------|--------|--------|
| A, B, X, Y | UP, DOWN, LEFT, RIGHT | L, R, ZL, ZR, SL, SR | LX, LY, RX, RY | HOME, PLUS, MINUS, CAPTURE |

## Architecture

```
Python  ──JSON──▶  32-bit PowerShell  ──P/Invoke──▶  gcdapi.dll  ──USB──▶  Titan One  ──▶  Switch
```

The 32-bit bridge is needed because `gcdapi.dll` is a 32-bit DLL and most modern Python installs are 64-bit.

## License

MIT
