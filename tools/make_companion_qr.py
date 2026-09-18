"""Create a local QR image when optional qrcode is installed; never sends the URL externally."""
from pathlib import Path
import os
import sys


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_companion_qr.py URL OUTPUT.png")
    try:
        import qrcode
    except ImportError:
        print("QR skipped: pip install 'qrcode[pil]' (the URL above still works)")
        return 0
    output = Path(sys.argv[2])
    temporary = output.with_suffix(output.suffix + ".tmp")
    image = qrcode.make(sys.argv[1])
    image.save(temporary, format="PNG")
    os.replace(temporary, output)
    print(f"QR saved: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
