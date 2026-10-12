# Strength Reduction — an LLVM 23 pass plugin

An out-of-tree LLVM new-pass-manager plugin that performs two classic integer strength reductions directly on LLVM IR.

Before:

```llvm
%product  = mul  i32 %x, 8
%quotient = udiv i32 %x, 16
```

After:

```llvm
%product  = shl  i32 %x, 3
%quotient = lshr i32 %x, 4
```

The project is intentionally small enough to audit and complete enough to demonstrate production-relevant compiler engineering: dynamic pass registration, APInt-based reasoning, poison-aware flag handling, analysis invalidation, and regression tests with LLVM's `lit` and `FileCheck` tools.

> **Scope:** scalar integer operations with a compile-time constant power of two. Vector operations, floating-point operations, variable divisors, and signed division are deliberately left unchanged.

## What the pass does

For an `N`-bit scalar integer and a non-zero constant `C = 2^k`, the `strength-reduction` function pass applies:

| Input | Output | Notes |
| --- | --- | --- |
| `mul iN %x, C` | `shl iN %x, k` | Recognizes the constant on either side of the commutative multiply. |
| `udiv iN %x, C` | `lshr iN %x, k` | Requires the divisor to be the constant. |
| `udiv exact iN %x, C` | `lshr exact iN %x, k` | Preserves the equivalent poison condition. |

Everything else is left alone, including multiplication or unsigned division by zero, non-powers of two, variable operands, `sdiv`, vectors, and floating-point instructions. The implementation uses `llvm::APInt`, so the recognition logic is not limited to native C++ integer widths.

## Requirements

- macOS on Intel or Apple Silicon
- Homebrew
- CMake 3.20 or newer
- LLVM 18 or newer; the project is tested against Homebrew LLVM **23.1.3**
- LLVM's `lit` test runner and `FileCheck` (the latter ships with Homebrew LLVM)
- Ninja is recommended, although another CMake generator also works

Install the dependencies:

```sh
brew install llvm cmake ninja lit
```

Homebrew installs LLVM as a keg-only formula. The commands below therefore use the Homebrew prefix explicitly rather than accidentally mixing Apple's `/usr/bin/clang` with Homebrew's `opt` and LLVM libraries.

## Build

From the repository root:

```sh
LLVM_PREFIX="$(brew --prefix llvm)"

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_DIR="$LLVM_PREFIX/lib/cmake/llvm" \
  -DSR_LLVM_INSTALL_DIR="$LLVM_PREFIX"

cmake --build build
```

The plugin is produced at:

```text
build/lib/libStrengthReduction.dylib
```

`SR_LLVM_INSTALL_DIR` is optional when `LLVM_DIR` is supplied as above. It is retained as an llvm-tutor-style convenience for pointing CMake at one explicit LLVM installation root.

## Run

Load the plugin into the matching Homebrew build of `opt`, select the pass by its pipeline name, and print the transformed IR:

```sh
LLVM_PREFIX="$(brew --prefix llvm)"

"$LLVM_PREFIX/bin/opt" \
  -load-pass-plugin=build/lib/libStrengthReduction.dylib \
  -passes=strength-reduction \
  -S examples/input.ll \
  -o -
```

To save the result instead:

```sh
"$LLVM_PREFIX/bin/opt" \
  -load-pass-plugin=build/lib/libStrengthReduction.dylib \
  -passes=strength-reduction \
  -S examples/input.ll \
  -o build/output.ll
```

The plugin ABI is tied to the LLVM version used to build it. Always load it with `opt` from that same LLVM installation; a plugin built against LLVM 23 is not expected to load into Apple's compiler tools or another LLVM major release.

Like LLVM's normal optimization passes, this pass respects the `optnone` function attribute. Clang adds that attribute at `-O0`; when generating demo IR from C/C++, disable it explicitly so the function pass is allowed to run:

```sh
"$LLVM_PREFIX/bin/clang" -O0 -Xclang -disable-O0-optnone \
  -S -emit-llvm input.c -o build/input.ll
```

## Test

Build and run the complete regression suite through its CMake target:

```sh
cmake --build build --target check-strength-reduction
```

The checked-in macOS GitHub Actions workflow repeats configuration, a warning-clean build, the lit/FileCheck suite, and CTest against Homebrew LLVM 23 on every push and pull request.

For verbose output from a direct lit invocation:

