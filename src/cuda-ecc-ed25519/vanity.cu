#include <vector>
#include <random>
#include <chrono>

#include <iostream>
#include <fstream>
#include <sstream>
#include <ctime>
#include <string>
#include <cstring>

#include <assert.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>

#include "curand_kernel.h"
#include "ed25519.h"
#include "fixedint.h"
#include "gpu_common.h"
#include "gpu_ctx.h"

#include "keypair.cu"
#include "sc.cu"
#include "fe.cu"
#include "ge.cu"
#include "sha512.cu"
#include "../config.h"

/* -- Types ----------------------------------------------------------------- */

typedef struct {
	// CUDA Random States.
	curandState*    states[8];
} config;

typedef struct {
	std::string prefix;
	std::string suffix;
} combined_pattern;

typedef struct {
	std::vector<std::string> prefixes;
	std::vector<std::string> suffixes;
	std::vector<combined_pattern> combined;
	int max_iterations;
	int stop_after_keys_found;
	int attempts_per_execution;
} pattern_config;

/* -- Prototypes, Because C++ ----------------------------------------------- */

pattern_config  load_pattern_config();
void            interactive_pattern_input(pattern_config& pconfig);
void            vanity_setup(config& vanity);
void            vanity_run(config& vanity, pattern_config& pconfig);
void __global__ vanity_init(unsigned long long int* seed, curandState* state);
void __global__ vanity_scan(curandState* state, int* keys_found, int* gpu, int* execution_count,
                           char** prefixes, int* prefix_lengths, int prefix_count,
                           char** suffixes, int* suffix_lengths, int suffix_count,
                           char** combined_prefixes, int* combined_prefix_lengths,
                           char** combined_suffixes, int* combined_suffix_lengths,
                           int combined_count, int attempts_per_exec);
bool __device__ b58enc(char* b58, size_t* b58sz, uint8_t* data, size_t binsz);

/* -- Entry Point ----------------------------------------------------------- */

int main(int argc, char const* argv[]) {
	ed25519_set_verbose(true);

	// Load pattern configuration
	pattern_config pconfig = load_pattern_config();

	// Allow interactive override if requested
	std::cout << "\nCurrent configuration:\n";
	std::cout << "  Max iterations: " << pconfig.max_iterations << "\n";
	std::cout << "  Stop after keys found: " << pconfig.stop_after_keys_found << "\n";
	std::cout << "  Attempts per execution: " << pconfig.attempts_per_execution << "\n";
	std::cout << "  Prefixes: ";
	for (const auto& p : pconfig.prefixes) std::cout << p << " ";
	std::cout << "\n  Suffixes: ";
	for (const auto& s : pconfig.suffixes) std::cout << s << " ";
	std::cout << "\n  Combined (prefix+suffix): ";
	for (const auto& c : pconfig.combined) std::cout << "[" << c.prefix << "..." << c.suffix << "] ";
	std::cout << "\n\nModify patterns? (y/n): ";

	char response;
	std::cin >> response;
	if (response == 'y' || response == 'Y') {
		interactive_pattern_input(pconfig);
	}

	config vanity;
	vanity_setup(vanity);
	vanity_run(vanity, pconfig);
}

// SMITH
std::string getTimeStr(){
    std::time_t now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::string s(30, '\0');
    std::strftime(&s[0], s.size(), "%Y-%m-%d %H:%M:%S", std::localtime(&now));
    return s;
}

// SMITH - safe? who knows
unsigned long long int makeSeed() {
    unsigned long long int seed = 0;
    char *pseed = (char *)&seed;

    std::random_device rd;

    for(unsigned int b=0; b<sizeof(seed); b++) {
      auto r = rd();
      char *entropy = (char *)&r;
      pseed[b] = entropy[0];
    }

    return seed;
}

