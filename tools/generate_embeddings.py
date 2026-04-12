#!/usr/bin/env python3
"""
SGS Card Scanner — MobileNetV2 Embedding Generator

Generates two files:
  1. assets/models/mobilenet_v2.tflite  — TFLite feature extractor model
  2. assets/data/general_embeddings.bin — Versioned reference bundle

Binary format of general_embeddings.bin (v2):
  - 4 bytes: magic "SGSV"
  - 4 bytes: version uint32 little-endian
  - 4 bytes: embedding dim uint32 little-endian
  - 4 bytes: reference count uint32 little-endian
  - For each reference:
      - 4 bytes: reference ID string length
      - N bytes: reference ID string (UTF-8, e.g. "YJ_WU033#canonical")
      - 4 bytes: logical card ID string length
      - N bytes: logical card ID string (UTF-8, e.g. "YJ_WU033")
      - 1 byte: reference type enum
      - 5120 bytes: 1280 x float32 embedding (little-endian)

Usage:
  cd "D:\\PROJECTS\\SGS TRANSLATION APP"
  python tools/generate_embeddings.py

Prerequisites:
  pip install tensorflow Pillow numpy
"""

import os
import sys
import struct
import numpy as np
from pathlib import Path

# ── Resolve project root (script is in tools/, project root is parent)
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
GENERALS_DIR = PROJECT_ROOT / "assets" / "images" / "generals"
MODELS_DIR = PROJECT_ROOT / "assets" / "models"
OUTPUT_BIN = PROJECT_ROOT / "assets" / "data" / "general_embeddings.bin"
OUTPUT_TFLITE = MODELS_DIR / "mobilenet_v2.tflite"

# MobileNetV2 settings (must match image_embedding_matcher.dart exactly)
INPUT_SIZE = 224
EMBEDDING_DIM = 1280
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]
BUNDLE_MAGIC = b"SGSV"
BUNDLE_VERSION = 2
REFERENCE_TYPE_CANONICAL = 0


def step1_create_tflite_model():
    """Convert MobileNetV2 (no-top) to TFLite feature extractor."""
    print("=" * 60)
    print("STEP 1: Creating TFLite model")
    print("=" * 60)

    if OUTPUT_TFLITE.exists():
        size_mb = OUTPUT_TFLITE.stat().st_size / (1024 * 1024)
        print(f"  Model already exists: {OUTPUT_TFLITE} ({size_mb:.1f} MB)")
        print("  Delete it to regenerate. Skipping.")
        return

    import tensorflow as tf

    print("  Loading MobileNetV2 (no-top, ImageNet weights)...")
    model = tf.keras.applications.MobileNetV2(
        input_shape=(INPUT_SIZE, INPUT_SIZE, 3),
        include_top=False,
        pooling="avg",
        weights="imagenet",
    )
    print(f"  Model output shape: {model.output_shape}")

    print("  Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = []
    tflite_model = converter.convert()

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_TFLITE.write_bytes(tflite_model)
    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"  Saved: {OUTPUT_TFLITE} ({size_mb:.1f} MB)")


