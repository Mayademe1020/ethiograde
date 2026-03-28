# TFLite models go here
# Download or train models and place them as:
# - amharic_ocr.tflite  (Amharic/Ge'ez handwriting recognition)
# - answer_detector.tflite (answer region detection)
# - text_enhancer.tflite (image enhancement model)

# For now, the app uses:
# 1. Image processing (contrast/sharpen/binarize) from the `image` package
# 2. Google ML Kit text recognition (offline, no internet needed)
# 3. Rule-based Amharic/English letter matching

# To add a custom TFLite model:
# 1. Place .tflite file in this directory
# 2. Update pubspec.yaml assets section
# 3. Load in ocr_service.dart using tflite_flutter