// Simple JSON parser for pattern config
pattern_config load_pattern_config() {
	pattern_config pconfig;

	// Default values from config.h
	pconfig.max_iterations = MAX_ITERATIONS;
	pconfig.stop_after_keys_found = STOP_AFTER_KEYS_FOUND;
	pconfig.attempts_per_execution = ATTEMPTS_PER_EXECUTION;

	// Try to load from JSON file
	std::ifstream config_file("vanity-config.json");
	if (!config_file.is_open()) {
		std::cout << "No vanity-config.json found, using built-in defaults\n";
		// Use built-in default instead of config.h to avoid linking issues
		pconfig.prefixes.push_back("meteor");
		std::cout << "Default prefix: meteor\n";
		std::cout << "To customize: create vanity-config.json or use interactive input\n";
		return pconfig;
	}

	std::cout << "Loading configuration from vanity-config.json\n";
	std::stringstream buffer;
	buffer << config_file.rdbuf();
	std::string content = buffer.str();

	// Simple JSON parsing (basic implementation)
	size_t pos = 0;

	// Parse max_iterations
	pos = content.find("\"max_iterations\"");
	if (pos != std::string::npos) {
		pos = content.find(":", pos);
		if (pos != std::string::npos) {
			pconfig.max_iterations = std::stoi(content.substr(pos + 1));
		}
	}

	// Parse stop_after_keys_found
	pos = content.find("\"stop_after_keys_found\"");
	if (pos != std::string::npos) {
		pos = content.find(":", pos);
		if (pos != std::string::npos) {
			pconfig.stop_after_keys_found = std::stoi(content.substr(pos + 1));
		}
	}

	// Parse attempts_per_execution
	pos = content.find("\"attempts_per_execution\"");
	if (pos != std::string::npos) {
		pos = content.find(":", pos);
		if (pos != std::string::npos) {
			pconfig.attempts_per_execution = std::stoi(content.substr(pos + 1));
		}
	}

	// Parse prefixes array
	pos = content.find("\"prefixes\"");
	if (pos != std::string::npos) {
		size_t bracket_start = content.find("[", pos);
		size_t bracket_end = content.find("]", bracket_start);
		if (bracket_start != std::string::npos && bracket_end != std::string::npos) {
			std::string array_content = content.substr(bracket_start + 1, bracket_end - bracket_start - 1);
			size_t quote_pos = 0;
			while ((quote_pos = array_content.find("\"", quote_pos)) != std::string::npos) {
				size_t end_quote = array_content.find("\"", quote_pos + 1);
				if (end_quote != std::string::npos) {
					std::string pattern = array_content.substr(quote_pos + 1, end_quote - quote_pos - 1);
					if (!pattern.empty()) {
						pconfig.prefixes.push_back(pattern);
					}
					quote_pos = end_quote + 1;
				} else {
					break;
				}
			}
		}
	}

	// Parse suffixes array
	pos = content.find("\"suffixes\"");
	if (pos != std::string::npos) {
		size_t bracket_start = content.find("[", pos);
		size_t bracket_end = content.find("]", bracket_start);
		if (bracket_start != std::string::npos && bracket_end != std::string::npos) {
			std::string array_content = content.substr(bracket_start + 1, bracket_end - bracket_start - 1);
			size_t quote_pos = 0;
			while ((quote_pos = array_content.find("\"", quote_pos)) != std::string::npos) {
				size_t end_quote = array_content.find("\"", quote_pos + 1);
				if (end_quote != std::string::npos) {
					std::string pattern = array_content.substr(quote_pos + 1, end_quote - quote_pos - 1);
					if (!pattern.empty()) {
						pconfig.suffixes.push_back(pattern);
					}
					quote_pos = end_quote + 1;
				} else {
					break;
				}
			}
		}
	}

	// Parse combined array
	pos = content.find("\"combined\"");
	if (pos != std::string::npos) {
		size_t bracket_start = content.find("[", pos);
		size_t bracket_end = content.find("]", bracket_start);
		if (bracket_start != std::string::npos && bracket_end != std::string::npos) {
			std::string array_content = content.substr(bracket_start + 1, bracket_end - bracket_start - 1);
			size_t obj_pos = 0;
			while ((obj_pos = array_content.find("{", obj_pos)) != std::string::npos) {
				size_t obj_end = array_content.find("}", obj_pos);
				if (obj_end != std::string::npos) {
					std::string obj_content = array_content.substr(obj_pos + 1, obj_end - obj_pos - 1);

					// Extract prefix
					size_t prefix_pos = obj_content.find("\"prefix\"");
					std::string prefix_str;
					if (prefix_pos != std::string::npos) {
						size_t quote1 = obj_content.find("\"", prefix_pos + 8);
						size_t quote2 = obj_content.find("\"", quote1 + 1);
						if (quote1 != std::string::npos && quote2 != std::string::npos) {
							prefix_str = obj_content.substr(quote1 + 1, quote2 - quote1 - 1);
						}
					}

					// Extract suffix
					size_t suffix_pos = obj_content.find("\"suffix\"");
					std::string suffix_str;
					if (suffix_pos != std::string::npos) {
						size_t quote1 = obj_content.find("\"", suffix_pos + 8);
						size_t quote2 = obj_content.find("\"", quote1 + 1);
						if (quote1 != std::string::npos && quote2 != std::string::npos) {
							suffix_str = obj_content.substr(quote1 + 1, quote2 - quote1 - 1);
						}
					}

					if (!prefix_str.empty() && !suffix_str.empty()) {
						combined_pattern cp;
						cp.prefix = prefix_str;
						cp.suffix = suffix_str;
						pconfig.combined.push_back(cp);
					}

					obj_pos = obj_end + 1;
				} else {
					break;
				}
			}
		}
	}

	return pconfig;
}

