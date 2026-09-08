# Entry HAP native build - delegates to the tdcore Node-API bridge
# (native/tdcore/napibridge). Built by hvigor via
# buildOption.externalNativeOptions in entry/build-profile.json5.

cmake_minimum_required(VERSION 3.10)
project(entry_native CXX)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)

add_subdirectory("${REPO_ROOT}/native/tdcore/napibridge" "${CMAKE_CURRENT_BINARY_DIR}/napibridge")
