# BeamCX v0.4.0 — P2B validation

2026-11-18. **Implementation complete / PASS. Physical CX acceptance pending.**

The generated application actively uses `UI → SectionDB → BeamPreset.model → Frame.solve → Frame recovery/extrema → BeamPreset.summary → diagrams/results/CAS`. The four selectable systems remain PIN-PIN, FIX-FREE, FIX-FIX and FIX-PIN. No additional systems, numerical algorithms or fallback engine were added. No commit, push or release publication was performed.

## Build and package

Commands executed successfully:

```bash
python3 build.py
luac5.1 -p BeamCX.lua
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
~/Luna/luna BeamCX.lua BeamCX.tns
git diff --check
```

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `BeamCX.lua` | 67,394 bytes | `52ed6f86e0808117f901ff781cb79fc5d8d5addb25fec705b787e3fc65ee3f45` |
| `BeamCX.tns` | 21,017 bytes | `96c18ad758bdf342485502c301a55482d6d545af5198f02234b9d336c907d983` |

The installed official Luna executable was used from the clean checkout at **a9924a9a968954eba9adcc161a58ac607f97ce8c**. Packaging succeeded. The output starts with the TI document header `*TIMLP0500`.

The bundle concatenates `section_db.lua`, `frame_core.lua`, `beam_preset.lua`, `beam_ui.lua` in that order. It contains Frame, BeamPreset, SectionDB and TI event handlers without a `require()` loader or legacy solver.

## Runtime and suite results

**11/11 suites pass on Lua 5.1.5 and 11/11 on Lua 5.4.7.** Lua 5.1.5 used `/usr/bin/lua5.1`; Lua 5.4.7 used the actual `liblua5.4.so.0` runtime (package 5.4.7-1+b2, embedded version string verified). The CLI runner executes the same Lua chunks as the ctypes harnesses, retaining their Python fixture and bundle checks.

Passing suites in both runtimes:

- `test_arrows.py`
- `test_beam_preset.py`
- `test_catalog.py`
- `test_dc_reference.py`
- `test_frame_core.py`
- `test_plot_sign.py`
- `test_port.py`
- `test_productive_route.py`
- `test_quick_check.py`
- `test_selector.py`
- `test_v033.py`

`test_productive_route.py` instruments the generated application's `Frame.solve`. Actual selector Enter, keyboard input, material changes, self-weight toggles and document restore reach the instrumented engine. Each valid recalculation invokes it once. Repaint, cursor movement and L/250–L/300 selection do not invoke it. This evidence comes from real UI event handlers, not a test-only call to Frame.

The UI tests cover all four systems, M/V/w display and cursor text against `BeamPreset.at`, zero axial response and prescribed support DOFs, changing section EI and deflection, self-weight ON/OFF without accumulation, changes to L and P including no loads, all eight native-CAS mock stores and error handling, v0.3.3-style persistence, complete candidate-system rollback, signed arrows and moment plot orientation, concrete `2.5L`, `AGREE LIMIT`, and rendering/navigation at 318×212 and 320×240 (also existing 320×212 checks).

The failed selector test injects failure at Frame after section data changes EI and available weight. It verifies restoration of the exact previous result/summary objects, support, EI, old error, CAS message, weight, self-weight setting and page. Failed ordinary recalculation still invalidates results and blocks export as before.

## Numerical equivalence

The established comparison suite now loads **the generated BeamCX.lua application**, then runs the existing frozen fixtures and unchanged P2A comparison assertions:

| Classification | Cases | Result |
| --- | ---: | --- |
| Ordinary equivalent | 2,009 | PASS |
| Independently adjudicated | 2 | PASS |
| RESOLVED legacy failures | 5 | PASS |
| Invalid inputs | 26 | Rejected correctly |
| Total | 2,042 | PASS in both runtimes |

All four P0 structural witnesses and all eight CAS quantities pass through the generated bundle. P0 selector activation and actual native-CAS mock exports are also checked through UI handlers. All five RESOLVED cases additionally succeed through actual UI restore, results display and export: `random_1097`, `near_1_1e-07`, `near_1_5.9999999`, `near_2_5.9999999`, `near_4_5.9999999`.

P2A rules are retained: normalized case scales with the established near-zero floor, tolerance 1e-9, physical extrema checks for tied positions, deflection-implied ratio comparisons, and explicit zero/nil states. No bitwise legacy equality is required. The largest normalized response difference is **9.1416081774202493e-10**; the deflection difference is **7.4583313832364138e-10**. The recorded maximum legacy deflection-coordinate difference is **1.9612957184259963e-9 × L**, with physical maximum-value checks retained. The dedicated tiny-response oracle also passes unchanged.

The original **394 Frame numeric oracles**, retained P1C.1 regressions and **10 frozen dc Euler reference cases** pass. Byte comparisons against repository HEAD confirm no changes to `frame_core.lua`, `beam_preset.lua`, `section_db.lua`, the four specified fixture files, or the original Frame/dc test suites. `on.save` and `on.restore` implementations are unchanged; no persistence fields or format were introduced.

The legacy `src/beam_core.lua`, its build dependency, live-output regeneration and live-solver check were removed. Independent analytical tests, golden input provenance, numerical oracles and fixtures remain. UI result consumers use the preset result structures directly; no compatibility solver or UI mechanics were introduced.

## Hardware status

Existing BXBENCH measurements on the original TI-Nspire CX CAS remain the reference:

| Model | Measured solve time |
| --- | ---: |
| Single-span beam | 76.67 ms |
| Continuous beam, five spans | 470 ms |
| Gable frame | 276.67 ms |
| 20 nodes | 2726.67 ms |
| 40 nodes | 8830 ms |
| 60 nodes | 20670 ms |

These measure the general solver, not guaranteed UI timings. The existing 60-node numerical guard is unchanged. No benchmark redesign, speculative thresholds, confirmation screens or solver optimization were added.

**Owner acceptance remains pending:** transfer the delivered `BeamCX.tns` to the original CX CAS and verify the four systems, diagrams/cursor, section changes and all eight CAS exports. Desktop tests and successful Luna packaging do not establish physical validation.