def step2_generate_embeddings():
    """Run all general reference images through MobileNetV2 and save embeddings."""
    print()
    print("=" * 60)
    print("STEP 2: Generating embeddings for all generals")
    print("=" * 60)

    import tensorflow as tf
    from PIL import Image

    if not OUTPUT_TFLITE.exists():
        print(f"  ERROR: TFLite model not found at {OUTPUT_TFLITE}")
        print("  Run step 1 first.")
        sys.exit(1)

    interpreter = tf.lite.Interpreter(model_path=str(OUTPUT_TFLITE))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    print(f"  Input shape:  {input_details[0]['shape']}")
    print(f"  Output shape: {output_details[0]['shape']}")

    if not GENERALS_DIR.exists():
        print(f"  ERROR: Generals directory not found: {GENERALS_DIR}")
        sys.exit(1)

    image_files = sorted(GENERALS_DIR.glob("*.webp"))
    print(f"  Found {len(image_files)} general images in {GENERALS_DIR}")

    if len(image_files) == 0:
        print("  ERROR: No .webp files found. Check the directory path.")
        sys.exit(1)

    embeddings = {}
    errors = []

    for i, img_path in enumerate(image_files):
        card_id = img_path.stem

        try:
            pil_img = Image.open(img_path).convert("RGB")
            pil_img = pil_img.resize((INPUT_SIZE, INPUT_SIZE), Image.LANCZOS)
            img_array = np.array(pil_img, dtype=np.float32) / 255.0

            for c in range(3):
                img_array[:, :, c] = (img_array[:, :, c] - IMAGENET_MEAN[c]) / IMAGENET_STD[c]

            input_data = np.expand_dims(img_array, axis=0)

            interpreter.set_tensor(input_details[0]["index"], input_data)
            interpreter.invoke()
            output_data = interpreter.get_tensor(output_details[0]["index"])

            embedding = output_data[0]
            norm = np.linalg.norm(embedding)
            if norm > 1e-10:
                embedding = embedding / norm

            embeddings[card_id] = embedding

            if (i + 1) % 50 == 0 or (i + 1) == len(image_files):
                print(f"  Processed {i + 1}/{len(image_files)}: {card_id}")

        except Exception as e:
            errors.append((card_id, str(e)))
            print(f"  WARNING: Failed to process {card_id}: {e}")

    print(f"\n  Successfully embedded: {len(embeddings)}/{len(image_files)}")
    if errors:
        print(f"  Errors: {len(errors)}")
        for card_id, err in errors:
            print(f"    - {card_id}: {err}")

    print(f"\n  Writing {OUTPUT_BIN}...")
    OUTPUT_BIN.parent.mkdir(parents=True, exist_ok=True)

    with open(OUTPUT_BIN, "wb") as f:
        f.write(BUNDLE_MAGIC)
        f.write(struct.pack("<I", BUNDLE_VERSION))
        f.write(struct.pack("<I", EMBEDDING_DIM))
        f.write(struct.pack("<I", len(embeddings)))

        for card_id, embedding in sorted(embeddings.items()):
            reference_id = f"{card_id}#canonical"
            reference_id_bytes = reference_id.encode("utf-8")
            logical_id_bytes = card_id.encode("utf-8")
            f.write(struct.pack("<I", len(reference_id_bytes)))
            f.write(reference_id_bytes)
            f.write(struct.pack("<I", len(logical_id_bytes)))
            f.write(logical_id_bytes)
            f.write(struct.pack("<B", REFERENCE_TYPE_CANONICAL))
            f.write(struct.pack(f"<{EMBEDDING_DIM}f", *embedding))

    size_mb = OUTPUT_BIN.stat().st_size / (1024 * 1024)
    print(f"  Saved: {OUTPUT_BIN} ({size_mb:.1f} MB)")
    print(f"  Contains {len(embeddings)} embeddings x {EMBEDDING_DIM} dims")


def step3_verify():
    """Quick sanity check: load the binary and verify structure."""
    print()
    print("=" * 60)
    print("STEP 3: Verification")
    print("=" * 60)

    if not OUTPUT_BIN.exists():
        print(f"  ERROR: {OUTPUT_BIN} not found")
        return

    with open(OUTPUT_BIN, "rb") as f:
        magic = f.read(4)
        version = struct.unpack("<I", f.read(4))[0]
        dim = struct.unpack("<I", f.read(4))[0]
        count = struct.unpack("<I", f.read(4))[0]
        print(f"  Magic: {magic!r}")
        print(f"  Version: {version}")
        print(f"  Embedding dim: {dim}")
        print(f"  Entry count: {count}")

        for i in range(min(3, count)):
            ref_len = struct.unpack("<I", f.read(4))[0]
            reference_id = f.read(ref_len).decode("utf-8")
            logical_len = struct.unpack("<I", f.read(4))[0]
            logical_id = f.read(logical_len).decode("utf-8")
            ref_type = struct.unpack("<B", f.read(1))[0]
            embedding = struct.unpack(f"<{EMBEDDING_DIM}f", f.read(EMBEDDING_DIM * 4))
            emb_norm = np.linalg.norm(embedding)
            print(
                f"  [{i}] ref={reference_id}, logical={logical_id}, "
                f"type={ref_type}, dim={len(embedding)}, L2_norm={emb_norm:.4f}"
            )

    tflite_size = OUTPUT_TFLITE.stat().st_size / (1024 * 1024) if OUTPUT_TFLITE.exists() else 0
    bin_size = OUTPUT_BIN.stat().st_size / (1024 * 1024)
    print(f"\n  Model size:      {tflite_size:.1f} MB")
    print(f"  Embeddings size: {bin_size:.1f} MB")
    print(f"  Total added:     {tflite_size + bin_size:.1f} MB")
    print()
    print("  All done! Run your Flutter app — the scanner will now")
    print("  use ML embeddings for visual matching.")


if __name__ == "__main__":
    print()
    print("  SGS Card Scanner — Embedding Generator")
    print(f"  Project: {PROJECT_ROOT}")
    print()

    step1_create_tflite_model()
    step2_generate_embeddings()
    step3_verify()