void interactive_pattern_input(pattern_config& pconfig) {
	std::string input;
	std::cin.ignore(); // Clear newline from previous input

	std::cout << "\nEnter prefixes (comma-separated, or empty to skip): ";
	std::getline(std::cin, input);
	if (!input.empty()) {
		pconfig.prefixes.clear();
		std::stringstream ss(input);
		std::string pattern;
		while (std::getline(ss, pattern, ',')) {
			// Trim whitespace
			size_t start = pattern.find_first_not_of(" \t");
			size_t end = pattern.find_last_not_of(" \t");
			if (start != std::string::npos && end != std::string::npos) {
				pattern = pattern.substr(start, end - start + 1);
				if (!pattern.empty()) {
					pconfig.prefixes.push_back(pattern);
				}
			}
		}
	}

	std::cout << "Enter suffixes (comma-separated, or empty to skip): ";
	std::getline(std::cin, input);
	if (!input.empty()) {
		pconfig.suffixes.clear();
		std::stringstream ss(input);
		std::string pattern;
		while (std::getline(ss, pattern, ',')) {
			// Trim whitespace
			size_t start = pattern.find_first_not_of(" \t");
			size_t end = pattern.find_last_not_of(" \t");
			if (start != std::string::npos && end != std::string::npos) {
				pattern = pattern.substr(start, end - start + 1);
				if (!pattern.empty()) {
					pconfig.suffixes.push_back(pattern);
				}
			}
		}
	}

	std::cout << "\nUpdated configuration:\n";
	std::cout << "  Prefixes: ";
	for (const auto& p : pconfig.prefixes) std::cout << p << " ";
	std::cout << "\n  Suffixes: ";
	for (const auto& s : pconfig.suffixes) std::cout << s << " ";
	std::cout << "\n";
}

/* -- Vanity Step Functions ------------------------------------------------- */

void vanity_setup(config &vanity) {
	printf("GPU: Initializing Memory\n");
	int gpuCount = 0;
	cudaGetDeviceCount(&gpuCount);

	// Create random states so kernels have access to random generators
	// while running in the GPU.
	for (int i = 0; i < gpuCount; ++i) {
		cudaSetDevice(i);

		// Fetch Device Properties
		cudaDeviceProp device;
		cudaGetDeviceProperties(&device, i);

		// Calculate Occupancy
		int blockSize       = 0,
		    minGridSize     = 0,
		    maxActiveBlocks = 0;
		cudaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, vanity_scan, 0, 0);
		cudaOccupancyMaxActiveBlocksPerMultiprocessor(&maxActiveBlocks, vanity_scan, blockSize, 0);

		// PERFORMANCE FIX: Force higher occupancy for newer GPUs
		// The automatic occupancy calculation can be too conservative
		if (blockSize < 256) {
			printf("WARNING: Auto blockSize=%d too small, forcing 256\n", blockSize);
			blockSize = 256;
		}
		// For H100/H200 with sm_90, increase occupancy but not too aggressively
		// The kernel is register-heavy, so we can't push too many blocks per SM
		int blocksPerSM = (device.major == 9 && device.minor == 0) ? 2 : 8;
		int minBlocksNeeded = device.multiProcessorCount * blocksPerSM;
		if (minGridSize < minBlocksNeeded) {
			printf("WARNING: Auto minGridSize=%d too small, forcing %d\n", minGridSize, minBlocksNeeded);
			minGridSize = minBlocksNeeded;
		}

		// Output Device Details
		// 
		// Our kernels currently don't take advantage of data locality
		// or how warp execution works, so each thread can be thought
		// of as a totally independent thread of execution (bad). On
		// the bright side, this means we can really easily calculate
		// maximum occupancy for a GPU because we don't have to care
		// about building blocks well. Essentially we're trading away
		// GPU SIMD ability for standard parallelism, which CPUs are
		// better at and GPUs suck at.
		//
		// Next Weekend Project: ^ Fix this.
		printf("GPU: %d (%s <%d, %d, %d>) -- W: %d, P: %d, TPB: %d, MTD: (%dx, %dy, %dz), MGS: (%dx, %dy, %dz)\n",
			i,
			device.name,
			blockSize,
			minGridSize,
			maxActiveBlocks,
			device.warpSize,
			device.multiProcessorCount,
		       	device.maxThreadsPerBlock,
			device.maxThreadsDim[0],
			device.maxThreadsDim[1],
			device.maxThreadsDim[2],
			device.maxGridSize[0],
			device.maxGridSize[1],
			device.maxGridSize[2]
		);

                // the random number seed is uniquely generated each time the program 
                // is run, from the operating system entropy

		unsigned long long int rseed = makeSeed();
		printf("Initialising from entropy: %llu\n",rseed);

		unsigned long long int* dev_rseed;
	        cudaMalloc((void**)&dev_rseed, sizeof(unsigned long long int));		
                cudaMemcpy( dev_rseed, &rseed, sizeof(unsigned long long int), cudaMemcpyHostToDevice ); 

		cudaMalloc((void **)&(vanity.states[i]), minGridSize * blockSize * sizeof(curandState));
		vanity_init<<<minGridSize, blockSize>>>(dev_rseed, vanity.states[i]);

		printf("GPU %d: Launching with %d blocks x %d threads = %d total threads\n",
		       i, minGridSize, blockSize, minGridSize * blockSize);
	}

	printf("END: Initializing Memory\n");
}

