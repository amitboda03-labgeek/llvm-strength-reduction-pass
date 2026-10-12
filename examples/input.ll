; Try it with:
;   "$(brew --prefix llvm)/bin/opt" \
;       -load-pass-plugin=build/lib/libStrengthReduction.dylib \
;       -passes=strength-reduction -S examples/input.ll

define i32 @scale_and_bucket(i32 %value) {
entry:
  %scaled = mul i32 %value, 8
  %bucket = udiv i32 %scaled, 4
  ret i32 %bucket
}
