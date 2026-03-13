"""Quick test: press the B button on Nintendo Switch via Titan One."""

from titan_one import TitanOneController, SwitchButton

print("Connecting to Titan One...")
with TitanOneController() as c:
    print(f"Connected! {c}")

    print("\nPressing B button...")
    c.press(SwitchButton.B, duration=0.2)
    print("B pressed and released!")

    print("\nDone.")
