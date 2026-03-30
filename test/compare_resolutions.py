#!/usr/bin/env python3
"""
Compare dHash at different resolutions to find the sweet spot.
9×8 = 64 bits (current) vs 16×15 = 240 bits vs 32×31 = 992 bits
"""
from PIL import Image, ImageDraw
import random

def dhash(img, hash_size=8):
    """dHash at configurable resolution. hash_size=8 → 9×8 → 64 bits."""
    w = hash_size + 1
    h = hash_size
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

def create_paper(seed, width=600, height=800):
    random.seed(seed)
    img = Image.new('RGB', (width, height), (245, 240, 230))
    draw = ImageDraw.Draw(img)
    draw.rectangle([30, 20, width-30, 25], fill=(0,0,0))
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
    draw.rectangle([30, height-40, width-30, height-35], fill=(0,0,0))
    return img

def noisy_copy(img, noise=5):
    pixels = list(img.getdata())
    random.seed(99)
    noisy = []
    for r, g, b in pixels:
        nr = max(0, min(255, r + random.randint(-noise, noise)))
        ng = max(0, min(255, g + random.randint(-noise, noise)))
        nb = max(0, min(255, b + random.randint(-noise, noise)))
        noisy.append((nr, ng, nb))
    result = img.copy()
    result.putdata(noisy)
    return result

# Test at different resolutions
for hash_size in [8, 12, 16]:
    total_bits = hash_size * hash_size
    threshold = max(3, total_bits // 10)  # ~10% tolerance
    print(f"\n{'='*60}")
    print(f"Resolution: {hash_size}×{hash_size} = {total_bits} bits, threshold={threshold}")
    print(f"{'='*60}")

    # Create papers
    papers = [create_paper(seed=i*100) for i in range(10)]
    hashes = [dhash(p, hash_size) for p in papers]

    # Same paper tests
    noisy = noisy_copy(papers[0], noise=5)
    bright = papers[0].point(lambda p: min(255, int(p * 1.15)))
    h_noisy = dhash(noisy, hash_size)
    h_bright = dhash(bright, hash_size)
    d_noisy = hamming(hashes[0], h_noisy)
    d_bright = hamming(hashes[0], h_bright)

    print(f"  Same paper noisy (±5):    distance {d_noisy:4d}  {'✅' if d_noisy <= threshold else '❌'}")
    print(f"  Same paper bright (+15%): distance {d_bright:4d}  {'✅' if d_bright <= threshold else '❌'}")

    # Different papers
    false_positives = 0
    total_pairs = 0
    min_dist = 999
    for i in range(10):
        for j in range(i+1, 10):
            d = hamming(hashes[i], hashes[j])
            total_pairs += 1
            min_dist = min(min_dist, d)
            if d <= threshold:
                false_positives += 1
    print(f"  Different papers:         min={min_dist:4d}, FP={false_positives}/{total_pairs}  {'✅' if false_positives == 0 else '❌'}")
