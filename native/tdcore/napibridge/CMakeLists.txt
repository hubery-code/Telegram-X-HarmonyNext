# BRG-001/002 - tdcore_napi Node-API bridge build.
#
# Consumed two ways:
#   1. From the entry HAP via hvigor externalNativeOptions
#      (entry/src/main/cpp/CMakeLists.txt add_subdirectory's this file).
#      The OHOS NDK toolchain is supplied by hvigor; OHOS_SDK_NATIVE and
#      OHOS_ARCH are already set.
#   2. Standalone: cmake -DCMAKE_TOOLCHAIN_FILE=native/tdcore/cmake/ohos-toolchain.cmake
#      (the toolchain sets OHOS_SDK_NATIVE too).
#
# tdjson/openssl are referenced as imported SHARED targets from TDN-002's
# build tree (native/tdcore/build/...). hvigor automatically packages imported
# SHARED targets into the hap - do NOT copy them to entry/libs/ as well
# (hvigor fails with 00306049 duplicated files). See docs/runbooks/
# tdlib-native-build.md "打包要点".

cmake_minimum_required(VERSION 3.10)
project(tdcore_napi CXX)

if(NOT DEFINED OHOS_SDK_NATIVE)
  message(FATAL_ERROR "OHOS_SDK_NATIVE not set - build via hvigor or with native/tdcore/cmake/ohos-toolchain.cmake")
endif()

get_filename_component(NAPIBRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" ABSOLUTE)
# napibridge -> tdcore -> native -> <repo root>
get_filename_component(REPO_ROOT "${NAPIBRIDGE_DIR}/../../.." ABSOLUTE)
set(TDCORE_BUILD "${REPO_ROOT}/native/tdcore/build")

if(NOT OHOS_ARCH)
  set(OHOS_ARCH arm64-v8a)
endif()
set(OHOS_TRIPLE aarch64-linux-ohos)
if(OHOS_ARCH STREQUAL "x86_64")
  set(OHOS_TRIPLE x86_64-linux-ohos)
endif()

add_library(tdcore_napi SHARED src/tdcore_napi.cpp)

target_include_directories(tdcore_napi PRIVATE
    "${OHOS_SDK_NATIVE}/sysroot/usr/include")

set_target_properties(tdcore_napi PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON)

# Node-API runtime (system lib, resolved from the device image at runtime).
add_library(ace_napi SHARED IMPORTED)
set_target_properties(ace_napi PROPERTIES
    IMPORTED_LOCATION "${OHOS_SDK_NATIVE}/sysroot/usr/lib/${OHOS_TRIPLE}/libace_napi.z.so")
target_link_libraries(tdcore_napi PUBLIC ace_napi)

# TDLib + OpenSSL prebuilts from TDN-002.
# - tdjson: the stripped copy (HAP packaging picks up the imported target's
#   file verbatim; the unstripped build-tree .so stays for symbol archival).
# - OpenSSL: reference the versioned real files (libcrypto.so.3), NOT the
#   unversioned symlinks - hvigor copies the imported file under its basename
#   into the hap, and DT_NEEDED carries the .so.3 soname; basename must match.
add_library(tdjson SHARED IMPORTED)
set_target_properties(tdjson PROPERTIES
    IMPORTED_LOCATION "${TDCORE_BUILD}/arm64-v8a/stripped/libtdjson.so")
target_link_libraries(tdcore_napi PRIVATE tdjson)

set(OPENSSL_DIR "${TDCORE_BUILD}/deps/openssl/arm64-v8a")
foreach(ssl_lib crypto ssl)
  add_library(openssl_${ssl_lib} SHARED IMPORTED)
  set_target_properties(openssl_${ssl_lib} PROPERTIES
      IMPORTED_LOCATION "${OPENSSL_DIR}/lib/lib${ssl_lib}.so.3")
  target_link_libraries(tdcore_napi PRIVATE openssl_${ssl_lib})
endforeach()

# Static libc++ (mirrors OHOS_STL=c++_static used for the TDLib build).
target_link_options(tdcore_napi PRIVATE -static-libstdc++ -lunwind)
