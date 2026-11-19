# P6C-0-R1 — UI structural separation

**PC REFACTOR/PASS — HARDWARE PENDING.** 2026-11-19.

Source organization only; no P6C-R1 feature work. Accepted original-CX P6B
behavior is the comparison authority. This refactor has not been accepted
on the physical calculator.

## Baseline and dependency inventory (before production edits)

Baseline HEAD: `1d6d5025a9c99877b471253ecee8475848d32726`.
`git status --short`: empty. Exact generated bundle, original UI, frozen-source
hashes, TNS, suite logs and portal contact sheet retained separately in
`/tmp/beamcx-p6c0-baseline/`. Baseline Lua: 124,613 bytes; TNS: 34,693 bytes.
All 16 existing suites passed in Lua 5.1.5 and liblua 5.4.7 before editing.

| Responsibility | Existing functions and dependencies | Destination |
| --- | --- | --- |
| State/calculation | `recalc`, `dirty`, `dirty_portal`, `continuous_parameters`, `deflections_at`, `cache_cursor`, `cache_samples`, `cache_portal`, `rollback_selection`, `open_selected_system`, `show_results` | main |
| Shared drawing | `color`, `label`, `fitted`, `header`, `scroll_top`, `mini_support` | main, before views |
| Selector | `selector_message`, `selector_moment`, `draw_selector` | main |
| Single-span | `name_value`, `draw_edit`, `draw_results`, `support`, `load_arrow`, `diagram`; read `params`, `section`, `settings`, `names`, `units`, `presets`, `edit_index`, `typing`, `err`, `result`, `mode`, `cursor`, `q_sw`, `export_message`; call `fmt`, `sec_info`, shared drawing, `BeamPreset.at` | single view |
| Continuous | `draw_continuous_edit`, `draw_continuous_table`, `continuous_diagram`; read `continuous`, `params`, `settings`, `typing`, `err`, `stale`, `result`, `mode`, `samples`, `cursor_value`, `export_message`; update existing `edit_top`; call `continuous_rows`, `fmt`, `scroll_top`, `mini_support`, shared drawing | continuous view |
| Portal | `draw_portal_edit`, `portal_arrow`, `draw_portal_table`, `portal_diagram`; read `portal`, `portal_fields`, `portal_member`, `portal_s`, `portal_side`, `typing`, `err`, `stale`, `mode`, `samples`, `cursor_value`, `export_message`; update existing `edit_top`, `table_page`; call `fmt`, `scroll_top`, shared drawing | portal view |
| Sections | `section_rows`, `active_section_index`, `draw_section`; read `SectionDB`, `params`, `section`, `settings`, `typing`, `err`; update existing `sec_index`, `sec_top`; call `sec_info`, `fmt`, `scroll_top`, shared drawing | sections view |
| Editing/events | `apply_edit`, `apply_continuous`, `apply_portal`, `commit`, `step_selection`, `move_field`, cursor movement, `redraw`, notice dismissal, all `on.*` callbacks; section handlers call extracted row helpers | main |
| Persistence/CAS | `export_cas`, `valid_document`, `on.save`, `on.restore` | main |

The shared locals `result`, `samples`, `summary`, `cursor_value`, `stale`,
`calculating`, `typing`, `section`, `portal`, `continuous`, `params`, `settings`,
`mode`, `page` and `selection_before` remain owned by the main source.
`continuous_rows` and `portal_fields` remain beside state because central
editing handlers also depend on them. Portal table preparation stays in
`cache_portal` with the existing timer/cache lifetime.

Chosen scope: static textual inclusion in the original top-level Lua chunk,
after state, calculation and shared drawing declarations, before event
callbacks. View functions retain their original local names and bodies.
No forward declarations, module tables, copied state, field accessors or
per-paint context allocations are needed. The unmodified test snapshot stays
appended at the end of this same lexical chunk.

## Changed files and runtime scope

