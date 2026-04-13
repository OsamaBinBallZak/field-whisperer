#!/usr/bin/env python3
"""
Generate the FieldWhisperer DMG background image.
Pure Python — no external dependencies.
Output: Distribution/dmg-background.png (600×400px)
"""
import struct, zlib, os

W, H = 600, 400
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dmg-background.png")

# ── Gradient colours ──────────────────────────────────────────────────────────
# Top:    #EAE6FF  (very light lavender — matches FieldWhisperer icon hue)
# Bottom: #C4B8FF  (medium lavender)
TOP    = (234, 230, 255)
BOTTOM = (196, 184, 255)

def grad(y):
    t = y / (H - 1)
    return tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))

# ── Pixel canvas ──────────────────────────────────────────────────────────────
canvas = [[grad(y) for _ in range(W)] for y in range(H)]

def set_pixel(x, y, rgb):
    if 0 <= x < W and 0 <= y < H:
        canvas[y][x] = rgb

def fill_rect(x0, y0, x1, y1, rgb):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            set_pixel(x, y, rgb)

# ── Bitmap font ───────────────────────────────────────────────────────────────
# 5-wide × 7-tall.  Row 0 = top.  Bit 4 = leftmost column.
FONT = {
    ' ': (0,)*7,
    'A': (0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0),
    'D': (0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110, 0),
    'F': (0b11111, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000, 0),
    'W': (0b10001, 0b10001, 0b10001, 0b10101, 0b01010, 0,        0),
    'a': (0,       0b01110, 0b00001, 0b01111, 0b10001, 0b01111, 0),
    'c': (0,       0b01110, 0b10000, 0b10000, 0b10001, 0b01110, 0),
    'd': (0b00001, 0b00001, 0b01101, 0b10011, 0b10001, 0b01111, 0),
    'e': (0,       0b01110, 0b10001, 0b11111, 0b10000, 0b01110, 0),
    'g': (0,       0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b01110),
    'h': (0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b10001, 0),
    'i': (0b00100, 0,       0b00100, 0b00100, 0b00100, 0b00100, 0),
    'l': (0b00110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0),
    'n': (0,       0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0),
    'o': (0,       0b01110, 0b10001, 0b10001, 0b10001, 0b01110, 0),
    'p': (0,       0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000),
    'r': (0,       0b10110, 0b11001, 0b10000, 0b10000, 0b10000, 0),
    's': (0,       0b01110, 0b10000, 0b01110, 0b00001, 0b11110, 0),
    't': (0b00100, 0b11111, 0b00100, 0b00100, 0b00100, 0b00011, 0),
}

def draw_text(cx, y0, text, color, scale=1, gap=1):
    """Render text centred at cx, top at y0."""
    char_w = 5 * scale + gap
    x0 = cx - (len(text) * char_w - gap) // 2
    for ch in text:
        glyph = FONT.get(ch, FONT[' '])
        for row_i, row_bits in enumerate(glyph):
            for col_i in range(5):
                if row_bits & (1 << (4 - col_i)):
                    for sy in range(scale):
                        for sx in range(scale):
                            set_pixel(x0 + col_i * scale + sx,
                                      y0 + row_i * scale + sy,
                                      color)
        x0 += char_w

# ── Text labels ───────────────────────────────────────────────────────────────
TITLE_C = (100,  80, 190)   # dark indigo
SUB_C   = (130, 110, 205)   # medium indigo

draw_text(W // 2,  30, "FieldWhisperer",               TITLE_C, scale=2, gap=2)
draw_text(W // 2, 252, "drag to Applications to install", SUB_C,   scale=1, gap=1)

# ── Arrow (→) centred between icon positions ──────────────────────────────────
# App icon will be at x≈150, Applications at x≈450  →  arrow centre x=300
ARROW_X  = 300          # horizontal centre of the arrow
ARROW_Y  = 210          # vertical centre
ARROW_W  = 64           # total width of arrow
SHAFT_H  = 8            # thickness of the shaft
HEAD_W   = 28           # width of the arrowhead
HEAD_H   = 28           # half-height of the arrowhead (full height = 2×HEAD_H)
ARROW_C  = (140, 120, 220)  # dark lavender — visible but not harsh

shaft_x0 = ARROW_X - ARROW_W // 2
shaft_x1 = ARROW_X + ARROW_W // 2 - HEAD_W
shaft_y0 = ARROW_Y - SHAFT_H // 2
shaft_y1 = ARROW_Y + SHAFT_H // 2
fill_rect(shaft_x0, shaft_y0, shaft_x1, shaft_y1, ARROW_C)

# Triangle arrowhead
head_tip  = ARROW_X + ARROW_W // 2
head_base = head_tip - HEAD_W
for dx in range(HEAD_W + 1):
    x = head_base + dx
    spread = int(HEAD_H * dx / HEAD_W)
    fill_rect(x, ARROW_Y - spread, x, ARROW_Y + spread, ARROW_C)

# ── Encode as PNG ─────────────────────────────────────────────────────────────
def png_chunk(tag: bytes, data: bytes) -> bytes:
    payload = tag + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

ihdr = struct.pack(">II", W, H) + bytes([8, 2, 0, 0, 0])  # 8-bit RGB

rows = bytearray()
for y in range(H):
    rows.append(0)  # filter byte: None
    for x in range(W):
        rows.extend(canvas[y][x])

png = (b"\x89PNG\r\n\x1a\n"
       + png_chunk(b"IHDR", ihdr)
       + png_chunk(b"IDAT", zlib.compress(bytes(rows), 6))
       + png_chunk(b"IEND", b""))

with open(OUT, "wb") as f:
    f.write(png)

print(f"  Background image: {OUT}  ({W}\xd7{H}px, {len(png):,} bytes)")
