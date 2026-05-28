#!/bin/bash
# Generate Hive TypeAdapter .g.dart files.
# Run this from the project root: bash scripts/build_adapters.sh
#
# Prerequisites:
#   flutter pub get
#
# This script runs build_runner to generate the .g.dart files for all
# models annotated with @HiveType. The generated files contain the
# TypeAdapter implementations (e.g., StudentAdapter, ClassInfoAdapter).
#
# After running, commit the generated .g.dart files to the repo.

set -e

echo "🔧 Running build_runner for Hive adapters..."
flutter pub run build_runner build --delete-conflicting-outputs

echo "✅ Generated .g.dart files:"
find lib/models -name "*.g.dart" -type f | sort

echo ""
echo "Run 'flutter analyze' to verify, then commit the .g.dart files."
