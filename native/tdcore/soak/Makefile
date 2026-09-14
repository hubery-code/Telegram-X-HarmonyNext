# SPIKE-002: Makefile for native_soak harness
# Supports both host (macOS/Linux) and OpenHarmony arm64-v8a cross-compilation

CXX ?= clang++
CXXFLAGS ?= -O3 -std=c++17 -Wall -Wextra -pthread

NDK ?= /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
OHOS_CLANG ?= $(NDK)/llvm/bin/clang++
OHOS_SYSROOT ?= $(NDK)/sysroot
OHOS_TARGET ?= aarch64-linux-ohos

all: native_soak

native_soak: native_soak.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

ohos: native_soak.cpp
	$(OHOS_CLANG) --target=$(OHOS_TARGET) --sysroot=$(OHOS_SYSROOT) \
		-O3 -std=c++17 -Wall -Wextra -pthread \
		$< -o native_soak_arm64

clean:
	rm -f native_soak native_soak_arm64

.PHONY: all ohos clean
