# Changelog

## 0.6.0 — P6C-0-R1 development
- Separated single-span, continuous, portal and section presentation into four static UI fragments. The main entry point retains shared state, events, calculation/cache scheduling, editing, rollback, CAS and persistence. All existing function bodies are unchanged.
- Added an offline, hash-checked P6B bundle and exact differential event/graphics comparison at 318×212, 320×212 and 320×240. Numerical modules, catalogue, historical fixtures, exports and document format remain unchanged; no portal section selection.
- Validation and before/after evidence: VALIDATION_P6C0.md and P6C0_UI_COMPARISON.png. Original-CX acceptance of this refactor remains pending; accepted P6B hardware behavior is the baseline.

## 0.6.0 — P6B-R1 rectangular portal
- Added the sixth PORTAL selector card and productive UI → PortalPreset.solve → Frame.solve route. All four numerical modules remain frozen from P6A CLOSED/PASS.
- Added scrolling manual h/l, equal PIN/FIX bases, EIc/EIb and characteristic q/P/a/H/w input, deferred timer calculation and transactional recovery after failed edits/calculations. No portal catalogue or self-weight.
- Added cached M/V/N and absolute deformed-shape views, 1/2/3 member selection and one local recovery query per cursor change. Moment ordinates follow each member's actual tension side; point-load shear limits stay distinct.
- Added scrolling reactions/member/corner/deformation results using the P6A chord-relative beam deflection, OPEN project/NA limits, and fourteen explicit unrounded bp_* CAS exports. Existing bx_*/bc_* contracts are unchanged.
- Persistence now accepts only complete exact format 0.6.0. All older versions, including both retained v0.5 documents, are rejected atomically with defaults and the existing warning; no migration. Deferred results restore at input.
- PC regression: 16 suites in Lua 5.1.5 and 5.4.7; 394 Frame rows, 2042 historical cases, 300 continuous models, 136 P6A portal models and six oracles retained. Ten-screen real-drawing contact sheet and owner acceptance checklist: VALIDATION_P6B.md.
- Status: **PC IMPLEMENTATION/PASS — HARDWARE PENDING** on the original TI-Nspire CX CAS. No hardware rendering or timing is inferred from PC simulation.

## 0.5.0 — UI polish R2
- Standardized all application UI text to English, including CONTINUOUS, forms, envelopes, tables, instructions, restore notices and feedback. Updated the benchmark's continuous-case label.
- Display results with two decimal places; normalize negative zero. Tiny nonzero magnitudes below 0.005 and large magnitudes from 10⁷ use scientific notation with a two-decimal mantissa. Keyboard editing, saves, calculations and both CAS exports retain full precision.
- Renamed local `car` to `characteristic_result` in the continuous preset and matching test/reference code. Translated `w car.` labels to `w char.`. Public APIs, persistent fields and CAS names are unchanged; no compatibility aliases are needed.
- Wrapped long selector errors, fitted editable text without dropping digits, and corrected a footer overlap and a translated section caption. Reviewed all relevant screens at 318×212, 320×212 and 320×240 with simulated font metrics.
- All 14 suites pass in Lua 5.1.5 and 5.4.7; the 394 Frame rows, 2042 golden cases and P5A.1 300-model comparison are preserved. Package: **28955 bytes**, final USB packet **130 bytes**. See VALIDATION_P5B_UI_POLISH_R2.md. No hardware acceptance is claimed.

## 0.5.0 — P5B / P5B-R1 original delivery
- Added CONTINUOUS to a 3×2 selector with five cards, support schemes, normalized M silhouettes, empty-cell navigation and transactional rollback.
- Added scrolling 2–5-span input, PIN/FIX ends, g/q and editable γ factors. Shared sections provide EI and self-weight, added once to g. Per-span deflection comparison uses L/250 or L/300.
- Continuous edits invalidate results; results entry displays Calculating… and defers calculation to on.timer. Plots use a stored 20-interval-per-span cache including both support sides. Cursor movement queries the exact envelope once. No solve or envelope query occurs during painting.
- Added M/V envelopes, odd/even characteristic w curves, span/support tables and eight bc_* CAS exports; bc_wmax is in mm. The γ convention remains OPEN (EN 1990 A1 + NA). Single-span behavior and all eight bx_* exports are retained.
- P5B-R1 persistence accepts only a complete valid 0.5.0 document. Any invalid field or other version resets the entire document to defaults at page 0, with a notice until the first key action. No v0.4 migration or persisted input focus. Continuous restore waits for results entry before calculation.
- P5B-R1 preserves ContinuousPreset and Frame, including Frame.combine. Case E accepts either symmetric maximum position and verifies that the exported position equals the summary and attains the characteristic maximum.
- All 13 suites pass under Lua 5.1.5 and 5.4.7, including the exact local CI sequence, 394 Frame rows, 2042 golden cases and P5A.1 brute force over 300 models. Package: 28765 bytes, final USB packet 193 bytes. Owner calculator acceptance remains pending; see VALIDATION_P5B.md.

