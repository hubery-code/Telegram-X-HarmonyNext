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

set(OHOS_ARCH arm64-v8a CACHE STRING "Target ABI (ADR-001: arm64-v8a first)" FORCE)
set(OHOS_STL c++_static CACHE STRING "Static libc++" FORCE)

include("${OHOS_NDK_PATH}/build/cmake/ohos.toolchain.cmake")

# The NDK toolchain restricts find_* to CMAKE_FIND_ROOT_PATH (ONLY modes) but
# only lists the NDK root itself, so sysroot headers/libs (zlib.h, libz.so)
# are invisible to find_package(ZLIB). Re-add the sysroot and our deps prefix.
list(APPEND CMAKE_FIND_ROOT_PATH "${OHOS_SDK_NATIVE}/sysroot")
if(DEFINED TDX_DEPS_PREFIX)
  list(APPEND CMAKE_FIND_ROOT_PATH "${TDX_DEPS_PREFIX}")
endif()
