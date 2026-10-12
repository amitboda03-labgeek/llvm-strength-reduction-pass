import os

import lit.formats


config.name = "StrengthReduction"
config.test_format = lit.formats.ShTest()
config.suffixes = [".ll"]
config.excludes = ["CMakeLists.txt", "lit.cfg.py", "lit.site.cfg.py.in"]

# Resolve LLVM tools explicitly so Apple-provided binaries or unrelated LLVM
# installations earlier on PATH cannot accidentally run the suite.
config.substitutions.append(
    ("%opt", os.path.join(config.llvm_tools_dir, "opt"))
)
config.substitutions.append(
    ("%FileCheck", os.path.join(config.llvm_tools_dir, "FileCheck"))
)
config.substitutions.append(
    ("%strength_reduction_plugin", config.strength_reduction_plugin)
)
