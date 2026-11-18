# Changelog

## 0.3.3
- Load arrows follow the sign of P and calculated total q, including self-weight; one filled head per arrow is retained.
- Moved loads below the measured diagram title, inset UDL arrows from supports, and kept P longer than q arrows. Catalogue EI now displays `(auto)` in the value column, separate from units.
- **Result change only for concrete cantilevers:** `Lref = 2.5·L` per DIN EN 1992-1-1/NA 7.4.1 changes `u250`, `u300` and `Lref/|w|`. Physical deflection, reactions, moments and the eight `bx_` variables are unchanged. Other supports still use L.
- Steel and MANUAL cantilevers retain `Lref = L` and display `CANTILEVER: AGREE LIMIT`; project / National Annex limits apply (EN 1993-1-1, 7.2).
- Added Lua 5.1 syntax and analytical/UI checks to CI, plus signed-load, layout, reference-length and CAS regressions.
- Package: **12,465 bytes**, official Luna commit **`a9924a9`**, rebuilt from source; identical output in two local packaging runs. Not yet tested on hardware or transferred by N-Link.

## 0.3.2
- Added a visual 2×2 support-system selector with compact schematics and reference M silhouettes for a downward uniform load (`q>0`), independent of the current model.
- Confirm systems with Enter using transactional calculation and full rollback on failure. New documents start at the selector; Esc returns to it and Tab has no effect there.
- Esc clears an input error when a valid result exists; malformed numeric text retains the confirmed model's solution. Failed-calculation diagnostics remain available.
- Preserved legacy document pages, loads and sections; selector saves restore focus to the confirmed support without adding saved fields.
- Added reference-formula, drawing-sign, layout, no-solve repaint, Esc/CAS recovery and persistence checks.
- Hardware validation: TI-Nspire CX CAS OS 4.5.5.79 on 2026-11-18; selector / silhouettes, Esc / editing, inert Tab, invalid-number recovery / CAS export, selector save, and analytical FIX-PIN results verified.
- Hardware-tested package: **12,006 bytes**, official Luna **`a9924a9`**. Initial 11,938-byte package stalled N-Link at 91%; see README for the local-build size discrepancy.

## 0.3
- Added analytical maximum absolute deflection and position, span/deflection ratio, L/250 and L/300 utilization and selectable comparison status.
- Added compact results within the existing diagram page; concrete warning `RC: GROSS EI ONLY`.
- Added optional self-weight (default OFF): ArcelorMittal IPE/HEA masses and nominal concrete unit weight 25 kN/m³. User load remains separate; old saves default to OFF and L/250.
- Added explicit EXPORT CAS using native `var.store`, documented `bx_` numeric variables, failed-solve blocking and visible API errors.
- Preserved solver mechanics, moment plot signs, load arrows and three-page navigation; added analytical, UI, export and persistence regressions.

## 0.2.3
- Replaced open-V load arrowheads with a single filled triangle for point and distributed loads.

## 0.2.2
- Reduced beam/support and diagram line widths.

## 0.2.1
- Plot positive sagging bending moments below the reference line; negative hogging moments above.

## 0.2.0
- Added offline concrete/steel material data, rectangular concrete sections, IPE/HEA catalog and automatic EI.
- Added model persistence and input/UI fixes.

## 0.1.0
- Single-span linear Euler–Bernoulli beam solver, M/V/deflection graphs and cursor.
