# Solana Vanity Address Generator - Usage Guide

## Overview

This GPU-accelerated vanity address generator allows you to create Solana wallet addresses with custom prefixes and suffixes **without needing to rebuild** the project.

## Configuration Methods

### Method 1: JSON Configuration File (Recommended)

Create a `vanity-config.json` file in the project root:

```json
{
  "comment": "Vanity address pattern configuration - supports wildcards with ?",
  "max_iterations": 100000,
  "stop_after_keys_found": 100,
  "attempts_per_execution": 10000,
  "patterns": {
    "prefixes": [
      "meteor",
      "sol",
      "moon"
    ],
    "suffixes": [
      "pump",
      "rich"
    ],
    "combined": [
      {
        "prefix": "sol",
        "suffix": "pump"
      },
      {
        "prefix": "moon",
        "suffix": "rich"
      }
    ]
  }
}
```

**Advantages:**
- No rebuild required - just edit the JSON and run
- Easy to save and share different configurations
- Can specify both prefixes and suffixes

### Method 2: Interactive Input at Runtime

When you run the program, you'll be prompted:

```
Current configuration:
  Max iterations: 100000
  Stop after keys found: 100
  Attempts per execution: 10000
  Prefixes: meteor sol moon
  Suffixes: pump rich

Modify patterns? (y/n):
```

Type `y` to enter custom patterns:

```
Enter prefixes (comma-separated, or empty to skip): king, queen, ace
Enter suffixes (comma-separated, or empty to skip): win, gold
```

**Advantages:**
- Quick pattern changes without editing files
- Great for testing different patterns
- Can override JSON config on the fly

### Method 3: Default from config.h (Fallback)

If no `vanity-config.json` exists and you skip interactive input, the program uses defaults from `src/config.h`.

## Pattern Features

### Wildcard Support

Use `?` as a wildcard to match any character:

```json
{
  "patterns": {
    "prefixes": [
      "sol?",     // Matches: sol1, solA, solX, etc.
      "m??n",     // Matches: moon, main, m00n, etc.
      "???pump"   // First 3 chars can be anything, then "pump"
    ]
  }
}
```

### Prefix Matching

Matches patterns at the **start** of the address:
- `"meteor"` → Finds addresses like: `meteorABC123...`
- `"sol"` → Finds addresses like: `solXYZ789...`

### Suffix Matching

Matches patterns at the **end** of the address:
- `"pump"` → Finds addresses like: `...XYZpump`
- `"rich"` → Finds addresses like: `...ABCrich`

### Combined Matching (Prefix AND Suffix)

**NEW!** Match BOTH a prefix AND suffix on the same address:

```json
{
  "patterns": {
    "combined": [
      {
        "prefix": "sol",
        "suffix": "pump"
      }
    ]
  }
}
```

This finds addresses like: `solABC123...XYZpump` - starts with "sol" AND ends with "pump" on the **same address**.

**Important**: Combined patterns are MUCH harder to find than individual patterns because BOTH conditions must be met. For example:
- Finding "sol" prefix: ~200,000 attempts (easy)
- Finding "pump" suffix: ~11 million attempts (moderate)
- Finding "sol" prefix AND "pump" suffix together: ~2+ billion attempts (very hard!)

### Multiple Patterns

You can search for multiple patterns simultaneously:

```json
{
  "patterns": {
    "prefixes": ["sol", "moon", "star"],
    "suffixes": ["pump", "rich", "win"]
  }
}
```

The generator will find addresses matching **any** of these patterns.

## Performance Tuning

### attempts_per_execution

Controls how many keys each GPU thread generates per iteration:

```json
"attempts_per_execution": 10000
```

- **Higher values (20000+)**: Longer iterations, better GPU utilization
- **Lower values (5000-)**: Shorter iterations, more responsive
- **Recommended**: 10000 for ~30 second iterations

### max_iterations

Maximum number of search iterations:

```json
"max_iterations": 100000
```

### stop_after_keys_found

Stop after finding this many matching addresses:

```json
"stop_after_keys_found": 100
```

## Example Workflows

### Generate addresses ending in "pump"

Edit `vanity-config.json`:
```json
{
  "patterns": {
    "prefixes": [],
    "suffixes": ["pump"]
  }
}
```

Run: `./vanity` (or however you execute the program)

### Find multiple prefix variations quickly

Interactive mode:
1. Run the program
2. Type `y` when prompted
3. Enter: `king, queen, prince, duke`
4. Press Enter to skip suffixes
5. Generator starts immediately

### Generate addresses with both prefix AND suffix

For ultra-rare vanity addresses with BOTH requirements:
```json
{
  "max_iterations": 10000000,
  "stop_after_keys_found": 1,
  "attempts_per_execution": 20000,
  "patterns": {
    "combined": [
      {
        "prefix": "sol",
        "suffix": "win"
      }
    ]
  }
}
```
This will find addresses like `solABC123...win` (starts with "sol" AND ends with "win")

### Test pattern difficulty

For very difficult patterns, increase iterations:
```json
{
  "max_iterations": 1000000,
  "stop_after_keys_found": 1,
  "patterns": {
    "prefixes": ["verylongpattern"]
  }
}
```

## Output Format

When a match is found, you'll see:

**Prefix match:**
```
GPU 0 PREFIX MATCH [meteor] -> meteorABC123... - 1a2b3c4d...
[1,162,179,234,45,67,89,123,...]
```

**Suffix match:**
```
GPU 0 SUFFIX MATCH [pump] -> XYZ123...pump - 1a2b3c4d...
[1,162,179,234,45,67,89,123,...]
```

**Combined match (prefix AND suffix):**
```
GPU 0 COMBINED MATCH [sol...pump] -> solABC123...pump - 1a2b3c4d...
[1,162,179,234,45,67,89,123,...]
```

- **Match type**: PREFIX, SUFFIX, or COMBINED
- **Pattern matched**: The pattern(s) that were found
- **Address**: The full Solana address
- **Seed hex**: The seed in hexadecimal
- **Array format**: Solana keyfile format (seed + public key)

The array can be saved directly as a `.json` keyfile for Solana CLI.

## Tips

1. **Start with shorter patterns** (2-3 characters) to test your GPU performance
2. **Use wildcards strategically** - `?` can significantly increase match rate
3. **Monitor GPU temperature** during long runs
4. **Save good configs** - keep multiple JSON files for different pattern sets
5. **Difficulty increases exponentially** with pattern length (each char ≈ 58x harder)

## Pattern Difficulty Estimates

| Pattern Length | Approximate Attempts | Time on High-End GPU |
|----------------|---------------------|----------------------|
| 2 chars        | ~3,000              | < 1 second          |
| 3 chars        | ~200,000            | ~5 seconds          |
| 4 chars        | ~11 million         | ~5 minutes          |
| 5 chars        | ~650 million        | ~5 hours            |
| 6 chars        | ~38 billion         | ~12 days            |

*Times vary based on GPU, pattern characters, and whether prefix or suffix*

## Troubleshooting

### "No vanity-config.json found"
This is normal - the program will use defaults from config.h or prompt for input.

### No matches found
- Try shorter patterns or use wildcards
- Increase `max_iterations`
- Check your pattern uses valid base58 characters (no 0, O, I, l)

### GPU errors
- Reduce `attempts_per_execution` to lower memory usage
- Check CUDA drivers are up to date
- Monitor GPU temperature

## Security Warning

**IMPORTANT**: Keys generated by this tool should only be used for:
- Testing and development
- Non-production environments
- Learning purposes

For production use, always use official Solana key generation tools and proper entropy sources.
