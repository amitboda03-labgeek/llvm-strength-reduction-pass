find_program(SR_LIT_EXECUTABLE
  NAMES llvm-lit lit
  HINTS "${LLVM_TOOLS_BINARY_DIR}"
  DOC "Path to llvm-lit or lit"
)

if(NOT SR_LIT_EXECUTABLE)
  message(FATAL_ERROR
    "lit was not found. Install it with `brew install lit` (macOS) or "
    "`python3 -m pip install lit`, then re-run CMake. Alternatively set "
    "-DSR_LIT_EXECUTABLE=/path/to/lit."
  )
endif()

set(SR_TEST_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(SR_TEST_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}")
set(SR_PLUGIN_PATH
  "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/${CMAKE_SHARED_LIBRARY_PREFIX}StrengthReduction${CMAKE_SHARED_LIBRARY_SUFFIX}"
)

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in"
  "${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py"
  @ONLY
)

add_custom_target(check-strength-reduction
  COMMAND "${SR_LIT_EXECUTABLE}" -sv "${CMAKE_CURRENT_BINARY_DIR}"
  DEPENDS StrengthReduction
  COMMENT "Running StrengthReduction lit tests"
  USES_TERMINAL
)

add_test(
  NAME strength-reduction-lit
  COMMAND "${SR_LIT_EXECUTABLE}" -sv "${CMAKE_CURRENT_BINARY_DIR}"
)
