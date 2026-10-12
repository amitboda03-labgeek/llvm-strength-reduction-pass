//===- StrengthReduction.cpp - Simple arithmetic strength reduction -------===//
//
// An out-of-tree New Pass Manager plugin, structured after llvm-tutor.
//
// This pass intentionally implements two small, teachable canonicalizations:
//   x * 2^k  -> x << k
//   x /u 2^k -> x >>u k
//
// LLVM's InstCombine already performs these folds. The value of this plugin is
// in demonstrating IR semantics, transformation hygiene, plugin registration,
// and regression testing rather than replacing production LLVM machinery.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/APInt.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Config/llvm-config.h"
#include "llvm/IR/Analysis.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#if __has_include("llvm/Plugins/PassPlugin.h")
#include "llvm/Plugins/PassPlugin.h"
#else
#include "llvm/Passes/PassPlugin.h"
#endif
#include "llvm/Support/Compiler.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>

using namespace llvm;

#define DEBUG_TYPE "strength-reduction"

STATISTIC(MulReduced, "Number of power-of-two multiplies changed to shifts");
STATISTIC(UDivReduced,
          "Number of power-of-two unsigned divides changed to shifts");

namespace {

struct PowerOfTwo {
  ConstantInt *Constant;
  unsigned Exponent;
};

static std::optional<PowerOfTwo> getPowerOfTwo(Value *V) {
  auto *C = dyn_cast<ConstantInt>(V);
  if (!C || !C->getValue().isPowerOf2())
    return std::nullopt;

  return PowerOfTwo{C, C->getValue().logBase2()};
}

static void replaceInstruction(BinaryOperator &Old,
                               BinaryOperator &Replacement) {
  Replacement.setDebugLoc(Old.getDebugLoc());
  Replacement.copyMetadata(Old);
  Replacement.takeName(&Old);
  Old.replaceAllUsesWith(&Replacement);
  Old.eraseFromParent();
}

static bool reduceMultiply(BinaryOperator &Mul) {
  Value *Multiplicand = nullptr;
  std::optional<PowerOfTwo> Factor = getPowerOfTwo(Mul.getOperand(1));

  if (Factor) {
    Multiplicand = Mul.getOperand(0);
  } else {
    Factor = getPowerOfTwo(Mul.getOperand(0));
    if (!Factor)
      return false;
    Multiplicand = Mul.getOperand(1);
  }

  auto *ShiftAmount = ConstantInt::get(Mul.getType(), Factor->Exponent);
#if LLVM_VERSION_MAJOR >= 19
  auto *Shift = BinaryOperator::CreateShl(Multiplicand, ShiftAmount, "",
                                          Mul.getIterator());
#else
  auto *Shift = BinaryOperator::CreateShl(Multiplicand, ShiftAmount, "", &Mul);
#endif

  // nuw has identical overflow behavior for multiplication and left shift by
  // a power of two. nsw is also equivalent for a positive signed multiplier.
  // The sign-bit-only constant (for example i8 -128) is a power of two as an
  // unsigned bit pattern, but copying nsw there would introduce extra poison.
  Shift->setHasNoUnsignedWrap(Mul.hasNoUnsignedWrap());
  if (!Factor->Constant->getValue().isNegative())
    Shift->setHasNoSignedWrap(Mul.hasNoSignedWrap());

  LLVM_DEBUG(dbgs() << "strength-reduction: " << Mul << "  ->  " << *Shift
                    << '\n');
  replaceInstruction(Mul, *Shift);
  ++MulReduced;
  return true;
}

static bool reduceUnsignedDivide(BinaryOperator &UDiv) {
  std::optional<PowerOfTwo> Divisor = getPowerOfTwo(UDiv.getOperand(1));
  if (!Divisor)
    return false;

  auto *ShiftAmount = ConstantInt::get(UDiv.getType(), Divisor->Exponent);
#if LLVM_VERSION_MAJOR >= 19
  auto *Shift = BinaryOperator::CreateLShr(UDiv.getOperand(0), ShiftAmount, "",
                                           UDiv.getIterator());
#else
  auto *Shift =
      BinaryOperator::CreateLShr(UDiv.getOperand(0), ShiftAmount, "", &UDiv);
#endif

  // `exact udiv` means that the discarded remainder is zero. `exact lshr`
  // expresses the same condition: every shifted-out bit must be zero.
  Shift->setIsExact(UDiv.isExact());

  LLVM_DEBUG(dbgs() << "strength-reduction: " << UDiv << "  ->  " << *Shift
                    << '\n');
  replaceInstruction(UDiv, *Shift);
  ++UDivReduced;
  return true;
}

class StrengthReductionPass : public PassInfoMixin<StrengthReductionPass> {
public:
  PreservedAnalyses run(Function &F, FunctionAnalysisManager &) {
    SmallVector<BinaryOperator *, 8> Worklist;

    // Collect first, then rewrite. This keeps iterator invalidation out of the
    // transformation loop and makes chains of candidate instructions safe.
    for (Instruction &I : instructions(F)) {
      auto *BinOp = dyn_cast<BinaryOperator>(&I);
      if (!BinOp || !BinOp->getType()->isIntegerTy())
        continue;

      if (BinOp->getOpcode() == Instruction::Mul ||
          BinOp->getOpcode() == Instruction::UDiv)
        Worklist.push_back(BinOp);
    }

    bool Changed = false;
    for (BinaryOperator *BinOp : Worklist) {
      if (BinOp->getOpcode() == Instruction::Mul)
        Changed |= reduceMultiply(*BinOp);
      else
        Changed |= reduceUnsignedDivide(*BinOp);
    }

    if (!Changed)
      return PreservedAnalyses::all();

    // Arithmetic instructions changed, but basic blocks and edges did not.
    // Keep CFG-only analyses such as dominators and loops valid.
    PreservedAnalyses PA;
    PA.preserveSet<CFGAnalyses>();
    return PA;
  }
};

} // namespace

PassPluginLibraryInfo getStrengthReductionPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "StrengthReduction", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerPipelineParsingCallback(
                [](StringRef Name, FunctionPassManager &FPM,
                   ArrayRef<PassBuilder::PipelineElement>) {
                  if (Name != "strength-reduction")
                    return false;

                  FPM.addPass(StrengthReductionPass());
                  return true;
                });
          }};
}

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
  return getStrengthReductionPluginInfo();
}
