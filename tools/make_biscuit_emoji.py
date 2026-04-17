#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "a_digital_emoji_emoji_features_a_single_tea_biscui.png"
OUTPUT = ROOT / "assets" / "biscuit-emoji.png"
CANVAS_SIZE = 64
CONTENT_SIZE = 56


def average_corner_color(image: Image.Image, sample_size: int = 8) -> tuple[int, int, int]:
    width, height = image.size
    samples: list[tuple[int, int, int]] = []
    for x in range(sample_size):
        for y in range(sample_size):
            samples.extend(
                [
                    image.getpixel((x, y))[:3],
                    image.getpixel((width - 1 - x, y))[:3],
                    image.getpixel((x, height - 1 - y))[:3],
                    image.getpixel((width - 1 - x, height - 1 - y))[:3],
                ]
            )
    count = len(samples)
    return tuple(sum(pixel[i] for pixel in samples) // count for i in range(3))


def is_background(pixel: tuple[int, int, int, int], bg_rgb: tuple[int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return True
    brightness = (red + green + blue) / 3
    chroma = max(red, green, blue) - min(red, green, blue)
    distance = ((red - bg_rgb[0]) ** 2 + (green - bg_rgb[1]) ** 2 + (blue - bg_rgb[2]) ** 2) ** 0.5
    return brightness >= 230 and chroma <= 35 and distance <= 48


def flood_fill_background(image: Image.Image, bg_rgb: tuple[int, int, int]) -> Image.Image:
    width, height = image.size
    mask = Image.new("L", image.size, 255)
    visited: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque(
        [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    )

    while queue:
        x, y = queue.popleft()
        if (x, y) in visited:
            continue
        visited.add((x, y))
        if not is_background(image.getpixel((x, y)), bg_rgb):
            continue
        mask.putpixel((x, y), 0)
        if x > 0:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y > 0:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    return mask.filter(ImageFilter.GaussianBlur(radius=1.0))


def build_emoji(source_path: Path, output_path: Path) -> None:
    image = Image.open(source_path).convert("RGBA")
    bg_rgb = average_corner_color(image)
    mask = flood_fill_background(image, bg_rgb)

    image.putalpha(mask)
    bbox = image.getbbox()
    if bbox is None:
        raise RuntimeError("Could not find biscuit content after background removal")

    image = image.crop(bbox)
    image.thumbnail((CONTENT_SIZE, CONTENT_SIZE), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    offset = ((CANVAS_SIZE - image.width) // 2, (CANVAS_SIZE - image.height) // 2)
    canvas.alpha_composite(image, offset)
    canvas.save(output_path)


if __name__ == "__main__":
    build_emoji(SOURCE, OUTPUT)