```sh
"$(brew --prefix lit)/bin/lit" -sv build/test
```

If lit lives elsewhere, pass `-DSR_LIT_EXECUTABLE=/absolute/path/to/lit` when configuring. The CMake check target remains the preferred entry point because it uses the runner selected at configure time.

The suite runs `opt` with the dynamically loaded plugin and pipes the emitted IR into `FileCheck`. A second debugify run checks that debug locations survive rewriting. The suite covers both successful rewrites and important non-rewrites:

| Test | Coverage |
| --- | --- |
| `test/basic.ll` | Multiply with the constant on either side, `2^0`, a sign-bit divisor, a rewrite chain, debugify, and an `i128`/`2^80` case that guards against accidental 64-bit truncation. |
| `test/unchanged.ll` | Zero, positive and negative non-powers, variable divisors, constant numerators, signed division, floating point, fixed vectors, and `optnone` functions remain unchanged. |
| `test/flags.ll` | `nuw`, `nsw`, combined flags on the sign-bit multiplier, and `exact` propagation. |

`CHECK-LABEL` and `CHECK-NEXT` assertions pin each transformation to the intended function and result. The signed-division test also uses `CHECK-NOT: ashr` to make the forbidden rewrite explicit.

## Why does `-O2` already do this?

Because LLVM already has the optimization—and that is a feature of this project, not something it tries to hide.

LLVM's `InstCombine` pass canonicalizes multiplication by powers of two to left shifts and unsigned division by powers of two to logical right shifts. `-O2` includes InstCombine in its optimization pipeline, so a production compiler normally performs these rewrites without this plugin. You can observe that directly:

```sh
LLVM_PREFIX="$(brew --prefix llvm)"

"$LLVM_PREFIX/bin/opt" -passes=instcombine -S examples/input.ll -o -
"$LLVM_PREFIX/bin/opt" -O2 -S examples/input.ll -o -
```

Because the example deliberately chains the operations, InstCombine may compose the two rewrites further (for LLVM 23 it emits a `shl` plus an `and`) rather than leaving one visible `shl` and one `lshr`. The standalone functions in `test/basic.ll` show each canonicalization independently.

The value here is not a novel optimization claim. It is a focused implementation exercise in the same mechanics real LLVM work requires: expressing an IR legality argument, using the new pass manager, registering an out-of-tree shared library, preserving poison-generating flags, invalidating analyses correctly, and writing durable IR-level tests. LLVM's own implementation is visible in [`InstCombineMulDivRem.cpp` at the LLVM 23.1.3 tag](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.3/llvm/lib/Transforms/InstCombine/InstCombineMulDivRem.cpp).

## Correctness, not just pattern matching

### Multiplication

LLVM integer multiplication is computed modulo `2^N` unless a no-wrap flag adds a stronger poison-producing contract. For `C = 2^k`:

```text
x * C mod 2^N = x << k mod 2^N
```

This justifies the base rewrite for every bit pattern. A representable, non-zero power of two also guarantees `0 <= k < N`, so the generated shift amount is in range.

The flags need separate care:

- `nuw` is copied because unsigned overflow of `x * 2^k` is equivalent to shifting non-zero bits out of the left side.
- `nsw` is copied only when the multiplier is not the sign-bit value. For an `iN` constant with only its sign bit set, the same bits denote `-2^(N-1)` as a signed multiply operand, while a left shift still behaves like multiplication by positive `2^(N-1)` for its `nsw` rule. Blindly copying `nsw` would introduce poison for a source-defined case such as `i8 1 * -128`. Dropping the flag makes some source-poison cases concrete, which is a legal LLVM refinement; it does not claim to preserve the original poison set exactly.

This distinction is easy to miss and is exactly why optimization work must be justified against LLVM IR semantics rather than against an informal algebraic identity.

### Unsigned division

For unsigned `x` and `C = 2^k`, discarding the low `k` bits is the same as taking the integer quotient:

```text
floor(x / 2^k) = x logical-right-shift k
```

An `exact udiv` is poison when the division has a non-zero remainder. An `exact lshr` is poison when any shifted-out bit is non-zero. For a power-of-two divisor, those are the same low `k` bits, so preserving `exact` is correct.

