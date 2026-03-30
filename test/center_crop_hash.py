#!/usr/bin/env python3
"""Final approach: center-crop dHash — exclude edges, hash content region."""
from PIL import Image, ImageDraw
import random

def dhash(img, hash_size=8):
    w, h = hash_size + 1, hash_size
    img = img.convert('L').resize((w, h), Image.LANCZOS)
    pixels = list(img.getdata())
    bits = []
    for row in range(h):
        for col in range(hash_size):
            left = pixels[row * w + col]
            right = pixels[row * w + col + 1]
            bits.append(1 if left > right else 0)
    h_val = 0
    for i in range(len(bits)):
        if bits[i] == 1:
            h_val |= (1 << i)
    return h_val

def hamming(h1, h2):
    x = h1 ^ h2
    count = 0
    while x:
        x &= x - 1
        count += 1
    return count

def create_paper(seed, w=600, h=800):
    random.seed(seed)
    img = Image.new('RGB', (w, h), (245, 240, 230))
    draw = ImageDraw.Draw(img)
    draw.rectangle([30, 20, w-30, 25], fill=(0,0,0))
    draw.rectangle([30, 40, 200, 42], fill=(0,0,0))
    draw.rectangle([30, 55, 250, 57], fill=(180,180,180))
    for q in range(20):
        y = 90 + q * 32
        draw.rectangle([30, y+5, 50, y+18], fill=(30,30,30))
        for b in range(5):
            bx = 80 + b * 45
            by = y + 3
            draw.ellipse([bx, by, bx+18, by+18], outline=(0,0,0), width=1)
            if random.random() < 0.3:
                draw.ellipse([bx+3, by+3, bx+15, by+15], fill=(30,30,30))
    draw.rectangle([30, h-40, w-30, h-35], fill=(0,0,0))
    return img

def noisy_copy(img, noise=5):
    px = list(img.getdata())
    random.seed(99)
    result = img.copy()
    result.putdata([tuple(max(0,min(255,c+random.randint(-noise,noise))) for c in p) for p in px])
    return result

def center_crop(img, pct=0.5):
    """Crop to center pct of image (removes headers/footers)."""
    w, h = img.size
    mx, my = int(w * (1-pct)/2), int(h * (1-pct)/2)
    return img.crop((mx, my, w-mx, h-my))

print("Center-crop dHash (50%) — excludes uniform edges")
print("=" * 55)

papers = [create_paper(seed=i*100) for i in range(10)]

# Hash with center crop
def hash_paper(img):
    cropped = center_crop(img, 0.5)
    return dhash(cropped)

hashes = [hash_paper(p) for p in papers]

# Same paper tests
tests = [
    ("Noisy ±5",    noisy_copy(papers[0], 5)),
    ("Noisy ±20",   noisy_copy(papers[0], 20)),
    ("Bright +15%", papers[0].point(lambda p: min(255, int(p*1.15)))),
    ("Dark -15%",   papers[0].point(lambda p: max(0, int(p*0.85)))),
    ("Cropped 3px", papers[0].crop((3,3,597,797))),
]
print("\n── Same paper re-scans ──")
for label, variant in tests:
    d = hamming(hashes[0], hash_paper(variant))
    print(f"  {label:20s}: distance {d:3d}  {'✅' if d <= 6 else '❌'}")

# Different papers
print("\n── Different papers ──")
all_dists = []
for i in range(10):
    for j in range(i+1, 10):
        d = hamming(hashes[i], hashes[j])
        all_dists.append(d)
all_dists.sort()
fp = sum(1 for d in all_dists if d <= 6)
print(f"  Min distance:  {all_dists[0]}")
print(f"  Median:        {all_dists[len(all_dists)//2]}")
print(f"  Max distance:  {all_dists[-1]}")
print(f"  FP @thresh=6:  {fp}/45  {'✅' if fp == 0 else '❌'}")
print(f"  FP @thresh=8:  {sum(1 for d in all_dists if d <= 8)}/45")
print(f"  FP @thresh=10: {sum(1 for d in all_dists if d <= 10)}/45")

# Distance distribution
print("\n── Distance distribution ──")
for t in range(0, 25, 2):
    count = sum(1 for d in all_dists if t <= d < t+2)
    bar = '█' * count
    print(f"  {t:2d}-{t+1}: {bar} ({count})")
