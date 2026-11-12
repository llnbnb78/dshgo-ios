from PIL import Image, ImageDraw, ImageFont
import os

OUT = "Resources"
os.makedirs(OUT, exist_ok=True)

def font(size):
    for p in ("/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def render(size):
    S = 4
    n = size * S
    img = Image.new("RGB", (n, n), "#0b1220")
    d = ImageDraw.Draw(img)
    # 背景渐变
    for y in range(n):
        t = y / max(1, n - 1)
        r = int(11 + 24 * t); g = int(18 + 60 * t); b = int(32 + 96 * t)
        d.line([(0, y), (n, y)], fill=(r, g, b))
    base = img
    d = ImageDraw.Draw(base)
    # 光标块
    bar_w = int(n * 0.055)
    pad = int(n * 0.20)
    d.rounded_rectangle([pad, int(n * 0.24), pad + bar_w, int(n * 0.76)],
                        radius=bar_w // 2, fill="#3ddc97")
    # DSH 字样
    f = font(int(n * 0.235))
    text = "DSH"
    tw = d.textlength(text, font=f)
    cx = (pad + bar_w + n) / 2
    d.text((cx, n * 0.50), text, font=f, fill="#ffffff", anchor="mm")
    # 底部小字
    f2 = font(int(n * 0.075))
    t2 = "GO"
    tw2 = d.textlength(t2, font=f2)
    d.text((cx, n * 0.745), t2, font=f2, fill="#3ddc97", anchor="mm")
    return base.resize((size, size), Image.LANCZOS)

specs = {
    "Icon60@2x.png": 120,
    "Icon60@3x.png": 180,
    "Icon76@2x.png": 152,
    "Icon83.5@2x.png": 167,
    "Icon1024.png": 1024,
}
for name, sz in specs.items():
    render(sz).save(os.path.join(OUT, name))
    print(name, sz)