The authoritative definitions of these operations and flags are in the LLVM Language Reference: [`mul`](https://llvm.org/docs/LangRef.html#mul-instruction), [`udiv`](https://llvm.org/docs/LangRef.html#udiv-instruction), [`shl`](https://llvm.org/docs/LangRef.html#shl-instruction), and [`lshr`](https://llvm.org/docs/LangRef.html#lshr-instruction).

## Why signed division is not an arithmetic shift

LLVM `sdiv` rounds toward zero. Arithmetic right shift replicates the sign bit and, for negative values with a remainder, behaves like rounding toward negative infinity. A concrete counterexample is enough:

```text
-3 sdiv 2  = -1
-3 ashr 1  = -2
```

Replacing a general `sdiv %x, 2^k` with `ashr %x, k` is therefore wrong. A correct lowering needs a bias for negative, non-divisible numerators before the shift (or a proof such as exact divisibility). This pass deliberately does not transform `sdiv`; that boundary is tested.

## Architecture

```text
.
├── .github/workflows/ci.yml
├── CMakeLists.txt
├── lib/
│   ├── CMakeLists.txt
│   └── StrengthReduction.cpp
├── examples/
│   └── input.ll
└── test/
    ├── CMakeLists.txt
    ├── lit.cfg.py
    ├── lit.site.cfg.py.in
    ├── basic.ll
    ├── unchanged.ll
    └── flags.ll
```

- `StrengthReduction.cpp` implements a new-pass-manager function pass, walks scalar integer instructions safely while replacing them, returns all analyses when unchanged, and preserves the CFG-analysis set after a rewrite because no block or edge changes.
- Its `llvmGetPassPluginInfo` entry point registers a pipeline-parsing callback, which maps `strength-reduction` to the pass.
- `add_library(StrengthReduction SHARED ...)` builds the loadable module without modifying or rebuilding LLVM; on macOS, LLVM symbols are resolved from the host `opt` process at load time.
- The lit site configuration injects the just-built plugin path and the selected LLVM tools into each test.

This follows LLVM's documented [new pass manager plugin model](https://llvm.org/docs/WritingAnLLVMNewPMPass.html#registering-passes-as-plugins) and uses the same general out-of-tree structure taught by [llvm-tutor](https://github.com/banach-space/llvm-tutor).

## Interview talking points

1. **IR semantics before machine folklore.** The rewrite is justified for fixed-width LLVM integers; the `sdiv` counterexample shows why “division is a shift” is too broad.
2. **Flags are semantic.** `nuw`, `nsw`, and `exact` affect poison and optimization freedom. They are not decoration, and the sign-bit `nsw` case prevents blind copying.
3. **Legality and profitability are different questions.** These rewrites are legal at the IR level. Whether a target should literally use a shift instruction is ultimately a backend cost/code-generation decision.
4. **Pass-manager hygiene matters.** The plugin exposes the stable pass-plugin entry point, registers a textual pipeline name, and precisely preserves CFG-only analyses while invalidating analyses that may depend on changed values.
5. **Toolchain consistency matters.** A pass plugin is a C++ shared object using LLVM's ABI, so `opt`, headers, libraries, and the plugin must come from the same LLVM installation.
6. **Tests specify boundaries.** Positive FileCheck cases prove the rewrite; negative cases prevent semantic scope from expanding accidentally.
7. **The honest production answer is InstCombine.** This standalone pass is a compact, reviewable demonstration of the engineering, while LLVM's mature canonicalizer already owns the optimization in real pipelines.

## Resume bullet

> Built a C++ out-of-tree LLVM new-pass-manager plugin that strength-reduces scalar power-of-two `mul`/`udiv` operations, applies refinement-correct `nuw`/`nsw`/`exact` handling, and is regression-tested with lit/FileCheck against LLVM 23; documented overlap with LLVM's production InstCombine pass.

## Primary references

- [Writing an LLVM new-PM pass and registering a plugin](https://llvm.org/docs/WritingAnLLVMNewPMPass.html)
- [Using LLVM's new pass manager](https://llvm.org/docs/NewPassManager.html)
- [LLVM Language Reference Manual](https://llvm.org/docs/LangRef.html)
- [LLVM 23.1.3 InstCombine multiply/divide/remainder implementation](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.3/llvm/lib/Transforms/InstCombine/InstCombineMulDivRem.cpp)
- [LLVM `lit` command guide](https://llvm.org/docs/CommandGuide/lit.html)
- [LLVM `FileCheck` command guide](https://llvm.org/docs/CommandGuide/FileCheck.html)

## License

This project is available under the MIT License. See `LICENSE`.
