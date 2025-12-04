NVCC:=nvcc

# H200 has compute capability 9.0 → sm_90
GPU_PTX_ARCH:=compute_90
GPU_ARCHS?=sm_90

# Generate SASS for sm_90 and PTX for compute_90
GPU_CFLAGS:=--gpu-code=$(GPU_ARCHS),$(GPU_PTX_ARCH) --gpu-architecture=$(GPU_PTX_ARCH)

CFLAGS_release:=--ptxas-options=-v $(GPU_CFLAGS) -O3 -Xcompiler "-Wall -Werror -fPIC -Wno-strict-aliasing"
CFLAGS_debug:=$(CFLAGS_release) -g
CFLAGS:=$(CFLAGS_$V)