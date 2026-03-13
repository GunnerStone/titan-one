"""
titan_one - Python package for controlling Nintendo Switch via Titan One adapter.

Usage:
    from titan_one import TitanOneController, SwitchButton

    with TitanOneController() as c:
        c.press(SwitchButton.B)
        c.press(SwitchButton.A, duration=0.5)
        c.set_stick("LX", 75, "LY", -50)
"""

from titan_one.buttons import SwitchButton
from titan_one.controller import TitanOneController

__all__ = ["TitanOneController", "SwitchButton"]
__version__ = "0.1.0"