| File | Final responsibility |
| --- | --- |
| `src/beam_ui.lua` | Shared state, calculation and caches, selector, shared primitives, all TI callbacks, editing, transactions, CAS and documents |
| `src/beam_ui_single.lua` | Six unchanged functions: single-span inputs, M/V/w, compact results, support and load-arrow drawing |
| `src/beam_ui_continuous.lua` | Three unchanged functions: inputs, envelopes/characteristic w, span/support tables |
| `src/beam_ui_portal.lua` | Four unchanged functions: inputs, arrows, diagrams/deformation, scrolling results |
| `src/beam_ui_sections.lua` | Three unchanged functions: catalogue rows, active row and section/material view |
| `build.py` | Explicit single/continuous/portal/sections inclusion order at marked locations in the entry point |
| `CHANGELOG.md`, this report, `P6C0_UI_COMPARISON.png` | Development entry and validation evidence |
| `BeamCX.lua`, `BeamCX.tns`, `PORTAL_UI_CONTACT.png` | Rebuilt artifacts and regenerated existing portal sheet |

The main file is 912 lines (previously 1,354). The four view files contain
169, 111, 125 and 56 lines, respectively. This count describes the move;
the responsibility inventory, unchanged bodies and runtime comparisons
provide the architectural and behavioral evidence.

All **62 top-level function bodies** across the original UI were compared
byte-for-byte with the final five UI files: identical, with no duplicate
definitions. Sixteen functions moved. Only function declaration positions,
comments and blank lines changed. The numerical-module order remains
section DB → Frame → BeamPreset → ContinuousPreset → PortalPreset → UI.
The main source declares all shared upvalues before build-time inclusion;
every callback and the test snapshot follows the included views.

No runtime loader, module factory, context table, state copy, field accessor
or new global was introduced. View closures still refer directly to the
same main-chunk locals, including reassigned parameter tables after restore
and rollback. Functions that intentionally update scroll state retain that
behavior. Existing result/summary/sample identities and initial `recalc()`
position are preserved. The snapshot in `tests/load_ui.lua` is unchanged.
Central section editing continues to call the extracted row helpers.
Portal cached table preparation stays with calculation scheduling because
moving it would split the established cache lifetime.

## Frozen source hashes

All five hashes match the recorded pre-edit baseline:

```text
4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b  src/frame_core.lua
b205832ce2f7ba4371456f9898ca40611c8c589d87abdff92c50c55f424feede  src/beam_preset.lua
16186de935f91b57c5785be27880bc5d46f45de497148c01b340a8657bf1073d  src/continuous_preset.lua
921ebbf5d15bd27481e71c99440e857d87c448d4c83d2a30fcc818b6510312cf  src/portal_preset.lua
46b102cf8a56d0a0d621b23aaf8170e2825f6340aaedd87fefb3654f4c17c641  src/section_db.lua
```

Historical fixtures, existing numerical/UI tests, `tests/load_ui.lua`,
`tools/package.py` and USB packaging logic are unchanged. No numerical or
functional defect was changed as part of this task.

## Regression results

Baseline: **16/16** existing suites passed in both Lua 5.1.5 and
liblua 5.4.7 (`liblua5.4-0` package `5.4.7-1+b2`). The 5.4 CLI is not
installed; the repository's normal ctypes/liblua runner executes that VM.

After each of single-span, continuous, portal and section extraction:
rebuilt, passed `luac5.1 -p`, passed the relevant existing UI suite(s), and
passed the full exact P6B event/graphics replay. Separate extraction logs
remain under `/tmp/beamcx-p6c0-baseline/extract-*.log`.

Repetition already executed on **2026-11-19: PASS, 17/17** suites in each VM
(Lua 5.1.5 and liblua 5.4.7): all 16 existing suites plus the equivalence
suite subsequently retired by the closure addendum below. Preserved
394 Frame rows (265+129), 2,042 historical beam
cases, 300 independent continuous models (1,050 spans / 4,500 patterns),
136 P6A portal models and six classical witnesses. Existing CAS, document,
layout and numerical criteria were not relaxed. Five Python packaging and
USB guard checks also pass.

Commands run successfully during that validation (including the subsequently
retired comparison tools):

```bash
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
python3 tests/test_ui_equivalence.py
python3 tests/render_portal_ui.py
BX_TRACE_DIR=/tmp/beamcx-p6c0-after BX_GRAPHICS_DIR=/tmp/beamcx-p6c0-after/graphics \
  python3 tests/test_ui_equivalence.py
python3 tests/render_ui_equivalence.py /tmp/beamcx-p6c0-after/graphics P6C0_UI_COMPARISON.png
```

The capture directories were created before these evidence commands.
Suite logs were written to `/tmp/beamcx-p6c0-after/suites51.log` and
`suites54.log`. These paths and the comparison commands above document the
completed run; they are not requirements for future UI tests. After closure,
ordinary regression retains the 16 existing suites, with no retained P6B
bundle fixture or equivalence-tool dependency.

