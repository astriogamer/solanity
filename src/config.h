#ifndef VANITY_CONFIG
#define VANITY_CONFIG

// Default configuration values (used if vanity-config.json is not found)
static int const MAX_ITERATIONS = 100000;
static int const STOP_AFTER_KEYS_FOUND = 100;

// how many times a gpu thread generates a public key in one go
// Optimized for ~30 second iterations
static int const ATTEMPTS_PER_EXECUTION = 10000;

// Note: To customize patterns without rebuilding:
// 1. Create vanity-config.json in the project root
// 2. Or use interactive input when prompted at runtime
//
// If no JSON file exists, the default prefix "meteor" will be used

#endif