void vanity_run(config &vanity, pattern_config& pconfig) {
	int gpuCount = 0;
	cudaGetDeviceCount(&gpuCount);

	// Prepare patterns for GPU
	char** dev_prefixes[100];
	int* dev_prefix_lengths[100];
	char** dev_suffixes[100];
	int* dev_suffix_lengths[100];
	char** dev_combined_prefixes[100];
	int* dev_combined_prefix_lengths[100];
	char** dev_combined_suffixes[100];
	int* dev_combined_suffix_lengths[100];

	std::vector<int> prefix_lengths;
	std::vector<int> suffix_lengths;
	std::vector<int> combined_prefix_lengths;
	std::vector<int> combined_suffix_lengths;

	for (const auto& p : pconfig.prefixes) prefix_lengths.push_back(p.length());
	for (const auto& s : pconfig.suffixes) suffix_lengths.push_back(s.length());
	for (const auto& c : pconfig.combined) {
		combined_prefix_lengths.push_back(c.prefix.length());
		combined_suffix_lengths.push_back(c.suffix.length());
	}

	// Copy patterns to device for each GPU
	for (int g = 0; g < gpuCount; ++g) {
		cudaSetDevice(g);

		// Allocate prefix arrays
		if (!pconfig.prefixes.empty()) {
			char** h_prefixes = new char*[pconfig.prefixes.size()];
			for (size_t i = 0; i < pconfig.prefixes.size(); ++i) {
				cudaMalloc(&h_prefixes[i], pconfig.prefixes[i].length() + 1);
				cudaMemcpy(h_prefixes[i], pconfig.prefixes[i].c_str(),
				          pconfig.prefixes[i].length() + 1, cudaMemcpyHostToDevice);
			}
			cudaMalloc(&dev_prefixes[g], pconfig.prefixes.size() * sizeof(char*));
			cudaMemcpy(dev_prefixes[g], h_prefixes,
			          pconfig.prefixes.size() * sizeof(char*), cudaMemcpyHostToDevice);
			delete[] h_prefixes;

			cudaMalloc(&dev_prefix_lengths[g], prefix_lengths.size() * sizeof(int));
			cudaMemcpy(dev_prefix_lengths[g], prefix_lengths.data(),
			          prefix_lengths.size() * sizeof(int), cudaMemcpyHostToDevice);
		}

		// Allocate suffix arrays
		if (!pconfig.suffixes.empty()) {
			char** h_suffixes = new char*[pconfig.suffixes.size()];
			for (size_t i = 0; i < pconfig.suffixes.size(); ++i) {
				cudaMalloc(&h_suffixes[i], pconfig.suffixes[i].length() + 1);
				cudaMemcpy(h_suffixes[i], pconfig.suffixes[i].c_str(),
				          pconfig.suffixes[i].length() + 1, cudaMemcpyHostToDevice);
			}
			cudaMalloc(&dev_suffixes[g], pconfig.suffixes.size() * sizeof(char*));
			cudaMemcpy(dev_suffixes[g], h_suffixes,
			          pconfig.suffixes.size() * sizeof(char*), cudaMemcpyHostToDevice);
			delete[] h_suffixes;

			cudaMalloc(&dev_suffix_lengths[g], suffix_lengths.size() * sizeof(int));
			cudaMemcpy(dev_suffix_lengths[g], suffix_lengths.data(),
			          suffix_lengths.size() * sizeof(int), cudaMemcpyHostToDevice);
		}

		// Allocate combined pattern arrays
		if (!pconfig.combined.empty()) {
			char** h_combined_prefixes = new char*[pconfig.combined.size()];
			char** h_combined_suffixes = new char*[pconfig.combined.size()];
			for (size_t i = 0; i < pconfig.combined.size(); ++i) {
				cudaMalloc(&h_combined_prefixes[i], pconfig.combined[i].prefix.length() + 1);
				cudaMemcpy(h_combined_prefixes[i], pconfig.combined[i].prefix.c_str(),
				          pconfig.combined[i].prefix.length() + 1, cudaMemcpyHostToDevice);

				cudaMalloc(&h_combined_suffixes[i], pconfig.combined[i].suffix.length() + 1);
				cudaMemcpy(h_combined_suffixes[i], pconfig.combined[i].suffix.c_str(),
				          pconfig.combined[i].suffix.length() + 1, cudaMemcpyHostToDevice);
			}

			cudaMalloc(&dev_combined_prefixes[g], pconfig.combined.size() * sizeof(char*));
			cudaMemcpy(dev_combined_prefixes[g], h_combined_prefixes,
			          pconfig.combined.size() * sizeof(char*), cudaMemcpyHostToDevice);

			cudaMalloc(&dev_combined_suffixes[g], pconfig.combined.size() * sizeof(char*));
			cudaMemcpy(dev_combined_suffixes[g], h_combined_suffixes,
			          pconfig.combined.size() * sizeof(char*), cudaMemcpyHostToDevice);

			delete[] h_combined_prefixes;
			delete[] h_combined_suffixes;

			cudaMalloc(&dev_combined_prefix_lengths[g], combined_prefix_lengths.size() * sizeof(int));
			cudaMemcpy(dev_combined_prefix_lengths[g], combined_prefix_lengths.data(),
			          combined_prefix_lengths.size() * sizeof(int), cudaMemcpyHostToDevice);

			cudaMalloc(&dev_combined_suffix_lengths[g], combined_suffix_lengths.size() * sizeof(int));
			cudaMemcpy(dev_combined_suffix_lengths[g], combined_suffix_lengths.data(),
			          combined_suffix_lengths.size() * sizeof(int), cudaMemcpyHostToDevice);
		}
	}

	unsigned long long int  executions_total = 0;
	unsigned long long int  executions_this_iteration;
	int  executions_this_gpu;
        int* dev_executions_this_gpu[100];

        int  keys_found_total = 0;
        int  keys_found_this_iteration;
        int* dev_keys_found[100]; // not more than 100 GPUs ok!

	printf("Starting iteration loop with %zu prefixes, %zu suffixes, and %zu combined patterns...\n",
	       pconfig.prefixes.size(), pconfig.suffixes.size(), pconfig.combined.size());
	for (int i = 0; i < pconfig.max_iterations; ++i) {
		printf("Iteration %d starting...\n", i+1);
		auto start  = std::chrono::high_resolution_clock::now();

                executions_this_iteration=0;

		// Run on all GPUs
		for (int g = 0; g < gpuCount; ++g) {
			cudaSetDevice(g);

			// Fetch Device Properties
			cudaDeviceProp device;
			cudaGetDeviceProperties(&device, g);

			// Calculate Occupancy
			int blockSize       = 0,
			    minGridSize     = 0,
			    maxActiveBlocks = 0;
			cudaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, vanity_scan, 0, 0);
			cudaOccupancyMaxActiveBlocksPerMultiprocessor(&maxActiveBlocks, vanity_scan, blockSize, 0);

			// PERFORMANCE FIX: Force higher occupancy
			if (blockSize < 256) {
				blockSize = 256;
			}
			// For H100/H200 with sm_90, increase occupancy but not too aggressively
			// The kernel is register-heavy, so we can't push too many blocks per SM
			int blocksPerSM = (device.major == 9 && device.minor == 0) ? 2 : 8;
			int minBlocksNeeded = device.multiProcessorCount * blocksPerSM;
			if (minGridSize < minBlocksNeeded) {
				minGridSize = minBlocksNeeded;
			}

			int* dev_g;
	                cudaMalloc((void**)&dev_g, sizeof(int));
                	cudaMemcpy( dev_g, &g, sizeof(int), cudaMemcpyHostToDevice );

	                cudaMalloc((void**)&dev_keys_found[g], sizeof(int));
	                cudaMalloc((void**)&dev_executions_this_gpu[g], sizeof(int));

			vanity_scan<<<minGridSize, blockSize>>>(
				vanity.states[g],
				dev_keys_found[g],
				dev_g,
				dev_executions_this_gpu[g],
				pconfig.prefixes.empty() ? nullptr : dev_prefixes[g],
				pconfig.prefixes.empty() ? nullptr : dev_prefix_lengths[g],
				pconfig.prefixes.size(),
				pconfig.suffixes.empty() ? nullptr : dev_suffixes[g],
				pconfig.suffixes.empty() ? nullptr : dev_suffix_lengths[g],
				pconfig.suffixes.size(),
				pconfig.combined.empty() ? nullptr : dev_combined_prefixes[g],
				pconfig.combined.empty() ? nullptr : dev_combined_prefix_lengths[g],
				pconfig.combined.empty() ? nullptr : dev_combined_suffixes[g],
				pconfig.combined.empty() ? nullptr : dev_combined_suffix_lengths[g],
				pconfig.combined.size(),
				pconfig.attempts_per_execution
			);
			printf("Kernel launched for GPU %d, now waiting for sync...\n", g);

		}
		printf("All kernels launched, synchronizing...\n");

		// Synchronize while we wait for kernels to complete. I do not
		// actually know if this will sync against all GPUs, it might
		// just sync with the last `i`, but they should all complete
		// roughly at the same time and worst case it will just stack
		// up kernels in the queue to run.
		cudaDeviceSynchronize();
		printf("Sync complete!\n");
		auto finish = std::chrono::high_resolution_clock::now();

		for (int g = 0; g < gpuCount; ++g) {
                	cudaMemcpy( &keys_found_this_iteration, dev_keys_found[g], sizeof(int), cudaMemcpyDeviceToHost ); 
                	keys_found_total += keys_found_this_iteration; 
			//printf("GPU %d found %d keys\n",g,keys_found_this_iteration);

                	cudaMemcpy( &executions_this_gpu, dev_executions_this_gpu[g], sizeof(int), cudaMemcpyDeviceToHost );
                	executions_this_iteration += executions_this_gpu * pconfig.attempts_per_execution;
                	executions_total += executions_this_gpu * pconfig.attempts_per_execution; 
                        //printf("GPU %d executions: %d\n",g,executions_this_gpu);
		}

		// Print out performance Summary
		std::chrono::duration<double> elapsed = finish - start;
		double cps = executions_this_iteration / elapsed.count();
		double cps_millions = cps / 1000000.0;

		printf("%s Iteration %d | CPS: %.2fM (%.0f) | Attempts: %llu in %.3fs | Total: %llu | Keys: %d\n",
			getTimeStr().c_str(),
			i+1,
			cps_millions,
			cps,
			executions_this_iteration,
			elapsed.count(),
			executions_total,
			keys_found_total
		);

                if ( keys_found_total >= pconfig.stop_after_keys_found ) {
                	printf("Enough keys found, Done! \n");
		        exit(0);
		}
	}

	printf("Iterations complete, Done!\n");
}

