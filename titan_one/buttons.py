"""Nintendo Switch button and axis constants for the Titan One GCAPI."""

from enum import IntEnum


class SwitchButton(IntEnum):
    """Nintendo Switch controller input indexes (from gcapi.h).

    Buttons accept values 0 (released) to 100 (fully pressed).
    Sticks accept values -100 to 100.
    """

    # System buttons
    HOME    = 0
    MINUS   = 1
    PLUS    = 2
    CAPTURE = 27

    # Shoulder / trigger buttons
    R  = 3
    ZR = 4
    SR = 5
    L  = 6
    ZL = 7
    SL = 8

    # Stick axes  (-100 to 100)
    RX = 9
    RY = 10
    LX = 11
    LY = 12

    # D-Pad
    UP    = 13
    DOWN  = 14
    LEFT  = 15
    RIGHT = 16

    # Face buttons
    X = 17
    A = 18
    B = 19
    Y = 20

    # Motion sensors (-100 to 100)
    ACCX  = 21
    ACCY  = 22
    ACCZ  = 23
    GYROX = 24
    GYROY = 25
    GYROZ = 26


# Convenient groupings
FACE_BUTTONS = {SwitchButton.A, SwitchButton.B, SwitchButton.X, SwitchButton.Y}
DPAD_BUTTONS = {SwitchButton.UP, SwitchButton.DOWN, SwitchButton.LEFT, SwitchButton.RIGHT}
SHOULDER_BUTTONS = {SwitchButton.L, SwitchButton.R, SwitchButton.ZL, SwitchButton.ZR,
                    SwitchButton.SL, SwitchButton.SR}
STICK_AXES = {SwitchButton.LX, SwitchButton.LY, SwitchButton.RX, SwitchButton.RY}
