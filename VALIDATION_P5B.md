# BeamCX v0.5.0 — P5B / P5B-R1

2026-11-18. Continuous-beam UI active. Local validation passed; calculator acceptance belongs to the owner. This report records the original P5B-R1 delivery. The current English UI, display formatting and package are described in [UI polish R2](VALIDATION_P5B_UI_POLISH_R2.md).

## Delivered behavior

- Five systems in a 3×2 selector, with navigation skipping the empty cell. The continuous card has a three-span scheme and normalized reference M curve. Failed deferred calculation rolls back the selection. Card names fit the tested 318×212, 320×212 and 320×240 canvases.
- Scrolling input for 2–5 spans, lengths, PIN/FIX ends, g/q and factors. The shared section page supplies EI and self-weight. Self-weight is added once to g. Each span uses its own length for L/250 or L/300 comparison.
- Edits discard the result/cache without solving. Results entry invalidates the window, displays a calculation message and starts a 0.05 s timer. `on.timer` stops it and performs exactly n+1 `Frame.solve` calls.
- Twenty sampling intervals per span: 21n envelope queries, including both sides of internal supports, plus one to initialize the cursor. The cache is constructed once per calculation. Continuous painting performs no solve, envelope query or `Frame.at` recovery. Returning to results without editing retains the same cache object.
- Mmax/Mmin with positive M below the axis, Vmax/Vmin with support jumps, odd/even characteristic deflections and span/support tables. Cursor movement makes one exact envelope query and includes every support; both shear sides are available from the cache.
- Eight explicit `bc_*` exports, with `bc_wmax` in mm. Single-span calculation remains immediate and preserves its eight `bx_*` variables and golden witnesses. The factor convention is **γ: OPEN (EN 1990 A1 + NA)**.

## P5B-R1 persistence

`on.save` emits format `0.5.0`. `on.restore` validates all fields before accepting the complete document. Any invalid/missing field or other version discards the entire document: inputs, section, settings, continuous parameters, mode, cursor and page return to defaults at the selector.

The invalid-document notice remains through repaint/save and clears on the first key action. Tests cover invalid and missing fields individually, L=0, and the real v0.4 save shape without `format` or `continuous`. There is no migration or mixing of saved fields with defaults. Input focus is reset and is not persisted. Restoring continuous results opens input without calculating until results entry.

The rejected-calculation export check uses an invalid **edit**, independently of restore. `quick_check.lua` explicitly navigates to the profile after restoring.

## Case E

Real UI events enter 3×6 m, PIN–PIN, g=10, q=5, EI=10000, default factors and self-weight OFF. Span/support tables and summary match `ContinuousPreset.solve` for identical inputs.

| Variable | Verified value |
| --- | ---: |
| `bc_mmax` | 66.0005357143 kNm |
| `bc_mmin` | −80.1 kNm |
| `bc_vabs` | 76.35 kN |
| `bc_rmax` | 143.1 kN |
| `bc_wmax` | 15.3264571214 mm |
| `bc_xwmax` | 2.75420947417 or 15.24579052583 m |
| `bc_ei` | 10000 kN·m² |
| `bc_n` | 3 |

P5B-R1 accepts either symmetric maximum position. `bc_xwmax` must equal `summary.deflection_position` exactly. Recovery of both characteristic combinations verifies that this position reaches the maximum within 1e-9. The asymmetric 4/5/8 m case selects span 3. No numerical tie rule was introduced.

## Original validation

The exact local CI sequence passed, using liblua **5.4.7**:

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

The original 13 suites also passed with **Lua 5.1.5**. Additional commands were:

```bash
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
luac5.1 -p BeamCX.lua
```

Both runtimes preserved **394 Frame numeric rows** and **2042 golden cases**: 2009 ordinary equivalents, two adjudicated, five RESOLVED and 26 invalid. P0 witnesses and all eight `bx_*` values passed; golden fixtures were unchanged.

P5A.1 brute force covered **300 models, 1050 spans and 4500 patterns**. Maximum normalized errors: M 2.99e-15, V 4.84e-16, R 2.19e-16, w 1.81e-15, positions/patterns by achieved response 4.67e-15, summary 2.59e-15. The positive support-B regression gave +28.081141172746, pattern `3`, γG=1.00.

Continuous UI checks covered case E, deferred calculation, single cache construction, curve signs, shear jumps, exact cursor, sections/self-weight, limits, export, rollback and timer cancellation. All screens were painted for 2–5 spans at 318×212, 320×212 and 320×240. Five packager tests and `git diff --check` passed.

## Original scope audit

The P5B-R1 delivery left `frame_core.lua` (including `Frame.combine`), `continuous_preset.lua`, `beam_preset.lua` and `section_db.lua` unchanged. Test snapshots/instrumentation live only in the harness, with no production test hooks.

UI functions have callers in drawing, events or persistence. `valid_document` is called by `on.restore`. The productive continuous route is input/sections → parameters → `on.timer` → `ContinuousPreset.solve` → summary/tables/CAS. The preset uses `Frame.solve` and `Frame.combine`; the deflection cache also combines existing bases. No P5B component is left without a productive caller.

## Original package — historical

The original `tools/package.py` output required no padding:

| Artifact | Size | Final USB packet |
| --- | ---: | ---: |
| `BeamCX.lua` | 100080 bytes | — |
| `BeamCX.tns` | 28765 bytes | 193 bytes |

Original TNS SHA-256: `ab4a45233593238eff98c8842795b85a3e6c66d91b0c391b5a23d1bb52ba06d0`.
Original Lua SHA-256: `bb3b9a874fa426e0ef3a7075b11c63d3e796d483dd11a619c94e761688e906d4`.

These historical hashes do not describe the R2 package.

## Pending owner acceptance on the CX

- [ ] Case E, tables and eight exported variables.
- [ ] Five-span calculation/sampling time, with the calculation message visible first.
- [ ] Responsive cursor and both shear sides at supports.
- [ ] `bc_*` export in Calculator within the same problem.
- [ ] Save/restore in both modes, deferred calculation after continuous restore and the invalid-document notice.

No physical-device validation of the delivered v0.5.0 packages is claimed. No commit or push.
