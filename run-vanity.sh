#!/bin/bash

echo "========================================"
echo "Solana Vanity Address Generator"
echo "========================================"
echo

# Check if executable exists
if [ ! -f "src/release/cuda_ed25519_vanity" ]; then
    echo "ERROR: cuda_ed25519_vanity not found!"
    echo "Please run build.sh first to compile the project."
    echo
    exit 1
fi

# Copy config file if it exists in root
if [ -f "vanity-config.json" ]; then
    echo "Copying vanity-config.json to executable directory..."
    cp vanity-config.json src/release/
    echo
fi

# Run the vanity generator
cd src/release
echo "Starting vanity address generator..."
echo
./cuda_ed25519_vanity

echo
echo "========================================"
echo "Generator stopped"
echo "========================================"
