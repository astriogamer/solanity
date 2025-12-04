#!/bin/bash

echo "========================================"
echo "Building Solana Vanity Address Generator"
echo "========================================"
echo

# Set build mode (release or debug)
BUILD_MODE=release

# Navigate to src directory and build
echo "Building in $BUILD_MODE mode..."
cd src
make V=$BUILD_MODE

if [ $? -ne 0 ]; then
    echo
    echo "========================================"
    echo "BUILD FAILED!"
    echo "========================================"
    exit 1
fi

echo
echo "========================================"
echo "BUILD SUCCESSFUL!"
echo "========================================"
echo
echo "Executable location: src/$BUILD_MODE/cuda_ed25519_vanity"
echo
echo "To run the vanity generator:"
echo "  cd src/$BUILD_MODE"
echo "  ./cuda_ed25519_vanity"
echo
echo "Or copy vanity-config.json to src/$BUILD_MODE/ and run from there"
echo "========================================"
