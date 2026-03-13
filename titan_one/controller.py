"""
TitanOneController — high-level Python interface for the Titan One adapter.

Uses a 32-bit PowerShell subprocess to bridge the 32-bit gcdapi.dll,
so this works from any Python (32- or 64-bit).
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Dict, Optional, Union

from titan_one.buttons import SwitchButton

# Default paths
_BRIDGE_PS1 = Path(__file__).parent / "_bridge.ps1"
_PS_X86 = r"C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"


def _find_dll(start: Path) -> Optional[Path]:
    """Search upward from start for gcdapi.dll inside a Gtuner3 folder."""
    current = start.resolve()
    for _ in range(6):  # up to 6 levels up
        candidate = current / "Gtuner3" / "gcdapi.dll"
        if candidate.exists():
            return candidate
        # Also check current dir directly
        candidate2 = current / "gcdapi.dll"
        if candidate2.exists():
            return candidate2
        if current.parent == current:
            break
        current = current.parent
    return None


class TitanOneError(Exception):
    """Raised when the Titan One bridge reports an error."""


class TitanOneController:
    """Control a Nintendo Switch through a Titan One adapter.

    Parameters
    ----------
    dll_path : str or Path, optional
        Path to ``gcdapi.dll``.  Defaults to ``../Gtuner3/gcdapi.dll``
        relative to the package.
    auto_connect : bool
        If True (default), connect to the device on ``__init__`` /
        context-manager entry.

    Examples
    --------
    >>> from titan_one import TitanOneController, SwitchButton
    >>> with TitanOneController() as c:
    ...     c.press(SwitchButton.B)
    ...     c.press(SwitchButton.A, duration=0.3)
    ...     c.tilt_stick(SwitchButton.LX, 80)
    """

    def __init__(
        self,
        dll_path: Union[str, Path, None] = None,
        auto_connect: bool = True,
    ):
        self._dll_path = Path(dll_path) if dll_path else _find_dll(Path(__file__).parent)
        if self._dll_path is None or not self._dll_path.exists():
            raise FileNotFoundError(
                "gcdapi.dll not found. Pass dll_path= explicitly, e.g.:\n"
                "  TitanOneController(dll_path=r'C:\\path\\to\\Gtuner3\\gcdapi.dll')"
            )
        if not Path(_PS_X86).exists():
            raise EnvironmentError(
                "32-bit PowerShell not found. This package requires Windows "
                "with SysWOW64 support."
            )

        self._proc: Optional[subprocess.Popen] = None
        self._firmware: Optional[int] = None
        self._device_pid: Optional[str] = None

        if auto_connect:
            self.connect()

    # ------------------------------------------------------------------
    # Connection lifecycle
    # ------------------------------------------------------------------

    def connect(self) -> dict:
        """Start the bridge and connect to the Titan One device.

        Returns a dict with ``firmware`` and ``device_pid`` on success.
        """
        if self._proc is not None:
            return {"firmware": self._firmware, "device_pid": self._device_pid}

        self._proc = subprocess.Popen(
            [
                _PS_X86,
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", str(_BRIDGE_PS1),
                "-DllPath", str(self._dll_path.resolve()),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )

        resp = self._send({"cmd": "connect"})
        self._firmware = resp.get("firmware")
        self._device_pid = resp.get("device_pid")
        return resp

    def disconnect(self) -> None:
        """Disconnect from the device and stop the bridge process."""
        if self._proc is None:
            return
        try:
            self._send({"cmd": "quit"})
        except Exception:
            pass
        try:
            self._proc.terminate()
            self._proc.wait(timeout=3)
        except Exception:
            pass
        self._proc = None
        self._firmware = None
        self._device_pid = None

    @property
    def firmware(self) -> Optional[int]:
        return self._firmware

    @property
    def is_connected(self) -> bool:
        if self._proc is None:
            return False
        try:
            resp = self._send({"cmd": "is_connected"})
            return resp.get("connected", False)
        except Exception:
            return False

    # ------------------------------------------------------------------
    # Button / input helpers
    # ------------------------------------------------------------------

    def write(self, values: Dict[Union[SwitchButton, int, str], int]) -> None:
        """Send a raw output frame to the controller.

        Parameters
        ----------
        values : dict
            Mapping of ``SwitchButton`` (or int index / string name) to
            value (-100..100).  Any index not specified defaults to 0.
        """
        resolved: Dict[str, int] = {}
        for key, val in values.items():
            idx = self._resolve_button(key)
            resolved[str(idx)] = max(-100, min(100, int(val)))
        self._send({"cmd": "write", "values": resolved})

    def press(
        self,
        *buttons: Union[SwitchButton, int, str],
        value: int = 100,
        duration: float = 0.1,
    ) -> None:
        """Press one or more buttons, hold, then release.

        Parameters
        ----------
        *buttons : SwitchButton | int | str
            One or more buttons to press simultaneously.
        value : int
            Pressure value (0-100).  Default 100 (fully pressed).
        duration : float
            How long to hold the press in seconds.  Default 0.1s.
        """
        mapping = {btn: value for btn in buttons}
        self.write(mapping)
        time.sleep(duration)
        self.release_all()

    def hold(
        self,
        *buttons: Union[SwitchButton, int, str],
        value: int = 100,
    ) -> None:
        """Press and hold buttons (without automatic release).

        Call ``release()`` or ``release_all()`` to let go.
        """
        mapping = {btn: value for btn in buttons}
        self.write(mapping)

    def release(self, *buttons: Union[SwitchButton, int, str]) -> None:
        """Release specific buttons (set to 0)."""
        mapping = {btn: 0 for btn in buttons}
        self.write(mapping)

    def release_all(self) -> None:
        """Release every input (send all zeros)."""
        self._send({"cmd": "write", "values": {}})

    def tap(
        self,
        *buttons: Union[SwitchButton, int, str],
        value: int = 100,
    ) -> None:
        """Atomic press+release in a single bridge call.

        The button is held for only microseconds — press and release
        both happen on the bridge side with no Python round-trip between them.
        """
        resolved: Dict[str, int] = {}
        for btn in buttons:
            idx = self._resolve_button(btn)
            resolved[str(idx)] = max(0, min(100, int(value)))
        self._send({"cmd": "tap", "values": resolved})

    def tilt_stick(
        self,
        axis: Union[SwitchButton, int, str],
        value: int,
        duration: Optional[float] = None,
    ) -> None:
        """Tilt an analog stick axis.

        Parameters
        ----------
        axis : SwitchButton.LX / LY / RX / RY
            Which stick axis to move.
        value : int
            -100 (full left/up) to 100 (full right/down).
        duration : float, optional
            If set, return stick to center after this many seconds.
        """
        self.write({axis: value})
        if duration is not None:
            time.sleep(duration)
            self.write({axis: 0})

    def set_stick(
        self,
        x_axis: Union[SwitchButton, int, str],
        x_value: int,
        y_axis: Union[SwitchButton, int, str],
        y_value: int,
        duration: Optional[float] = None,
    ) -> None:
        """Set both axes of a stick at once.

        Example: ``c.set_stick(SwitchButton.LX, 80, SwitchButton.LY, -50)``
        """
        self.write({x_axis: x_value, y_axis: y_value})
        if duration is not None:
            time.sleep(duration)
            self.write({x_axis: 0, y_axis: 0})

    # ------------------------------------------------------------------
    # Context manager
    # ------------------------------------------------------------------

    def __enter__(self) -> "TitanOneController":
        return self

    def __exit__(self, *exc) -> None:
        self.disconnect()

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    @staticmethod
    def _resolve_button(key: Union[SwitchButton, int, str]) -> int:
        """Convert a button key to its integer index."""
        if isinstance(key, int):
            return int(key)
        if isinstance(key, str):
            try:
                return int(SwitchButton[key.upper()])
            except KeyError:
                raise ValueError(
                    f"Unknown button name '{key}'. "
                    f"Valid names: {', '.join(b.name for b in SwitchButton)}"
                )
        return int(key)

    def _send(self, msg: dict, timeout: float = 15.0) -> dict:
        """Send a JSON message to the bridge and return the parsed response."""
        if self._proc is None or self._proc.poll() is not None:
            raise TitanOneError("Bridge process is not running. Call connect() first.")

        line = json.dumps(msg) + "\n"
        try:
            self._proc.stdin.write(line)
            self._proc.stdin.flush()
        except (BrokenPipeError, OSError) as e:
            stderr = ""
            try:
                stderr = self._proc.stderr.read()
            except Exception:
                pass
            raise TitanOneError(f"Failed to send to bridge: {e}\nBridge stderr: {stderr}")

        # Read response with timeout using a thread (selectors doesn't
        # work with pipes on Windows).
        import threading

        result = [None]
        error = [None]

        def _read():
            try:
                result[0] = self._proc.stdout.readline()
            except Exception as e:
                error[0] = e

        t = threading.Thread(target=_read, daemon=True)
        t.start()
        t.join(timeout=timeout)

        if t.is_alive():
            raise TitanOneError(f"Bridge did not respond within {timeout}s")

        if error[0] is not None:
            raise TitanOneError(f"Error reading from bridge: {error[0]}")

        resp_line = result[0]
        if not resp_line:
            stderr = ""
            try:
                stderr = self._proc.stderr.read()
            except Exception:
                pass
            raise TitanOneError(f"Bridge returned empty response.\nBridge stderr: {stderr}")

        try:
            resp = json.loads(resp_line)
        except json.JSONDecodeError:
            raise TitanOneError(f"Invalid JSON from bridge: {resp_line!r}")

        if resp.get("status") == "error":
            raise TitanOneError(resp.get("message", "Unknown bridge error"))

        return resp

    def __repr__(self) -> str:
        state = "connected" if self._proc and self._proc.poll() is None else "disconnected"
        fw = f", fw={self._firmware}" if self._firmware else ""
        return f"<TitanOneController({state}{fw})>"
