; RUN: "%opt" -load-pass-plugin="%strength_reduction_plugin" -passes=strength-reduction -verify-each -S "%s" | "%FileCheck" "%s"

; Overflow flags are poison-generating semantic promises, not decoration.
define i32 @mul_flags(i32 %x) {
entry:
  %result = mul nuw nsw i32 %x, 8
  ret i32 %result
}

; CHECK-LABEL: define i32 @mul_flags(
; CHECK-NOT: mul
; CHECK: %result = shl nuw nsw i32 %x, 3
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; i8 -128 has a one-bit unsigned representation, but it is a negative signed
; multiplier. Keeping nsw on the shl would introduce poison for %x = 1, so the
; pass conservatively drops nsw for this special case.
define i8 @negative_sign_bit(i8 %x) {
entry:
  %result = mul nsw i8 %x, -128
  ret i8 %result
}

; CHECK-LABEL: define i8 @negative_sign_bit(
; CHECK-NOT: mul
; CHECK: %result = shl i8 %x, 7
; CHECK-NEXT: ret i8 %result
; CHECK-NEXT: }

; `nuw` remains valid for the same bit pattern even when `nsw` must be dropped.
define i8 @negative_sign_bit_with_nuw(i8 %x) {
entry:
  %result = mul nuw nsw i8 %x, -128
  ret i8 %result
}

; CHECK-LABEL: define i8 @negative_sign_bit_with_nuw(
; CHECK-NOT: mul
; CHECK: %result = shl nuw i8 %x, 7
; CHECK-NEXT: ret i8 %result
; CHECK-NEXT: }

; Exactness has the same meaning here: no non-zero remainder/discarded bits.
define i64 @udiv_exact(i64 %x) {
entry:
  %result = udiv exact i64 %x, 16
  ret i64 %result
}

; CHECK-LABEL: define i64 @udiv_exact(
; CHECK-NOT: udiv
; CHECK: %result = lshr exact i64 %x, 4
; CHECK-NEXT: ret i64 %result
; CHECK-NEXT: }
