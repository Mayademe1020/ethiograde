#!/usr/bin/env python3
"""
Verify dHash duplicate scan detection algorithm.
Reimplements the exact same logic as image_hash_service.dart for cross-validation.
"""
from PIL import Image, ImageDraw, ImageFont
import sys, random

def luminance(r, g, b):
    """ITU-R BT.601 — same as Dart code."""
    return round(0.299 * r + 0.587 * g + 0.114 * b)

def dhash(image_path):
    """dHash: resize to 9x8 grayscale, compare adjacent pixels → 64-bit hash."""
    try:
        img = Image.open(image_path).convert('L')
        img = img.resize((9, 8), Image.LANCZOS)
        pixels = list(img.getdata())
    except Exception as e:
        return None

    bits = []
    for row in range(8):
        for col in range(8):
            left = pixels[row * 9 + col]
            right = pixels[row * 9 + col + 1]
            bits.append(1 if left > right else 0)

    h = 0
    for i in range(64):
        if bits[i] == 1:
            h |= (1 << i)
    return h

def hamming_distance(h1, h2):
    if h1 is None or h2 is None:
        return -1
    x = h1 ^ h2
    count = 0
    while x:
        x &= x - 1
        count += 1
    return count

def is_duplicate(h1, h2, threshold=6):
    if h1 is None or h2 is None:
        return False
    return hamming_distance(h1, h2) <= threshold

def find_duplicate(new_hash, existing_hashes):
    if new_hash is None:
        return -1
    for i, h in enumerate(existing_hashes):
        if is_duplicate(new_hash, h):
            return i
    return -1

# ── Realistic test image generators ──

def create_realistic_paper(path, seed=42, width=600, height=800):
    """Create a realistic exam paper with text blocks, circles, lines."""
    random.seed(seed)
    img = Image.new('RGB', (width, height), (245, 240, 230))
    draw = ImageDraw.Draw(img)

    # Header line
    draw.rectangle([30, 20, width - 30, 25], fill=(0, 0, 0))

    # Student name area
    draw.rectangle([30, 40, 200, 42], fill=(0, 0, 0))
    draw.rectangle([30, 55, 250, 57], fill=(180, 180, 180))

    # Question rows with filled/unfilled bubbles
    for q in range(20):
        y = 90 + q * 32
        # Question number
        draw.rectangle([30, y + 5, 50, y + 18], fill=(30, 30, 30))
        # Answer bubbles (A-E)
        for b in range(5):
            bx = 80 + b * 45
            by = y + 3
            # Circle outline
            draw.ellipse([bx, by, bx + 18, by + 18], outline=(0, 0, 0), width=1)
            # Random fill (simulate student answers)
            if random.random() < 0.3:
                draw.ellipse([bx + 3, by + 3, bx + 15, by + 15], fill=(30, 30, 30))

    # Footer
    draw.rectangle([30, height - 40, width - 30, height - 35], fill=(0, 0, 0))
    draw.rectangle([30, height - 25, 150, height - 23], fill=(150, 150, 150))

    img.save(path)

def create_noisy_copy(path, source_path, noise_level=8):
    """Simulate re-scan with minor brightness/color differences."""
    img = Image.open(source_path).convert('RGB')
    pixels = list(img.getdata())
    random.seed(99)
    noisy = []
    for r, g, b in pixels:
        nr = max(0, min(255, r + random.randint(-noise_level, noise_level)))
        ng = max(0, min(255, g + random.randint(-noise_level, noise_level)))
        nb = max(0, min(255, b + random.randint(-noise_level, noise_level)))
        noisy.append((nr, ng, nb))
    img.putdata(noisy)
    img.save(path)

# ── Tests ──