/* -- CUDA Vanity Functions ------------------------------------------------- */

void __global__ vanity_init(unsigned long long int* rseed, curandState* state) {
	int id = threadIdx.x + (blockIdx.x * blockDim.x);  
	curand_init(*rseed + id, id, 0, &state[id]);
}

void __global__ vanity_scan(curandState* state, int* keys_found, int* gpu, int* exec_count,
                           char** prefixes, int* prefix_lengths, int prefix_count,
                           char** suffixes, int* suffix_lengths, int suffix_count,
                           char** combined_prefixes, int* combined_prefix_lengths,
                           char** combined_suffixes, int* combined_suffix_lengths,
                           int combined_count, int attempts_per_exec) {
	int id = threadIdx.x + (blockIdx.x * blockDim.x);

        atomicAdd(exec_count, attempts_per_exec);

	// Local Kernel State
	ge_p3 A;
	curandState localState     = state[id];
	unsigned char seed[32]     = {0};
	unsigned char publick[32]  = {0};
	unsigned char privatek[64] = {0};
	char key[256]              = {0};
	//char pkey[256]             = {0};

	// Start from an Initial Random Seed (Slow)
	// NOTE: Insecure random number generator, do not use keys generator by
	// this program in live.
	// SMITH: localState should be entropy random now
	for (int i = 0; i < 32; ++i) {
		float random    = curand_uniform(&localState);
		uint8_t keybyte = (uint8_t)(random * 255);
		seed[i]         = keybyte;
	}

	// Generate Random Key Data
	sha512_context md;

	// I've unrolled all the MD5 calls and special cased them to 32 byte
	// inputs, which eliminates a lot of branching. This is a pretty poor
	// way to optimize GPU code though.
	//
	// A better approach would be to split this application into two
	// different kernels, one that is warp-efficient for SHA512 generation,
	// and another that is warp efficient for bignum division to more
	// efficiently scan for prefixes. Right now bs58enc cuts performance
	// from 16M keys on my machine per second to 4M.
	for (int attempts = 0; attempts < attempts_per_exec; ++attempts) {
		// sha512_init Inlined
		md.curlen   = 0;
		md.length   = 0;
		md.state[0] = UINT64_C(0x6a09e667f3bcc908);
		md.state[1] = UINT64_C(0xbb67ae8584caa73b);
		md.state[2] = UINT64_C(0x3c6ef372fe94f82b);
		md.state[3] = UINT64_C(0xa54ff53a5f1d36f1);
		md.state[4] = UINT64_C(0x510e527fade682d1);
		md.state[5] = UINT64_C(0x9b05688c2b3e6c1f);
		md.state[6] = UINT64_C(0x1f83d9abfb41bd6b);
		md.state[7] = UINT64_C(0x5be0cd19137e2179);

		// sha512_update inlined
		// 
		// All `if` statements from this function are eliminated if we
		// will only ever hash a 32 byte seed input. So inlining this
		// has a drastic speed improvement on GPUs.
		//
		// This means:
		//   * Normally we iterate for each 128 bytes of input, but we are always < 128. So no iteration.
		//   * We can eliminate a MIN(inlen, (128 - md.curlen)) comparison, specialize to 32, branch prediction improvement.
		//   * We can eliminate the in/inlen tracking as we will never subtract while under 128
		//   * As a result, the only thing update does is copy the bytes into the buffer.
		const unsigned char *in = seed;
		for (size_t i = 0; i < 32; i++) {
			md.buf[i + md.curlen] = in[i];
		}
		md.curlen += 32;


		// sha512_final inlined
		// 
		// As update was effectively elimiated, the only time we do
		// sha512_compress now is in the finalize function. We can also
		// optimize this:
		//
		// This means:
		//   * We don't need to care about the curlen > 112 check. Eliminating a branch.
		//   * We only need to run one round of sha512_compress, so we can inline it entirely as we don't need to unroll.
		md.length += md.curlen * UINT64_C(8);
		md.buf[md.curlen++] = (unsigned char)0x80;

		while (md.curlen < 120) {
			md.buf[md.curlen++] = (unsigned char)0;
		}

		STORE64H(md.length, md.buf+120);

		// Inline sha512_compress
		uint64_t S[8], W[80], t0, t1;
		int i;

		/* Copy state into S */
		for (i = 0; i < 8; i++) {
			S[i] = md.state[i];
		}

		/* Copy the state into 1024-bits into W[0..15] */
		for (i = 0; i < 16; i++) {
			LOAD64H(W[i], md.buf + (8*i));
		}

		/* Fill W[16..79] */
		for (i = 16; i < 80; i++) {
			W[i] = Gamma1(W[i - 2]) + W[i - 7] + Gamma0(W[i - 15]) + W[i - 16];
		}

		/* Compress */
		#define RND(a,b,c,d,e,f,g,h,i) \
		t0 = h + Sigma1(e) + Ch(e, f, g) + K[i] + W[i]; \
		t1 = Sigma0(a) + Maj(a, b, c);\
		d += t0; \
		h  = t0 + t1;

		for (i = 0; i < 80; i += 8) {
			RND(S[0],S[1],S[2],S[3],S[4],S[5],S[6],S[7],i+0);
			RND(S[7],S[0],S[1],S[2],S[3],S[4],S[5],S[6],i+1);
			RND(S[6],S[7],S[0],S[1],S[2],S[3],S[4],S[5],i+2);
			RND(S[5],S[6],S[7],S[0],S[1],S[2],S[3],S[4],i+3);
			RND(S[4],S[5],S[6],S[7],S[0],S[1],S[2],S[3],i+4);
			RND(S[3],S[4],S[5],S[6],S[7],S[0],S[1],S[2],i+5);
			RND(S[2],S[3],S[4],S[5],S[6],S[7],S[0],S[1],i+6);
			RND(S[1],S[2],S[3],S[4],S[5],S[6],S[7],S[0],i+7);
		}

		#undef RND

		/* Feedback */
		for (i = 0; i < 8; i++) {
			md.state[i] = md.state[i] + S[i];
		}

		// We can now output our finalized bytes into the output buffer.
		for (i = 0; i < 8; i++) {
			STORE64H(md.state[i], privatek+(8*i));
		}

		// Code Until here runs at 87_000_000H/s.

		// ed25519 Hash Clamping
		privatek[0]  &= 248;
		privatek[31] &= 63;
		privatek[31] |= 64;

		// ed25519 curve multiplication to extract a public key.
		ge_scalarmult_base(&A, privatek);
		ge_p3_tobytes(publick, &A);

		// Code Until here runs at 87_000_000H/s still!

		size_t keysize = 256;
		b58enc(key, &keysize, publick, 32);

		// Code Until here runs at 22_000_000H/s. b58enc badly needs optimization.

		// Pattern matching - check both prefixes and suffixes
		bool match_found = false;
		char* matched_pattern = nullptr;
		const char* match_type = nullptr;

		// Get key length
		int key_len = 0;
		for (; key[key_len] != '\0' && key_len < 256; ++key_len);

		// Check prefixes
		for (int i = 0; i < prefix_count && !match_found; ++i) {
			bool prefix_matches = true;
			for (int j = 0; j < prefix_lengths[i]; ++j) {
				char pattern_char = prefixes[i][j];
				if (pattern_char != '?' && pattern_char != key[j]) {
					prefix_matches = false;
					break;
				}
			}
			if (prefix_matches) {
				match_found = true;
				matched_pattern = prefixes[i];
				match_type = "PREFIX";
			}
		}

		// Check suffixes
		for (int i = 0; i < suffix_count && !match_found; ++i) {
			bool suffix_matches = true;
			int suffix_start = key_len - suffix_lengths[i];
			if (suffix_start >= 0) {
				for (int j = 0; j < suffix_lengths[i]; ++j) {
					char pattern_char = suffixes[i][j];
					if (pattern_char != '?' && pattern_char != key[suffix_start + j]) {
						suffix_matches = false;
						break;
					}
				}
				if (suffix_matches) {
					match_found = true;
					matched_pattern = suffixes[i];
					match_type = "SUFFIX";
				}
			}
		}

		// Check combined patterns (prefix AND suffix must BOTH match)
		char combined_prefix_pattern[64] = {0};
		char combined_suffix_pattern[64] = {0};
		for (int i = 0; i < combined_count && !match_found; ++i) {
			bool prefix_matches = true;
			bool suffix_matches = true;

			// Check prefix part
			for (int j = 0; j < combined_prefix_lengths[i]; ++j) {
				char pattern_char = combined_prefixes[i][j];
				if (pattern_char != '?' && pattern_char != key[j]) {
					prefix_matches = false;
					break;
				}
			}

			// Check suffix part
			int suffix_start = key_len - combined_suffix_lengths[i];
			if (suffix_start >= 0) {
				for (int j = 0; j < combined_suffix_lengths[i]; ++j) {
					char pattern_char = combined_suffixes[i][j];
					if (pattern_char != '?' && pattern_char != key[suffix_start + j]) {
						suffix_matches = false;
						break;
					}
				}
			} else {
				suffix_matches = false;
			}

			// BOTH must match for combined pattern
			if (prefix_matches && suffix_matches) {
				match_found = true;
				match_type = "COMBINED";
				// Copy patterns for printing
				for (int j = 0; j < combined_prefix_lengths[i] && j < 63; ++j) {
					combined_prefix_pattern[j] = combined_prefixes[i][j];
				}
				for (int j = 0; j < combined_suffix_lengths[i] && j < 63; ++j) {
					combined_suffix_pattern[j] = combined_suffixes[i][j];
				}
			}
		}

		if (match_found) {
			atomicAdd(keys_found, 1);

			// Print match information
			if (match_type[0] == 'C') { // COMBINED
				printf("GPU %d %s MATCH [%s...%s] -> %s - ", *gpu, match_type,
				       combined_prefix_pattern, combined_suffix_pattern, key);
			} else {
				printf("GPU %d %s MATCH [%s] -> %s - ", *gpu, match_type, matched_pattern, key);
			}
			for(int n=0; n<sizeof(seed); n++) {
				printf("%02x",(unsigned char)seed[n]);
			}
			printf("\n");

			// Print as Solana keyfile format (seed + public key as decimal array)
			printf("[");
			for(int n=0; n<sizeof(seed); n++) {
				printf("%d,",(unsigned char)seed[n]);
			}
			for(int n=0; n<sizeof(publick); n++) {
				if ( n+1==sizeof(publick) ) {
					printf("%d",publick[n]);
				} else {
					printf("%d,",publick[n]);
				}
			}
			printf("]\n");
		}

		// Code Until here runs at 22_000_000H/s. So the above is fast enough.

		// Increment Seed.
		// NOTE: This is horrifically insecure. Please don't use these
		// keys on live. This increment is just so we don't have to
		// invoke the CUDA random number generator for each hash to
		// boost performance a little. Easy key generation, awful
		// security.
		for (int i = 0; i < 32; ++i) {
			if (seed[i] == 255) {
				seed[i]  = 0;
			} else {
				seed[i] += 1;
				break;
			}
		}
	}

	// Copy Random State so that future calls of this kernel/thread/block
	// don't repeat their sequences.
	state[id] = localState;
}

