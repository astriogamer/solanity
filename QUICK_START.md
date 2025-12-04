# Quick Start Guide

## For the Impatient

### Windows
```cmd
build.bat
run-vanity.bat
```

### Linux/Mac
```bash
chmod +x build.sh run-vanity.sh
./build.sh
./run-vanity.sh
```

## That's it!

The generator will:
1. Load patterns from `vanity-config.json` (prefixes: "abc", suffixes: "ab")
2. Ask if you want to modify patterns
3. Start searching for matching addresses
4. Print matches in Solana keyfile format

## Want Different Patterns?

Edit `vanity-config.json`:

```json
{
  "patterns": {
    "prefixes": ["your", "custom", "prefix"],
    "suffixes": ["suffix1", "suffix2"]
  }
}
```

**No rebuild needed!** Just edit and run again.

## Example Patterns

- `"sol"` - Find addresses starting with "sol"
- `"pump"` - Find addresses ending with "pump"
- `"m??n"` - Find "moon", "main", etc. (`?` is wildcard)
- `"????"` - Any 4 characters (easier to find)

## Output Example

When a match is found:
```
GPU 0 PREFIX MATCH [abc] -> abcXYZ123... - 1a2b3c4d...
[1,162,179,234,45,67,89,123,...]
```

The array `[...]` is a Solana keyfile - save it as `wallet.json` to use with Solana CLI.

## Need More Help?

- **Building issues**: See [BUILD_AND_RUN.md](BUILD_AND_RUN.md)
- **Configuration**: See [VANITY_USAGE.md](VANITY_USAGE.md)
- **Pattern examples**: See [VANITY_USAGE.md](VANITY_USAGE.md)

## Tips

1. Shorter patterns = faster (each character ≈ 58x harder)
2. Use `?` wildcards to increase match rate
3. Watch GPU temperature with `nvidia-smi`
4. Stop with `Ctrl+C`

Have fun generating vanity addresses! 🚀