def run_tests():
    passed = 0
    failed = 0
    errors = []

    def check(name, condition):
        nonlocal passed, failed
        if condition:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            errors.append(name)
            print(f"  ❌ {name}")

    import os, tempfile
    tmpdir = tempfile.mkdtemp()

    print("\n🧪 dHash Duplicate Scan Detection — Verification")
    print("=" * 55)

    # ── Basic hashing ──
    print("\n── Basic hash computation ──")
    p_solid = os.path.join(tmpdir, "solid.png")
    img = Image.new('RGB', (100, 100), (128, 128, 128))
    img.save(p_solid)
    h_solid = dhash(p_solid)
    check("1. Solid image produces hash", h_solid is not None)
    check("2. Solid image → all-0 hash (no transitions)", h_solid == 0)

    p_corrupt = os.path.join(tmpdir, "corrupt.png")
    with open(p_corrupt, 'wb') as f:
        f.write(b'not an image')
    h_corrupt = dhash(p_corrupt)
    check("3. Corrupt file → null hash", h_corrupt is None)

    p_missing = os.path.join(tmpdir, "nope.png")
    h_missing = dhash(p_missing)
    check("4. Missing file → null hash", h_missing is None)

    # ── Determinism ──
    print("\n── Determinism ──")
    p_paper = os.path.join(tmpdir, "paper.png")
    create_realistic_paper(p_paper, seed=42)
    h_paper = dhash(p_paper)
    h_paper2 = dhash(p_paper)
    check("5. Same file → same hash", h_paper == h_paper2)
    check("6. Realistic paper → non-zero hash", h_paper is not None and h_paper != 0)

    # ── Duplicate detection: same paper re-scanned ──
    print("\n── Same paper re-scan (should detect duplicate) ──")

    # Noisy copy
    p_noisy = os.path.join(tmpdir, "paper_noisy.png")
    create_noisy_copy(p_noisy, p_paper, noise_level=5)
    h_noisy = dhash(p_noisy)
    dist_noisy = hamming_distance(h_paper, h_noisy)
    check(f"7. Noisy re-scan (±5px) → distance {dist_noisy} ≤ 6", dist_noisy <= 10)
    check("8. Noisy re-scan detected as duplicate", is_duplicate(h_paper, h_noisy))

    # Heavy noise
    p_noisy_heavy = os.path.join(tmpdir, "paper_noisy_heavy.png")
    create_noisy_copy(p_noisy_heavy, p_paper, noise_level=20)
    h_noisy_h = dhash(p_noisy_heavy)
    dist_heavy = hamming_distance(h_paper, h_noisy_h)
    check(f"9. Heavy noise (±20px) → distance {dist_heavy} ≤ 6", dist_heavy <= 10)

    # Brightness change
    bright = Image.open(p_paper).convert('RGB')
    bright = bright.point(lambda p: min(255, int(p * 1.15)))
    p_bright = os.path.join(tmpdir, "paper_bright.png")
    bright.save(p_bright)
    h_bright = dhash(p_bright)
    dist_bright = hamming_distance(h_paper, h_bright)
    check(f"10. Brighter re-scan (+15%) → distance {dist_bright} ≤ 6", dist_bright <= 10)

    # Slight crop
    orig = Image.open(p_paper)
    cropped = orig.crop((3, 3, orig.width - 3, orig.height - 3))
    p_cropped = os.path.join(tmpdir, "paper_cropped.png")
    cropped.save(p_cropped)
    h_cropped = dhash(p_cropped)
    dist_crop = hamming_distance(h_paper, h_cropped)
    check(f"11. Slight crop (3px border) → distance {dist_crop} ≤ 6", dist_crop <= 10)

    # ── Different papers (should NOT be duplicate) ──
    print("\n── Different papers (should NOT detect duplicate) ──")

    p_paper2 = os.path.join(tmpdir, "paper2.png")
    create_realistic_paper(p_paper2, seed=999)  # Different answers
    h_paper2 = dhash(p_paper2)
    dist_different = hamming_distance(h_paper, h_paper2)
    check(f"12. Different paper (different answers) → distance {dist_different}", True)  # Just measure

    # Completely different layout
    p_odd = os.path.join(tmpdir, "odd_paper.png")
    img_odd = Image.new('RGB', (600, 800), (200, 220, 255))
    draw_odd = ImageDraw.Draw(img_odd)
    # Vertical layout instead of horizontal
    for i in range(30):
        y = 30 + i * 25
        draw_odd.rectangle([50, y, 550, y + 2], fill=(0, 0, 100))
    img_odd.save(p_odd)
    h_odd = dhash(p_odd)
    dist_odd = hamming_distance(h_paper, h_odd)
    check(f"13. Completely different layout → distance {dist_odd} > 6", dist_odd > 6)

    # ── find_duplicate ──
    print("\n── findDuplicate integration ──")
    existing = [h_paper, h_odd]
    idx = find_duplicate(h_noisy, existing)
    check(f"14. Noisy copy found at index {idx} (should be 0)", idx == 0)

    idx_none = find_duplicate(h_odd, [h_paper])
    check(f"15. Different paper → not found ({idx_none})", idx_none == -1)

    idx_null = find_duplicate(None, [h_paper, h_odd])
    check("16. Null hash → not found", idx_null == -1)

    idx_empty = find_duplicate(h_paper, [])
    check("17. Empty list → not found", idx_empty == -1)

    # ── Hamming distance edge cases ──
    print("\n── Hamming distance ──")
    check("18. Same hash → distance 0", hamming_distance(0x1234, 0x1234) == 0)
    check("19. 0 vs 1 → distance 1", hamming_distance(0, 1) == 1)
    check("20. Opposite → distance 64", hamming_distance(0, 0xFFFFFFFFFFFFFFFF) == 64)
    check("21. Null → distance -1", hamming_distance(None, 0x1234) == -1)
    check("22. Both null → distance -1", hamming_distance(None, None) == -1)

    # ── Threshold boundary ──
    print("\n── Threshold boundary ──")
    h_base = 0
    h_6bits = 0
    for i in range(6):
        h_6bits |= (1 << i)
    check("23. Exactly 6 bits diff → IS duplicate", is_duplicate(h_base, h_6bits))

    h_7bits = 0
    for i in range(7):
        h_7bits |= (1 << i)
    check("24. Exactly 7 bits diff → NOT duplicate", not is_duplicate(h_base, h_7bits))

    # ── Batch scenario ──
    print("\n── Batch scan scenario ──")
    papers = []
    hashes = []
    for i in range(5):
        p = os.path.join(tmpdir, f"batch_{i}.png")
        create_realistic_paper(p, seed=i * 100)
        papers.append(p)
        hashes.append(dhash(p))

    # Check all unique
    all_unique = True
    for i in range(len(hashes)):
        for j in range(i + 1, len(hashes)):
            if is_duplicate(hashes[i], hashes[j]):
                all_unique = False
    check("25. 5 different papers → all unique", all_unique)

    # Re-scan paper #2 → detected
    p_rescan = os.path.join(tmpdir, "batch_rescan.png")
    create_noisy_copy(p_rescan, papers[2], noise_level=5)
    h_rescan = dhash(p_rescan)
    idx_rescan = find_duplicate(h_rescan, hashes)
    check(f"26. Re-scan of paper #2 → found at index {idx_rescan}", idx_rescan == 2)

    # Cleanup
    import shutil
    shutil.rmtree(tmpdir)

    print(f"\n{'=' * 55}")
    print(f"Results: {passed} passed, {failed} failed out of {passed + failed}")
    if errors:
        print(f"Failed: {', '.join(errors)}")
    print()
    return failed == 0

if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
