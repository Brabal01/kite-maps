#!/usr/bin/env python3
"""
A cheap, honest check on simulator screenshots.

It cannot judge whether a layout "looks right"; a human or a reviewed reference
image must do that. It can catch the failures that automation actually sees:
a missing screen, a black frame, a blank/uniform image, or a screenshot taken
before the app drew anything.
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageStat
except ImportError:
    print("Pillow is not installed", file=sys.stderr)
    sys.exit(2)

EXPECTED = [
    "home-dark", "home-light", "routes-dark",
    "place-dark", "directions-dark",
    "nav-dark", "nav-light", "settings-dark",
    "se-home", "max-home",
]

def check(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, "missing"
    try:
        with Image.open(path) as image:
            image = image.convert("RGB")
            width, height = image.size
            stat = ImageStat.Stat(image)
            mean = sum(stat.mean) / 3
            spread = max(stat.stddev)
            # A fully black screenshot, or one with no variation at all, means
            # the app had not drawn its first frame.
            if mean < 4 and spread < 3:
                return False, "black frame"
            if spread < 2:
                return False, "uniform frame"
            if width < 300 or height < 500:
                return False, f"too small ({width}x{height})"
            return True, f"{width}x{height}, mean {mean:.0f}, spread {spread:.0f}"
    except Exception as exc:  # corrupt PNG
        return False, f"unreadable: {exc}"

def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "shots")
    failures = 0
    for name in EXPECTED:
        ok, detail = check(root / f"{name}.png")
        print(f"{'OK  ' if ok else 'FAIL'} {name:14} {detail}")
        failures += 0 if ok else 1
    print(f"\n{len(EXPECTED) - failures}/{len(EXPECTED)} screenshots passed the mechanical check")
    print("Layout quality is NOT verified by this script. Large text, landscape and long-name overflow are not covered by this run.")
    return 1 if failures else 0

if __name__ == "__main__":
    sys.exit(main())
