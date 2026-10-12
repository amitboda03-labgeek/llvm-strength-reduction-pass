; RUN: "%opt" -load-pass-plugin="%strength_reduction_plugin" -passes=strength-reduction -verify-each -S "%s" | "%FileCheck" "%s"
; RUN: "%opt" -load-pass-plugin="%strength_reduction_plugin" -passes='debugify,function(strength-reduction),check-debugify' -disable-output "%s" 2>&1 | "%FileCheck" "%s" --check-prefix=DEBUGIFY
; DEBUGIFY: CheckModuleDebugify: PASS

; Multiplication works with the constant on either side.
define i32 @mul_rhs(i32 %x) {
entry:
  %result = mul i32 %x, 8
  ret i32 %result
}

; CHECK-LABEL: define i32 @mul_rhs(
; CHECK-NOT: mul
; CHECK: %result = shl i32 %x, 3
; CHECK-NOT: mul
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

define i64 @mul_lhs(i64 %x) {
entry:
  %result = mul i64 16, %x
  ret i64 %result
}

; CHECK-LABEL: define i64 @mul_lhs(
; CHECK-NOT: mul
; CHECK: %result = shl i64 %x, 4
; CHECK-NOT: mul
; CHECK-NEXT: ret i64 %result
; CHECK-NEXT: }

; One is 2^0, so this deliberately becomes a shift by zero.
define i8 @mul_one(i8 %x) {
entry:
  %result = mul i8 %x, 1
  ret i8 %result
}

; CHECK-LABEL: define i8 @mul_one(
; CHECK-NOT: mul
; CHECK: %result = shl i8 %x, 0
; CHECK-NOT: mul
; CHECK-NEXT: ret i8 %result
; CHECK-NEXT: }

define i32 @udiv_rhs(i32 %x) {
entry:
  %result = udiv i32 %x, 32
  ret i32 %result
}

; CHECK-LABEL: define i32 @udiv_rhs(
; CHECK-NOT: udiv
; CHECK: %result = lshr i32 %x, 5
; CHECK-NOT: udiv
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

define i16 @udiv_one(i16 %x) {
entry:
  %result = udiv i16 %x, 1
  ret i16 %result
}

; CHECK-LABEL: define i16 @udiv_one(
; CHECK-NOT: udiv
; CHECK: %result = lshr i16 %x, 0
; CHECK-NOT: udiv
; CHECK-NEXT: ret i16 %result
; CHECK-NEXT: }

; In unsigned arithmetic, the sign bit is still a valid power-of-two divisor.
define i8 @udiv_sign_bit(i8 %x) {
entry:
  %result = udiv i8 %x, -128
  ret i8 %result
}

; CHECK-LABEL: define i8 @udiv_sign_bit(
; CHECK-NOT: udiv
; CHECK: %result = lshr i8 %x, 7
; CHECK-NOT: udiv
; CHECK-NEXT: ret i8 %result
; CHECK-NEXT: }

; Candidate instructions can form a chain without invalidating traversal.
define i32 @chain(i32 %x) {
entry:
  %scaled = mul i32 %x, 4
  %result = udiv i32 %scaled, 2
  ret i32 %result
}

; CHECK-LABEL: define i32 @chain(
; CHECK-NOT: mul
; CHECK-NOT: udiv
; CHECK: %scaled = shl i32 %x, 2
; CHECK-NEXT: %result = lshr i32 %scaled, 1
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; APInt keeps this correct beyond native 64-bit integer widths (2^80).
define i128 @wide_integer(i128 %x) {
entry:
  %result = mul i128 %x, 1208925819614629174706176
  ret i128 %result
}

; CHECK-LABEL: define i128 @wide_integer(
; CHECK-NOT: mul
; CHECK: %result = shl i128 %x, 80
; CHECK-NOT: mul
; CHECK-NEXT: ret i128 %result
; CHECK-NEXT: }
