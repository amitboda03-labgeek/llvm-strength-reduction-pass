add_library(StrengthReduction SHARED StrengthReduction.cpp)

target_include_directories(StrengthReduction SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
target_compile_features(StrengthReduction PRIVATE cxx_std_17)
target_compile_options(StrengthReduction PRIVATE
  $<$<CXX_COMPILER_ID:AppleClang,Clang,GNU>:-Wall;-Wextra;-Wpedantic>
)

if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(StrengthReduction PRIVATE -fno-rtti)
endif()

# LLVM symbols are supplied by the host `opt` process when the plugin is
# loaded. Darwin otherwise rejects those intentionally unresolved symbols.
target_link_libraries(StrengthReduction PRIVATE
  "$<$<PLATFORM_ID:Darwin>:-undefined dynamic_lookup>"
)
