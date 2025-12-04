NVCC:=nvcc

# RTX 5070 Ti reports compute capability 12.0 → sm_120
GPU_PTX_ARCH:=compute_120
GPU_ARCHS?=sm_120

# Generate SASS for sm_120 and PTX for compute_120
GPU_CFLAGS:=--gpu-code=$(GPU_ARCHS),$(GPU_PTX_ARCH) --gpu-architecture=$(GPU_PTX_ARCH)

CFLAGS_release:=--ptxas-options=-v $(GPU_CFLAGS) -O3 -Xcompiler "-Wall -Werror -fPIC -Wno-strict-aliasing"
CFLAGS_debug:=$(CFLAGS_release) -g
CFLAGS:=$(CFLAGS_$V)