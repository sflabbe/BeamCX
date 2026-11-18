# BeamCX v0.5.0 — UI polish R2

2026-11-18. English presentation and two-decimal display implemented. No commit or push.

## Presentation and naming

All application UI text is English, including the CONTINUOUS card, scrolling input, ends, envelope titles/legends, span/support tables, keyboard help, calculation state and invalid-document notice. The independent benchmark's continuous-case label is also English.

The shared formatter uses `string.format('%.2f', value)`. Exact zero, including IEEE negative zero, displays as `0.00`. Nonzero magnitudes below 0.005 use `%.2e` to preserve sign and scale; magnitudes at least 10⁷ use the same two-decimal mantissa to fit table columns. Formulas, version numbers, preset names and material/profile designations retain their established notation.

The local variable `car` was renamed to `characteristic_result` in `continuous_preset.lua`, the exhaustive harness, the independent Python reference and their tests. The display labels `w car.` became `w char.`. Existing function names were already English. No public API or internal table key was renamed, so **no compatibility aliases or migration were needed**. CAS names and serialized format/keys are unchanged.

No solver formulas, tolerances, matrices, boundary conditions, patterns, material data, navigation rules or packaging tools changed. ContinuousPreset changes are confined to the local identifier and two label strings. Frame, Frame.combine, BeamPreset and the material catalogue are unchanged.

## Precision and layout

Typed text stays complete while editing, including `6.123456789012345` and `0.000000000000000001`; fitting reduces font size without dropping digits. The formatter never writes to solver inputs, result objects, checks, saved values or exports. Tests compare both complete CAS export tables exactly with their full-precision summaries, including EI=10000.123456789.

`tests/fixtures/beam_v050_saved.lua` contains two real `on.save` snapshots captured from the pre-polish application. Both restore and save without changing any field or numerical value. Existing invalid-document handling and focus reset are retained.

The new presentation harness checks text rectangles for overlap and screen bounds at **318×212, 320×212 and 320×240** across all five systems, manual/concrete/steel sections, input/scroll states, all result modes, both continuous tables, restore notices and validation/CAS errors. Negative, zero and tiny loads, high ratios, exact keyboard text and wrapped diagnostics are included. Existing UI suites retain 2–5-span cache/cursor coverage. An 18-screen rendered contact sheet was also visually reviewed. Metrics are simulated; physical TI font and hardware acceptance remain with the owner.

The layout corrections are limited to a one-pixel single-span diagram footer overlap, the concise `Defl. limit` caption, and wrapping selector diagnostics without truncation.

## Numerical validation

**14 suites passed in Lua 5.1.5 and liblua 5.4.7**, including:

- 394 original Frame numeric rows and retained mechanics regressions.
- 2042 golden/adjudicated cases, all four original single-span presets, P0 witnesses and eight `bx_*` values.
- P5A.1 brute force: 300 models, 1050 spans, 4500 patterns; maximum normalized response/position error **4.67e-15**, unchanged from P5B-R1.
- Case E, unchanged continuous envelopes, full-precision `bc_*`, exact exported summary position and characteristic deflection recovery at that position.
- Deferred n+1 solves, a single stored sample cache, exact cursor and zero solves during paint.
- English strings/names, two-decimal/scientific formatting, negative zero, saved-document compatibility, unrounded editing and complete CAS values.

Executed the exact local CI sequence:

```bash
set -e
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
for test in tests/test_*.py; do
  echo "Running $test"
  python3 "$test"
done
```

Also executed:

```bash
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
luac5.1 -p BeamCX.lua
git diff --check
```

The five packaging tests passed. The existing Luna/USB guard and packaging process are unchanged.

## Package

`BeamCX.tns`: **28955 bytes**. Final USB packet: **130 bytes**, satisfying the existing guard. No padding was needed.

TNS SHA-256: `e52160578a3db833bb1af0046f94f8463fb7b04223e52acf50f7f27268dc86ec`.
Lua SHA-256: `76bbf567ad83c2b4c111806c3af150f2a4098cb3b225b6a99eb11e75362515d2`.

Owner checks remain: case E, five-span time, cursor responsiveness, CAS export, persistence and physical-font layout. No calculator validation is claimed. STOP.
