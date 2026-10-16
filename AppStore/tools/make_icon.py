"""Build AppIcon + Logo imageset from the real Logo.png. Run: python3 AppStore/tools/make_icon.py"""
import os
import shutil
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
LOGO = os.path.join(ROOT, "Logo.png")

logo = Image.open(LOGO).convert("RGBA")

# AppIcon: 1024x1024, opaque white (App Store rejects alpha), mark at ~80%.
icon = Image.new("RGB", (1024, 1024), (255, 255, 255))
scaled = logo.resize((820, 820), Image.LANCZOS)
icon.paste(scaled, (102, 102), scaled)
appicon = os.path.join(ROOT, "BizLinq", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(appicon, exist_ok=True)
for old in ("icon-1024.png",):
    try:
        os.remove(os.path.join(appicon, old))
    except FileNotFoundError:
        pass
icon.save(os.path.join(appicon, "icon-1024.png"))

# In-app logo: keep transparency.
imageset = os.path.join(ROOT, "BizLinq", "Assets.xcassets", "Logo.imageset")
os.makedirs(imageset, exist_ok=True)
shutil.copyfile(LOGO, os.path.join(imageset, "logo.png"))
with open(os.path.join(imageset, "Contents.json"), "w") as f:
    f.write('{\n  "images" : [\n    {\n      "filename" : "logo.png",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print("app icon + logo imageset written")
