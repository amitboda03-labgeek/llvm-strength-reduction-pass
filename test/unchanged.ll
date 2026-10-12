; RUN: "%opt" -load-pass-plugin="%strength_reduction_plugin" -passes=strength-reduction -verify-each -S "%s" | "%FileCheck" "%s"

; Non-powers of two and zero are not candidates.
define i32 @mul_non_power(i32 %x) {
entry:
  %by_three = mul i32 %x, 3
  %by_zero = mul i32 %by_three, 0
  ret i32 %by_zero
}

; CHECK-LABEL: define i32 @mul_non_power(
; CHECK: %by_three = mul i32 %x, 3
; CHECK-NEXT: %by_zero = mul i32 %by_three, 0
; CHECK-NOT: shl
; CHECK-NEXT: ret i32 %by_zero
; CHECK-NEXT: }

define i32 @mul_negative_non_power(i32 %x) {
entry:
  %result = mul i32 %x, -8
  ret i32 %result
}

; CHECK-LABEL: define i32 @mul_negative_non_power(
; CHECK: %result = mul i32 %x, -8
; CHECK-NOT: shl
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; Only a constant divisor is reduced.
define i32 @udiv_variable(i32 %x, i32 %divisor) {
entry:
  %result = udiv i32 %x, %divisor
  ret i32 %result
}

; CHECK-LABEL: define i32 @udiv_variable(
; CHECK: %result = udiv i32 %x, %divisor
; CHECK-NOT: lshr
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; Division is not commutative: a constant numerator proves nothing about a
; variable divisor.
define i32 @udiv_constant_numerator(i32 %divisor) {
entry:
  %result = udiv i32 8, %divisor
  ret i32 %result
}

; CHECK-LABEL: define i32 @udiv_constant_numerator(
; CHECK: %result = udiv i32 8, %divisor
; CHECK-NOT: lshr
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

define i32 @udiv_non_power(i32 %x) {
entry:
  %result = udiv i32 %x, 10
  ret i32 %result
}

; CHECK-LABEL: define i32 @udiv_non_power(
; CHECK: %result = udiv i32 %x, 10
; CHECK-NOT: lshr
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; Signed division is intentionally excluded: sdiv rounds toward zero, while
; ashr rounds negative values toward negative infinity.
define i32 @signed_division(i32 %x) {
entry:
  %result = sdiv i32 %x, 8
  ret i32 %result
}

; CHECK-LABEL: define i32 @signed_division(
; CHECK: %result = sdiv i32 %x, 8
; CHECK-NOT: ashr
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

; The pass is deliberately about integer arithmetic, not floating point.
define float @floating_multiply(float %x) {
entry:
  %result = fmul float %x, 8.0
  ret float %result
}

; CHECK-LABEL: define float @floating_multiply(
; CHECK: %result = fmul float %x, 8.000000e+00
; CHECK-NOT: shl
; CHECK-NEXT: ret float %result
; CHECK-NEXT: }

; Fixed vectors are an explicit v1 non-goal, even when every lane is a power
; of two. These cases pin that documented scalar-only boundary.
define <4 x i32> @vector_multiply(<4 x i32> %x) {
entry:
  %result = mul <4 x i32> %x, <i32 2, i32 4, i32 8, i32 16>
  ret <4 x i32> %result
}

; CHECK-LABEL: define <4 x i32> @vector_multiply(
; CHECK: %result = mul <4 x i32> %x, <i32 2, i32 4, i32 8, i32 16>
; CHECK-NOT: shl
; CHECK-NEXT: ret <4 x i32> %result
; CHECK-NEXT: }

define <2 x i16> @vector_divide(<2 x i16> %x) {
entry:
  %result = udiv <2 x i16> %x, <i16 2, i16 8>
  ret <2 x i16> %result
}

; CHECK-LABEL: define <2 x i16> @vector_divide(
; CHECK: %result = udiv <2 x i16> %x, <i16 2, i16 8>
; CHECK-NOT: lshr
; CHECK-NEXT: ret <2 x i16> %result
; CHECK-NEXT: }

; Transformation passes conventionally respect optnone. This also catches an
; easy demo pitfall when consuming IR produced by clang -O0.
define i32 @optnone_function(i32 %x) #0 {
entry:
  %result = mul i32 %x, 8
  ret i32 %result
}

; CHECK-LABEL: define i32 @optnone_function(
; CHECK: %result = mul i32 %x, 8
; CHECK-NOT: shl
; CHECK-NEXT: ret i32 %result
; CHECK-NEXT: }

attributes #0 = { noinline optnone }
