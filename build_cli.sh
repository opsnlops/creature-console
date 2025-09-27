#!/bin/bash

# Build script for creature-cli release version
# Builds the CLI tool and copies it to cli/ directory

set -e  # Exit on any error

echo "Building creature-cli release version..."

# Navigate to Common directory and build
pushd Common
swift build -c release --target creature-cli
popd

echo "Build completed successfully!"

# Create cli directory if it doesn't exist
mkdir -p cli

# Copy the built executable
cp Common/.build/arm64-apple-macosx/release/creature-cli cli/

echo "creature-cli copied to cli/creature-cli"
echo "✅ Release build complete!"