bool __device__ b58enc(
	char    *b58,
       	size_t  *b58sz,
       	uint8_t *data,
       	size_t  binsz
) {
	// Base58 Lookup Table
	const char b58digits_ordered[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

	const uint8_t *bin = data;
	int carry;
	size_t i, j, high, zcount = 0;
	size_t size;
	
	while (zcount < binsz && !bin[zcount])
		++zcount;
	
	size = (binsz - zcount) * 138 / 100 + 1;
	uint8_t buf[256];
	memset(buf, 0, size);
	
	for (i = zcount, high = size - 1; i < binsz; ++i, high = j)
	{
		for (carry = bin[i], j = size - 1; (j > high) || carry; --j)
		{
			carry += 256 * buf[j];
			buf[j] = carry % 58;
			carry /= 58;
			if (!j) {
				// Otherwise j wraps to maxint which is > high
				break;
			}
		}
	}
	
	for (j = 0; j < size && !buf[j]; ++j);
	
	if (*b58sz <= zcount + size - j) {
		*b58sz = zcount + size - j + 1;
		return false;
	}
	
	if (zcount) memset(b58, '1', zcount);
	for (i = zcount; j < size; ++i, ++j) b58[i] = b58digits_ordered[buf[j]];

	b58[i] = '\0';
	*b58sz = i + 1;
	
	return true;
}
