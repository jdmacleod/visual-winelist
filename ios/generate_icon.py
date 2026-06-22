#!/usr/bin/env python3
"""Generate the Visual Winelist iOS app icon — 1024x1024 wine/grapes theme."""

import math
from PIL import Image, ImageDraw

SIZE = 1024
OUT = "Sources/VisualWinelistIOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"


def lerp(a, b, t):
    return a + (b - a) * t


def main():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    # ── Background: deep burgundy-to-purple gradient ──────────────────────────
    bg_top = (130, 28, 55)
    bg_bot = (55, 12, 80)
    for y in range(SIZE):
        t = y / SIZE
        r = int(lerp(bg_top[0], bg_bot[0], t))
        g = int(lerp(bg_top[1], bg_bot[1], t))
        b = int(lerp(bg_top[2], bg_bot[2], t))
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    # ── Subtle warm glow behind cluster ──────────────────────────────────────
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for radius in range(300, 0, -6):
        alpha = int(22 * (1 - radius / 300))
        gd.ellipse(
            [SIZE // 2 - radius, SIZE // 2 - 60 - radius,
             SIZE // 2 + radius, SIZE // 2 - 60 + radius],
            fill=(200, 60, 100, alpha),
        )
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # ── Wine glass (subtle outline, bottom third) ─────────────────────────────
    # Draw first so grapes sit on top
    glass_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gl = ImageDraw.Draw(glass_layer)
    gx = SIZE // 2
    # Bowl: classic wide wine glass bowl
    bowl_top_y = 620
    bowl_bot_y = 760
    bowl_w = 170
    # Fill bowl with very translucent white
    gl.ellipse(
        [gx - bowl_w, bowl_top_y, gx + bowl_w, bowl_bot_y],
        fill=(255, 230, 240, 28),
        outline=(255, 200, 220, 55),
        width=4,
    )
    # Stem
    stem_h = 100
    stem_y0 = (bowl_top_y + bowl_bot_y) // 2 + 10
    for w in range(-5, 6):
        gl.line(
            [(gx + w, stem_y0), (gx + w, stem_y0 + stem_h)],
            fill=(255, 200, 220, 45),
        )
    # Base
    base_y = stem_y0 + stem_h
    gl.ellipse(
        [gx - 95, base_y - 14, gx + 95, base_y + 14],
        fill=(255, 200, 220, 40),
        outline=(255, 200, 220, 55),
        width=3,
    )
    img = Image.alpha_composite(img, glass_layer)
    draw = ImageDraw.Draw(img)

    # ── Grape cluster (triangular, widest at top) ─────────────────────────────
    grape_fill   = (165, 38, 95)
    grape_shadow = (100, 18, 58)
    grape_hi     = (215, 110, 155)

    R   = 68   # grape radius
    DX  = int(R * 1.92)
    DY  = int(R * 1.68)

    # rows: wide at top, taper to tip (classic inverted-triangle bunch)
    rows = [5, 4, 5, 4, 3, 2, 1]
    cx0 = SIZE // 2
    cy0 = 215   # top of cluster (leaves will appear above this)

    positions = []
    for row_i, count in enumerate(rows):
        # Alternate rows offset by half-spacing for hex packing
        offset_x = DX // 2 if count % 2 == 0 else 0
        row_width = (count - 1) * DX
        start_x = cx0 - row_width // 2 + offset_x
        for col_i in range(count):
            x = start_x + col_i * DX
            y = cy0 + row_i * DY
            positions.append((x, y))

    # Drop-shadow pass
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    for (x, y) in positions:
        sd.ellipse([x - R + 9, y - R + 12, x + R + 9, y + R + 12], fill=(20, 0, 15, 90))
    shadow_layer = shadow_layer.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(radius=8))
    img = Image.alpha_composite(img, shadow_layer)
    draw = ImageDraw.Draw(img)

    # Grape pass: dark rim + fill + highlight
    for (x, y) in positions:
        draw.ellipse([x - R, y - R, x + R, y + R], fill=grape_shadow)
        draw.ellipse([x - R + 5, y - R + 5, x + R - 5, y + R - 5], fill=grape_fill)
        hr = int(R * 0.30)
        hx = x - int(R * 0.30)
        hy = y - int(R * 0.30)
        draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=grape_hi)

    # ── Stem ─────────────────────────────────────────────────────────────────
    # Curved stem from top of cluster upward
    stem_color = (95, 58, 20)
    vine_tip_x = cx0 + 20
    vine_tip_y = cy0 - R - 10
    vine_top_x = cx0 + 60
    vine_top_y = 85
    for w in range(-9, 10):
        draw.line(
            [(vine_tip_x + w, vine_tip_y), (vine_top_x + w // 2, vine_top_y)],
            fill=stem_color,
            width=1,
        )

    # ── Leaves ───────────────────────────────────────────────────────────────
    leaf_fill = (38, 105, 45)
    leaf_vein = (55, 145, 62)
    leaf_dark = (25, 75, 30)

    def draw_leaf(layer_img, cx, cy, angle_deg, rw, rh):
        leaf = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        ld = ImageDraw.Draw(leaf)
        # Leaf body
        ld.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=leaf_fill)
        # Darker edge around
        ld.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], outline=leaf_dark, width=4)
        # Midrib
        angle = math.radians(angle_deg)
        tip_x = cx + int(rw * 0.85 * math.cos(angle))
        tip_y = cy + int(rh * 0.85 * math.sin(angle))
        ld.line([(cx - int(rw * 0.5 * math.cos(angle)),
                  cy - int(rh * 0.5 * math.sin(angle))),
                 (tip_x, tip_y)],
                fill=leaf_vein, width=5)
        rotated = leaf.rotate(-angle_deg + 90, center=(cx, cy), expand=False)
        return Image.alpha_composite(layer_img, rotated)

    img = draw_leaf(img, vine_top_x + 58, vine_top_y + 10, 25, 88, 50)
    img = draw_leaf(img, vine_top_x - 52, vine_top_y + 18, -30, 78, 44)
    draw = ImageDraw.Draw(img)

    # ── Vignette ─────────────────────────────────────────────────────────────
    vig = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vig)
    for step in range(1, 60):
        t = step / 60
        r_v = int(SIZE * 0.5 * (1 - t * 0.15))
        alpha = int(100 * (t ** 2.2))
        vd.ellipse(
            [SIZE // 2 - r_v, SIZE // 2 - r_v, SIZE // 2 + r_v, SIZE // 2 + r_v],
            outline=(0, 0, 0, alpha),
            width=6,
        )
    img = Image.alpha_composite(img, vig)

    img = img.convert("RGB")
    img.save(OUT)
    print(f"Saved {OUT} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
