#ifndef VANITY_CONFIG
#define VANITY_CONFIG

static int const MAX_ITERATIONS = 100000;
static int const STOP_AFTER_KEYS_FOUND = 100;

// how many times a gpu thread generates a public key in one go
// Optimized for ~30 second iterations
__device__ const int ATTEMPTS_PER_EXECUTION = 10000;

__device__ const int MAX_PATTERNS = 10;

// exact matches at the beginning of the address, letter ? is wildcard

__device__ static char const *prefixes[] = {
	"meteor",
};


#endif
