# HarmonyOS NEXT cross toolchain wrapper for TDLib native builds (TDN-001/002).
#
# Thin wrapper around the official NDK toolchain shipped with DevEco Studio
# (native/build/cmake/ohos.toolchain.cmake), locking the choices made in
# ADR-001 / tools/toolchain-versions.json:
#   - ABI:      arm64-v8a only (Phone first)
#   - STL:      c++_static (libc++ statically linked into every artifact;
#               avoids shipping libc++_shared.so from the start)
#
# Configurable inputs (cache variables):
#   OHOS_NDK_PATH  - root of the HarmonyOS NDK "native" dir
#                    (default: DevEco path from tools/toolchain-versions.json,
#                     overridable via env TDX_OHOS_NDK)
#   TDX_DEPS_PREFIX - install prefix of cross-compiled dependencies
#                     (OpenSSL); appended to CMAKE_FIND_ROOT_PATH so
#                     find_package(OpenSSL) can see it under ONLY modes.

if(NOT DEFINED OHOS_NDK_PATH)
  if(DEFINED ENV{TDX_OHOS_NDK})
    set(OHOS_NDK_PATH "$ENV{TDX_OHOS_NDK}")
  else()
    set(OHOS_NDK_PATH "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native")
  endif()
endif()

if(NOT EXISTS "${OHOS_NDK_PATH}/build/cmake/ohos.toolchain.cmake")
  message(FATAL_ERROR "OHOS NDK toolchain not found at ${OHOS_NDK_PATH}; set OHOS_NDK_PATH or TDX_OHOS_NDK")
endif()

# ADR-001 的默认目标是 arm64-v8a（真机），但**不强制** —— 模拟器镜像只有 x86_64，
# 要能在模拟器上验证 native 链路就必须允许覆盖。原先这里是 `FORCE`，于是
# `-DOHOS_ARCH=x86_64` 被静默覆盖成 arm64，编译出 aarch64 目标、链接 x86_64 的
# OpenSSL，报 `incompatible with aarch64linux` —— 报错指向库，指向不了这个 FORCE。
if(NOT DEFINED OHOS_ARCH)
  set(OHOS_ARCH arm64-v8a CACHE STRING "Target ABI (ADR-001: arm64-v8a first; x86_64 for emulator)" FORCE)
endif()
set(OHOS_STL c++_static CACHE STRING "Static libc++" FORCE)

include("${OHOS_NDK_PATH}/build/cmake/ohos.toolchain.cmake")

# The NDK toolchain restricts find_* to CMAKE_FIND_ROOT_PATH (ONLY modes) but
# only lists the NDK root itself, so sysroot headers/libs (zlib.h, libz.so)
# are invisible to find_package(ZLIB). Re-add the sysroot and our deps prefix.
list(APPEND CMAKE_FIND_ROOT_PATH "${OHOS_SDK_NATIVE}/sysroot")
if(DEFINED TDX_DEPS_PREFIX)
  list(APPEND CMAKE_FIND_ROOT_PATH "${TDX_DEPS_PREFIX}")
endif()