## 0.4.0
- Activated the single productive FEA route: section EI/self-weight → `BeamPreset.model` → `Frame.solve` → Frame recovery/extrema → preset summary → UI/CAS. Removed the legacy numerical solver and its build dependency.
- Retained the four existing single-span presets, selector transactions, input/catalog/manual EI, signed loads and arrows, M/V/w diagrams/cursor, analytical extrema, L/250 and L/300 comparisons, concrete cantilever `2.5L`, `AGREE LIMIT`, and all eight CAS values. Continuous beams and frames remain engine capabilities only.
- Preserved the v0.3.3 saved-document contract and failure/selector rollback behavior; self-weight remains separate and is added exactly once. Limit selection updates the comparison without solving again.
- Generated-bundle golden/adjudication regressions: 2,009 ordinary equivalents, two adjudicated, five RESOLVED legacy failures and 26 invalid inputs. Frozen mechanics, fixtures and all 394 original Frame oracles retained unchanged.
- All 11 suites pass under Lua 5.1.5 and Lua 5.4.7, including real UI-to-Frame instrumentation, cursor comparisons, persistence, rollback, native-CAS mock and target canvas checks. See `VALIDATION_P2B.md` for package details.
- BXBENCH measurements from the original CX CAS remain solver references, not UI timings. Final v0.4.0 hardware acceptance is pending owner testing of the delivered package.
- P1C.1: compatibility check scale floored by member end-force reference; fixes false rejection of loads near rigid supports. The end-force/load-based floor is an experimentally validated rounding tolerance, not a rigorous bound. The implied absolute compatibility tolerances are δw = 1e-14·F·L³/EI and δθ = 1e-14·F·L²/EI (about 45 times double-precision machine epsilon times the force reference); near rigid supports, recovery errors below these scales are no longer detected.

## 0.3.3
- Load arrows follow the sign of P and calculated total q, including self-weight; one filled head per arrow is retained.
- Moved loads below the measured diagram title, inset UDL arrows from supports, and kept P longer than q arrows. Catalogue EI now displays `(auto)` in the value column, separate from units.
- **Result change only for concrete cantilevers:** `Lref = 2.5·L` per DIN EN 1992-1-1/NA 7.4.1 changes `u250`, `u300` and `Lref/|w|`. Physical deflection, reactions, moments and the eight `bx_` variables are unchanged. Other supports still use L.
- Steel and MANUAL cantilevers retain `Lref = L` and display `CANTILEVER: AGREE LIMIT`; project / National Annex limits apply (EN 1993-1-1, 7.2).
- Added Lua 5.1 syntax and analytical/UI checks to CI, plus signed-load, layout, reference-length and CAS regressions.
- Package: **12,465 bytes**, official Luna commit **`a9924a9`**, rebuilt from source; identical output in two local packaging runs. TI-Nspire CX CAS hardware-tested 2026-11-18; the classic-zlib package transferred fine under a plain file name in the root folder.

## 0.3.2
- Added a visual 2×2 support-system selector with compact schematics and reference M silhouettes for a downward uniform load (`q>0`), independent of the current model.
- Confirm systems with Enter using transactional calculation and full rollback on failure. New documents start at the selector; Esc returns to it and Tab has no effect there.
- Esc clears an input error when a valid result exists; malformed numeric text retains the confirmed model's solution. Failed-calculation diagnostics remain available.
- Preserved legacy document pages, loads and sections; selector saves restore focus to the confirmed support without adding saved fields.
- Added reference-formula, drawing-sign, layout, no-solve repaint, Esc/CAS recovery and persistence checks.
- Hardware validation: TI-Nspire CX CAS OS 4.5.5.79 on 2026-11-18; selector / silhouettes, Esc / editing, inert Tab, invalid-number recovery / CAS export, selector save, and analytical FIX-PIN results verified.
- Hardware-tested package: **12,006 bytes**, official Luna **`a9924a9`**. Luna uses the system zlib: classic zlib and zlib-ng produced valid 11,938- and 12,006-byte packages from the same script; size is not a cross-machine build check. One v0.3.2 upload stalled N-Link at 91 % using `BeamCX_0.3.tns` in `Apps` with classic zlib; the successful upload used a plain name in the root folder with zlib-ng. The cause was not isolated. The classic-zlib v0.3.3 package later transferred fine with a plain name in the root folder. Recommended: plain names without extra dots (e.g. `BeamCX033.tns`) and the root folder; see README.

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
