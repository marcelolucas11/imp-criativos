#!/usr/bin/env python3
"""Gera os ícones do IMP Criativos a partir da logo original (flor-de-lis vermelha).

Uso:  python3 scripts/make_icon.py caminho/da/logo.png

Saídas:
  Resources/Assets.xcassets/AppIcon.appiconset/*      ícone do app (squircle preto)
  Resources/Assets.xcassets/MenuBarIcon.imageset/*    ícone template da barra de menus
  Resources/Assets.xcassets/BrandMark.imageset/*      símbolo vermelho para uso nas telas
  Resources/Assets.xcassets/AccentColor.colorset/*    vermelho da marca
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "Assets.xcassets"
BRAND_RED = (255, 51, 51)


def extract_symbol(path: Path) -> Image.Image:
    """Transforma a logo (vermelho sobre branco) em símbolo vermelho com transparência."""
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(np.float32)
    rgb = arr[..., :3]
    # quanto menos verde/azul, mais "tinta vermelha" tem o pixel
    ink = (255.0 - np.minimum(rgb[..., 1], rgb[..., 2])) / (255.0 - 51.0)
    ink = np.clip(ink, 0, 1) * (arr[..., 3] / 255.0)
    out = np.zeros_like(arr)
    out[..., 0], out[..., 1], out[..., 2] = BRAND_RED
    out[..., 3] = ink * 255
    sym = Image.fromarray(out.astype(np.uint8), "RGBA")
    return sym.crop(sym.getbbox())


def squircle_mask(size: int, n: float = 5.0, ss: int = 4) -> Image.Image:
    """Máscara de superelipse (formato de ícone do macOS), com antialiasing."""
    big = size * ss
    half = big / 2
    pts = []
    for t in np.linspace(0, 2 * np.pi, 2048, endpoint=False):
        c, s = np.cos(t), np.sin(t)
        x = half + half * np.sign(c) * abs(c) ** (2 / n)
        y = half + half * np.sign(s) * abs(s) ** (2 / n)
        pts.append((x, y))
    m = Image.new("L", (big, big), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def fit(img: Image.Image, box: int) -> Image.Image:
    w, h = img.size
    k = box / max(w, h)
    return img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)


def make_app_icon(sym: Image.Image) -> Image.Image:
    canvas = 1024
    body = 824  # grade oficial do macOS: 100 px de margem
    off = (canvas - body) // 2

    # fundo preto com leve gradiente para dar profundidade
    grad = np.zeros((body, body, 4), np.uint8)
    top, bottom = np.array([34, 34, 36]), np.array([6, 6, 7])
    for y in range(body):
        grad[y, :, :3] = top + (bottom - top) * (y / (body - 1))
    grad[..., 3] = 255
    plate = Image.fromarray(grad, "RGBA")
    mask = squircle_mask(body)
    plate.putalpha(mask)

    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    # sombra suave (padrão dos ícones do macOS)
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    sh = Image.new("RGBA", (body, body), (0, 0, 0, 110))
    sh.putalpha(mask.point(lambda v: v * 110 // 255))
    shadow.paste(sh, (off, off + 12), sh)
    icon = Image.alpha_composite(icon, shadow.filter(ImageFilter.GaussianBlur(14)))
    icon.paste(plate, (off, off), plate)

    s = fit(sym, int(body * 0.68))
    icon.alpha_composite(s, ((canvas - s.width) // 2, (canvas - s.height) // 2))
    return icon


def write_appiconset(icon: Image.Image) -> None:
    d = ASSETS / "AppIcon.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            icon.resize((px, px), Image.LANCZOS).save(d / name)
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    (d / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))


def write_imageset(name: str, img_1x: Image.Image, img_2x: Image.Image, template: bool = False) -> None:
    d = ASSETS / f"{name}.imageset"
    d.mkdir(parents=True, exist_ok=True)
    img_1x.save(d / f"{name}.png")
    img_2x.save(d / f"{name}@2x.png")
    contents = {
        "images": [
            {"idiom": "universal", "scale": "1x", "filename": f"{name}.png"},
            {"idiom": "universal", "scale": "2x", "filename": f"{name}@2x.png"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    if template:
        contents["properties"] = {"template-rendering-intent": "template"}
    (d / "Contents.json").write_text(json.dumps(contents, indent=2))


def square(img: Image.Image, size: int, pad: float = 0.0) -> Image.Image:
    s = fit(img, int(size * (1 - pad)))
    c = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c.alpha_composite(s, ((size - s.width) // 2, (size - s.height) // 2))
    return c


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("uso: make_icon.py logo.png")
    sym = extract_symbol(Path(sys.argv[1]))

    icon = make_app_icon(sym)
    write_appiconset(icon)
    icon.save(ROOT / "Resources" / "AppIcon-1024.png")

    # barra de menus: silhueta preta (template), 18 pt
    a = np.asarray(sym).copy()
    a[..., :3] = 0
    mono = Image.fromarray(a, "RGBA")
    write_imageset("MenuBarIcon", square(mono, 18), square(mono, 36), template=True)

    # símbolo vermelho para telas do app
    write_imageset("BrandMark", square(sym, 128), square(sym, 256))

    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    acc = ASSETS / "AccentColor.colorset"
    acc.mkdir(exist_ok=True)
    r, g, b = (f"{v / 255:.3f}" for v in BRAND_RED)
    (acc / "Contents.json").write_text(json.dumps({
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb",
                    "components": {"red": r, "green": g, "blue": b, "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1}}, indent=2))
    print("ícones gerados em", ASSETS)


if __name__ == "__main__":
    main()
