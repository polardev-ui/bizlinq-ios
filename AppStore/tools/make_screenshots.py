"""Crop-fit 6.9\" captures to App Store upload sizes. Run: python3 AppStore/tools/make_screenshots.py"""
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "AppStore", "screenshots")
OUT = os.path.join(SRC, "upload")
SHOTS = ["00-onboarding.png", "01-discover.png", "02-detail.png", "03-paywall.png"]
# (width, height) portrait slots
SIZES = [(1179, 2556), (1206, 2622)]


def crop_fit(img, tw, th):
    scale = max(tw / img.width, th / img.height)
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (resized.width - tw) // 2
    top = (resized.height - th) // 2
    return resized.crop((left, top, left + tw, top + th))


os.makedirs(OUT, exist_ok=True)
for shot in SHOTS:
    img = Image.open(os.path.join(SRC, shot)).convert("RGB")
    base, _ = os.path.splitext(shot)
    for tw, th in SIZES:
        out = crop_fit(img, tw, th)
        name = f"{base}-{tw}x{th}.png"
        out.save(os.path.join(OUT, name))
        print("wrote", name, out.size)
