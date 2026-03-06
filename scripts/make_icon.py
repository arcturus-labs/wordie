#!/usr/bin/env python3
"""Convert icon.svg to AppIcon.icns via cairosvg + iconutil."""

import os
import subprocess
import tempfile
import cairosvg

SVG_PATH = os.path.join(os.path.dirname(__file__), "..", "resources", "icon.svg")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "resources")

# macOS .icns requires these sizes (pixels) with names
SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

def main():
    with open(SVG_PATH, "rb") as f:
        svg_data = f.read()

    # Create .iconset directory
    iconset_dir = os.path.join(OUTPUT_DIR, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    for size, filename in SIZES:
        out_path = os.path.join(iconset_dir, filename)
        cairosvg.svg2png(
            bytestring=svg_data,
            write_to=out_path,
            output_width=size,
            output_height=size,
        )
        print(f"  {filename} ({size}x{size})")

    # Use iconutil to create .icns
    icns_path = os.path.join(OUTPUT_DIR, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"\n✅ Created {icns_path}")

    # Clean up iconset
    import shutil
    shutil.rmtree(iconset_dir)

if __name__ == "__main__":
    main()
