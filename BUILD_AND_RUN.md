# Building and Running the Vanity Address Generator

## Quick Start

### Windows

1. **Build the project:**
   ```cmd
   build.bat
   ```

2. **Run the generator:**
   ```cmd
   run-vanity.bat
   ```

### Linux/Mac

1. **Make scripts executable:**
   ```bash
   chmod +x build.sh run-vanity.sh
   ```

2. **Build the project:**
   ```bash
   ./build.sh
   ```

3. **Run the generator:**
   ```bash
   ./run-vanity.sh
   ```

## What These Scripts Do

### Build Scripts (`build.bat` / `build.sh`)

- Compiles the CUDA vanity address generator in **release mode** for optimal performance
- Creates the executable at `src/release/cuda_ed25519_vanity` (or `.exe` on Windows)
- Shows clear success/error messages
- Requires NVIDIA CUDA toolkit to be installed

### Run Scripts (`run-vanity.bat` / `run-vanity.sh`)

- Checks if the executable exists (reminds you to build if not)
- Automatically copies `vanity-config.json` to the executable directory
- Runs the vanity generator
- Handles proper directory navigation

## Prerequisites

Before building, ensure you have:

1. **NVIDIA CUDA Toolkit** installed (version 9.2 or higher)
   - Download from: https://developer.nvidia.com/cuda-downloads
   - Make sure `nvcc` is in your PATH

2. **Compatible NVIDIA GPU** with CUDA support
   - Check compatibility: https://developer.nvidia.com/cuda-gpus

3. **Build tools:**
   - **Windows**: Visual Studio Build Tools or MinGW with `make`
   - **Linux**: `build-essential` package (`sudo apt install build-essential`)
   - **Mac**: Xcode Command Line Tools (`xcode-select --install`)

## Manual Build (Advanced)

If you prefer to build manually:

```bash
cd src
make V=release
```

For debug build:
```bash
cd src
make V=debug
```

## Manual Run (Advanced)

After building:

**Linux/Mac:**
```bash
cd src/release
LD_LIBRARY_PATH=. ./cuda_ed25519_vanity
```

**Windows:**
```cmd
cd src\release
cuda_ed25519_vanity.exe
```

**Important for Linux/Mac**: The `LD_LIBRARY_PATH=.` tells the system to look for `libcuda-crypt.so` in the current directory. Without this, you'll get a "shared library not found" error.

Make sure `vanity-config.json` is in the same directory as the executable, or it will use defaults.

## Configuration

Edit `vanity-config.json` before running to customize patterns:

```json
{
  "patterns": {
    "prefixes": ["sol", "moon"],
    "suffixes": ["pump", "rich"]
  }
}
```

See [VANITY_USAGE.md](VANITY_USAGE.md) for detailed configuration options.

## Troubleshooting

### "nvcc: command not found"
- CUDA toolkit is not installed or not in PATH
- **Fix**: Install CUDA toolkit and add it to your system PATH

### "No CUDA-capable device detected"
- No NVIDIA GPU found or drivers not installed
- **Fix**: Install latest NVIDIA drivers for your GPU

### "Compute capability not supported"
- Your GPU is too old for the configured compute capability
- **Fix**: Edit `src/gpu-common.mk` and adjust `GPU_ARCHS` for your GPU

### Build fails with linker errors
- Missing CUDA libraries
- **Fix**: Ensure CUDA_PATH environment variable is set correctly

### Executable not found after build
- Build may have failed silently
- **Fix**: Check `src/release/` directory, look for error messages in build output

### "error while loading shared libraries: libcuda-crypt.so" (Linux/Mac)
- The executable can't find the shared library
- **Fix**: Use the run script (`./run-vanity.sh`) which sets `LD_LIBRARY_PATH` automatically
- **Manual fix**: Run with `LD_LIBRARY_PATH=. ./cuda_ed25519_vanity` from the `src/release` directory

## Performance Tips

1. **Use release builds**: Much faster than debug builds
2. **Monitor GPU temperature**: Use `nvidia-smi` to check GPU stats
3. **Adjust patterns**: Shorter patterns = faster finding
4. **Use wildcards**: `?` wildcards increase match rate

## Getting Help

- For configuration help: See [VANITY_USAGE.md](VANITY_USAGE.md)
- For issues: Check GitHub issues or create a new one
- For CUDA help: https://docs.nvidia.com/cuda/

## Build Output Location

After building, you'll find:

```
src/
├── release/
│   ├── cuda_ed25519_vanity      # Main executable
│   ├── libcuda-crypt.so          # Shared library
│   └── *.o                       # Object files
└── debug/
    └── (debug builds go here)
```

## Clean Build

To remove all build artifacts:

**Windows:**
```cmd
cd src
make clean
```

**Linux/Mac:**
```bash
cd src
make clean
```

This removes the entire `release/` and `debug/` directories.
