#!/usr/bin/env python3
"""
Region-focused dHash: crop to answer area before hashing.
The answer bubbles are where differences actually live.
"""
from PIL import Image, ImageDraw
import random

def dhash(img, hash_size=8):
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

print("Region-focused dHash — crop to answer bubbles")
print("=" * 55)

papers = [create_paper(seed=i*100) for i in range(10)]

# Crop to answer region: x=[60,350], y=[85,730] (bubbles area)
def crop_bubbles(img):
    return img.crop((60, 85, 350, 730))

# Full image hash (current approach)
print("\n── Full image (64 bits) ──")
hashes_full = [dhash(p) for p in papers]
same_noisy = hamming(hashes_full[0], dhash(noisy_copy(papers[0]), 8))
diff_min = min(hamming(hashes_full[i], hashes_full[j]) for i in range(10) for j in range(i+1, 10))
fp_6 = sum(1 for i in range(10) for j in range(i+1, 10) if hamming(hashes_full[i], hashes_full[j]) <= 6)
print(f"  Same paper noisy: distance {same_noisy}")
print(f"  Different papers: min distance {diff_min}, FP@6={fp_6}/45")

# Cropped bubble region hash
print("\n── Bubble region only (64 bits) ──")
hashes_crop = [dhash(crop_bubbles(p)) for p in papers]
same_noisy_c = hamming(hashes_crop[0], dhash(crop_bubbles(noisy_copy(papers[0]))))
diff_min_c = min(hamming(hashes_crop[i], hashes_crop[j]) for i in range(10) for j in range(i+1, 10))
fp_6_c = sum(1 for i in range(10) for j in range(i+1, 10) if hamming(hashes_crop[i], hashes_crop[j]) <= 6)
print(f"  Same paper noisy: distance {same_noisy_c}")
print(f"  Different papers: min distance {diff_min_c}, FP@6={fp_6_c}/45")

# Combined: two hashes (full + cropped)
print("\n── Combined: full(64) + bubble(64) → 128 bits total ──")
# Combine into single check: both must be within threshold
def combined_dup(p1, p2, threshold=6):
    h1a, h2a = dhash(p1), dhash(crop_bubbles(p1))
    h1b, h2b = dhash(p2), dhash(crop_bubbles(p2))
    d1 = hamming(h1a, h1b)
    d2 = hamming(h2a, h2b)
    return d1 <= threshold and d2 <= threshold, d1, d2

# Same paper
_, d1, d2 = combined_dup(papers[0], noisy_copy(papers[0]))
print(f"  Same paper noisy: full={d1}, bubble={d2} → duplicate={d1<=6 and d2<=6}")

# Different papers
fp_combined = 0
min_d1, min_d2 = 99, 99
for i in range(10):
    for j in range(i+1, 10):
        is_dup, d1, d2 = combined_dup(papers[i], papers[j])
        min_d1 = min(min_d1, d1)
        min_d2 = min(min_d2, d2)
        if is_dup:
            fp_combined += 1
print(f"  Different papers: min full={min_d1}, min bubble={min_d2}, FP={fp_combined}/45")

# Brightness change
bright = papers[0].point(lambda p: min(255, int(p * 1.15)))
_, d1, d2 = combined_dup(papers[0], bright)
print(f"  Same paper bright: full={d1}, bubble={d2} → duplicate={d1<=6 and d2<=6}")

# Crop test
orig = papers[0]
cropped = orig.crop((3, 3, orig.width-3, orig.height-3))
_, d1, d2 = combined_dup(papers[0], cropped)
print(f"  Same paper cropped: full={d1}, bubble={d2} → duplicate={d1<=6 and d2<=6}")
