cmake_minimum_required(VERSION 3.20)

project(
  LLVMStrengthReduction
  VERSION 1.0.0
  DESCRIPTION "An out-of-tree LLVM strength-reduction pass plugin"
  # LLVMConfig performs a few C-language feature checks while configuring.
  LANGUAGES C CXX
)

# Mirrors llvm-tutor's explicit installation-root option while also supporting
# the standard -DLLVM_DIR=/path/to/lib/cmake/llvm spelling.
set(SR_LLVM_INSTALL_DIR "" CACHE PATH "Root of the LLVM installation")
if(SR_LLVM_INSTALL_DIR)
  list(PREPEND CMAKE_PREFIX_PATH
    "${SR_LLVM_INSTALL_DIR}/lib/cmake/llvm"
    "${SR_LLVM_INSTALL_DIR}/lib64/cmake/llvm"
  )
endif()

find_package(LLVM REQUIRED CONFIG)

if(LLVM_VERSION_MAJOR VERSION_LESS 18)
  message(FATAL_ERROR "LLVM 18 or newer is required; found ${LLVM_PACKAGE_VERSION}")
endif()

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake from ${LLVM_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")

# Keep the plugin path stable for lit under both single-config generators
# (Ninja/Make) and multi-config generators (Xcode/Ninja Multi-Config).
foreach(SR_CONFIG IN LISTS CMAKE_CONFIGURATION_TYPES)
  string(TOUPPER "${SR_CONFIG}" SR_CONFIG_UPPER)
  set("CMAKE_LIBRARY_OUTPUT_DIRECTORY_${SR_CONFIG_UPPER}"
      "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
endforeach()

add_definitions(${LLVM_DEFINITIONS})

add_subdirectory(lib)

option(SR_BUILD_TESTS "Build the lit/FileCheck regression suite" ON)
if(SR_BUILD_TESTS)
  include(CTest)
  enable_testing()
  add_subdirectory(test)
endif()