## Exact differential event and graphics comparison

In **each VM**, original P6B and extracted UI match at **2,263 observations**,
including **213,389 ordered graphics commands**. This is exact equality of
canonical structural content and round-trip numeric encodings, with no
tolerance. Both bundles run in the same VM with the same interactions and
font metrics; comparisons do not assume two Lua versions share formatting.

Coverage includes all six cards; all four single presets; valid/invalid
edits, backspace and cancel; materials, concrete dimensions, steel profiles,
self-weight and limits; continuous span count/lengths, ends, loads and
factors; portal PIN/FIX, all geometry/EI/load fields, five modes, members
1/2/3, both point-load shear limits and every table scroll; all namespaces;
save/restore; failed single/continuous/portal selection, confirmed-portal
calculation rollback, timer cancellation and strict malformed/old-version
rejection. The original snapshot supplies state without adaptation.

Each observation compares pre/post-paint state and documents, confirmed
parameters, result records, summaries, samples, cursor readings, cache
identity relationships, solver and recovery counts, ordered timer and
invalidate calls, CAS stores, error strings, global names/types, registered
callback names/types, and full graphics commands. Text, coordinates, colors,
font face/style/size, pen width/style and all primitive arguments are included.
Tables use sorted keys; function addresses and private solver closures are
excluded. Numerical records and cache contents are compared directly.
Paint performs zero solves. The initial single-span calculation is counted;
deferred continuous work asserts exactly n+1 Frame solves, portal exactly
one, with no synchronous solve when entering results.

At 318×212, 320×212 and 320×240, **21 selected views each** produce
**63 identical before/after command streams and rasters**. The side-by-side
sheet `P6C0_UI_COMPARISON.png` contains selector, single input/M/V/w/results,
manual/concrete/steel sections, continuous input/sections/M/V/w/results,
portal input/M/V/N/deformation/results. These are actual bundled `on.paint`
commands. Raster simulation uses the same DejaVu font/renderer on both sides;
exact command comparison is the acceptance evidence, not PNG appearance alone.

The regenerated existing ten-screen `PORTAL_UI_CONTACT.png` is also
byte-identical to its pre-edit copy:
`a0be649b0310f8b5bdb81b1e576e4d4f8f8d48a52c28f2b20b2d831be1128c3e`.

Final liblua 5.4 event traces share SHA-256
`dcce34bcd069c780a9e0630b1c7cf7317263b6377d35ac07dba6c841c5d91677`;
selected graphics JSONL streams share
`ed746ff04855326e0dd42c90b23005c068915691a5f21b3ee24cc62bc35ccc01`.
The first replay was captured before any production edit; later captures
add global/callback observations while still executing the retained original
bundle as the authority.

## Documents and CAS

`on.save()` retains its twelve top-level keys and types: string `format`,
tables `params`, `section`, `portal`, `continuous`, `settings`; numeric
`page`, `mode`, `cursor`, `portal_member`, `portal_s`; string `portal_side`.
Format is exactly `0.6.0`. Nested fields, full-precision values, saved mode,
cursor/member/side and restore behavior match structurally. No solutions,
cache fields, timers or migration were added. Both historical v0.5 witnesses
and malformed v0.6 documents reset exactly as before, including
`Invalid document or version: defaults restored`.

The ordered name/value stores match exactly for eight `bx_*`, eight `bc_*`
and fourteen `bp_*` exports. Values remain unrounded solver results; store
order, returned-error/exception handling and success/error messages match.
For example the default single-span baseline retains `bx_mmax=45`,
`bx_vabs=30`, `bx_wmax=16.875`, `bx_ei=10000`. Continuous and portal full
precision values and saved structures matched in the completed event captures
against the hash-checked original bundle. The comparison fixture and harness
were subsequently removed as recorded below.

## Closure addendum — 2026-11-19

At the owner's request, removed only these five temporary comparison files:

```text
tests/ui_equivalence.lua
tests/test_ui_equivalence.py
tests/render_ui_equivalence.py
tests/fixtures/p6b_bundle.lua.gz
tests/fixtures/p6b_ui_baseline.md
```

The preceding differential results and graphics sheet remain evidence of
the completed validation, not a retained additional test suite. The already
executed repetition on **2026-11-19 was PASS** in Lua 5.1.5 and liblua 5.4.7,
with all 17 then-present suites and all five packaging/USB checks passing.
This addendum does not claim a new suite run after deleting the harness.

