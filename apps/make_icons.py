# Makes the app icons from the site's icon.png (square, any size). Run by the GitHub workflow.
#   iPhone/iPad: the picture as it is (iOS rounds the corners itself).
#   Mac: the picture on a rounded white tile with a soft shadow, like other Mac apps.
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

src = Image.open(sys.argv[1] if len(sys.argv) > 1 else "icon.png").convert("RGBA")
here = os.path.dirname(os.path.abspath(__file__))

def flat(size):
    bg = Image.new("RGBA", src.size, "white")
    bg.alpha_composite(src)
    return bg.convert("RGB").resize((size, size), Image.LANCZOS)

def mac(size):
    S = 1024
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    box, radius = (100, 100, 924, 924), 185
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((100, 112, 924, 936), radius, fill=(0, 0, 0, 80))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile.paste(flat(824).convert("RGBA"), (100, 100))
    out.paste(tile, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)

def write(folder, images):
    d = os.path.join(here, folder, "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(here, folder, "Assets.xcassets", "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f)
    entries = []
    for name, img, entry in images:
        img.save(os.path.join(d, name))
        entries.append(dict(entry, filename=name))
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": entries, "info": {"version": 1, "author": "xcode"}}, f, indent=1)

write("iOS", [("icon-1024.png", flat(1024), {"idiom": "universal", "platform": "ios", "size": "1024x1024"})])
mac_images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        mac_images.append(("mac-%d@%dx.png" % (pt, scale), mac(pt * scale), {"idiom": "mac", "size": "%dx%d" % (pt, pt), "scale": "%dx" % scale}))
write("Mac", mac_images)
print("icons made")
