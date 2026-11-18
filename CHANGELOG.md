# Changelog

## 0.3.2
- Added a visual 2×2 support-system selector with compact schematics and reference M silhouettes for a downward uniform load (`q>0`), independent of the current model.
- Confirm systems with Enter using transactional calculation and full rollback on failure. New documents start at the selector; Esc returns to it and Tab has no effect there.
- Esc clears an input error when a valid result exists; malformed numeric text retains the confirmed model's solution. Failed-calculation diagnostics remain available.
- Preserved legacy document pages, loads and sections; selector saves restore focus to the confirmed support without adding saved fields.
- Added reference-formula, drawing-sign, layout, no-solve repaint, Esc/CAS recovery and persistence checks.

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