Static comparison against P6B commit
`1d6d5025a9c99877b471253ecee8475848d32726` (`1d6d502`):

- Reconstructed both bundles in temporary directories using their respective
  `build.py` and sources; no productive source or workspace bundle was changed.
  Their SHA-256 values match the before/after hashes recorded above.
- The line multiset is identical apart from **10 added blank lines and six
  current comment lines**: five added comments and one replacing the original
  support-helper comment. Excluding blank/comment-only lines, the code-line
  multisets are identical.
- `luac5.1 -l -l` reports **142 locals in both main chunks**, with the same
  144 slots, 1,139 instructions, 190 constants and 128 child functions.
- `GETGLOBAL`/`SETGLOBAL` operand multisets, including occurrence counts, are
  identical. Upvalue-name multisets (728 references) and per-prototype upvalue
  count distributions are identical. No global or upvalue additions appear.

Closure changes only this report and the five deletions. `src/`, `build.py`,
the generated Lua/TNS artifacts, the existing 16 suites and their historical
fixtures remain unchanged. Physical-CX acceptance remains pending.

## Build, packaging and resource use

| Artifact | P6B before | P6C-0 after | Change |
| --- | ---: | ---: | ---: |
| Generated Lua | 124,613 bytes | 125,001 bytes | +388 (+0.31%) |
| TNS | 34,693 bytes | 34,896 bytes | +203 (+0.59%) |
| Final USB packet, `17 + size % 253` | 49 bytes | 252 bytes | guard passes |

`(17 + size % 253) % 64 != 0` remains true; no padding retry was required.
The small source increase is fragment comments/separators, with no new
application operations or per-paint context allocations. Generated files
remain ignored according to the existing `.gitignore`; both were rebuilt
and are present in the workspace.

| SHA-256 | Before | After |
| --- | --- | --- |
| Lua | `88b7b433044a75564ff92876cc4568e2c42eab40a23e916b94aa91a42368b55f` | `7c9ff32e9fc8b8e48435d2ef0e16c2e6153ef13c7647b8d7b4f1d019c9c68527` |
| TNS | `4c05456c4751b3245deacfb75665110685847aaa49b4999978c790172bfb0cd0` | `750194cb095e203f2c541ab998f46a19b3ce50ed7aec1a9ca8c451b30e2f2145` |

PC Lua 5.1 `os.clock()` medians over 41 runs per bundle, measured back to
back after regression finished (including parse/startup, timer including
cache generation):

| Operation | P6B | P6C-0 |
| --- | ---: | ---: |
| Parse/startup + initial single solve | 4.613 ms | 4.367 ms |
| Five-span continuous timer | 20.506 ms | 19.120 ms |
| Default portal timer | 1.645 ms | 1.503 ms |

The pre-edit capture under concurrent test load measured 6.479 / 28.784 /
2.516 ms; an earlier after-only run measured 4.244 / 18.346 / 1.405 ms.
This variability prevents attributing a speedup to reorganization. No PC
timing regression was observed. The temporary measurement script is
`/tmp/beamcx-p6c0-baseline/timing.lua`; it loads the actual bundle, restores
five spans `{4,4.5,5,5.5,6}`, enters deferred results, then restores the
default portal and times its timer callback. No optimization was added.

## Remaining risk and original-CX acceptance

PC evidence establishes equality for the recorded interactions and existing
regressions. Physical font rendering, memory headroom and responsiveness
still require the original TI-Nspire CX CAS. Hardware acceptance of P6B
does not establish acceptance of this newly packaged artifact.

Transfer the rebuilt plain-name `BeamCX.tns` and confirm:

1. All six selector cards and expected navigation/confirmation.
2. Single-span input, sections, M/V/w and results for the four presets.
3. Continuous input, sections, deferred results, tables and diagrams.
4. Portal PIN/FIX input, M/V/N, deformation and scrolling results.
5. Numeric editing, negative key, backspace, TAB, ENTER and ESC.
6. CAS exports in all three namespaces, including all fourteen `bp_*`.
7. Save/restore v0.6; reject an older/malformed document with default reset.
8. Cursor/member movement and diagram responsiveness, including the P jump.

**No hardware PASS is claimed.** P6C-R1 portal sections remain excluded and
unimplemented. No commit, push or release was made.
