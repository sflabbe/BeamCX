# P6B-R1 — BeamCX v0.6.0

**PC IMPLEMENTATION/PASS — HARDWARE PENDING.** 2026-11-18.

PORTAL is active in the generated application through
`UI → PortalPreset.solve → Frame.solve`. P6A remains the frozen numerical
authority. This delivery does not claim acceptance on a physical calculator.
No commit, push or release; no work on v0.7.

## Productive behavior

The 3×2 selector now contains PIN-PIN, FIX-FREE, FIX-FIX, FIX-PIN,
CONTINUOUS and PORTAL. All 24 arrow transitions are tested, with ENTER
confirmation and transactional rollback. The portal reference silhouette is
illustrative under q>0, independent of the live inputs. The five earlier
schematics and their reference-M numerical checks remain intact.

PORTAL has ten scrolling input fields: equal PIN/FIX bases; h/l; manual
EIc/EIb; q/P/a/H/w. Defaults match P6A. Physical validation delegates to
PortalPreset.model; invalid input retains the valid parameters, result and
cache, displaying the original error. Reducing l resets an inactive a to
l/2 only with P=0. The shared catalogue, sections and self-weight remain
exclusive to the earlier systems. TAB in PORTAL switches input/results.

Valid changes mark results stale and invalidate the plot cache without a
solve. Entering stale results displays `Calculating...` and uses the existing
TI timer. The productive callback makes **one PortalPreset.solve and one
Frame.solve**, then caches about 20 intervals per member, endpoints and both
limits at an interior P cut. It caches table rows and plot scales as well.
Paint, numeric member selection, cursor movement, mode changes, table
navigation and export never solve. Paint also makes **zero recovery queries**.
A changed cursor makes **one PortalPreset.at query**, not a frame sweep.
No-op edits preserve the cache. Initial candidate failure restores the
previous system and result references; later calculation failure restores
the last confirmed portal parameters, result and cache.

The five modes are M, V, N, absolute Deformed shape and Results. Keys 1/2/3
select left column/beam/right column. Local s starts at the base on both
columns and at the left eave on the beam. The cursor visits both P limits,
labelled left/right. UP/DOWN advances/recedes along s; in the table it scrolls
rows. LEFT/RIGHT changes mode, ENTER opens the table or explicitly exports,
TAB returns to input and ESC returns to the selector/cancels typing.

## Physical and presentation authority

Nodes and members retain P6A numbering: 1→2, 2→3, 4→3. Actual h/l proportions
are retained in the drawing; **both columns run bottom to top**. Positive q/P
arrows point down, positive H/w arrows point right; negative loads reverse
heads and zero loads omit them. PIN and FIX base glyphs are distinct.

M>0 tensions local −y: global RIGHT for members 1 and 3, DOWN for member 2.
All members share one M scale based on the preset extrema; the right column
is not sign-flipped. V keeps the Frame local convention and its ordinates
use local +y. The exact P cut is drawn as a vertical jump in beam V, without
a sloping segment across the jump. N is positive tension, with orange tension
and cyan compression outlines. M extrema and their positions come from
sol.members, not pixels. |V|max is recovered at exact endpoints and both P
limits, independently of the regular drawing samples.

The deformed shape uses both recovered local u and w: beam `(dx,dy)=(u,w)`;
both columns `(dx,dy)=(-w,u)`. Joint endpoint translations agree with the
Frame nodal solution; the sampled curves use its compatible Euler–Bernoulli
recovery and rigid-joint rotations. The original geometry remains visible,
and a displayed automatic magnification factor distinguishes the drawing
from true geometric scale.

The table's signed beam deflection and position come **unchanged** from
`sol.deflection.value/absolute/position`. They are relative to the displaced
end chord and are not replaced by Frame.deflection_extrema or inferred from
the absolute deformed picture. Eave drift is signed global horizontal
motion. The table shows reactions, N/Mmin/Mmax/|V|max for each member,
M-extrema positions, both local corner moments, signed drifts and w_rel in
mm, h/|drift| and l/|w_rel| ratios, and the deflection position. Undefined
zero-displacement ratios and PIN reaction moments display a dash.
`limits: OPEN (project / NA)` remains visible.

EA=1e6·EI/L² remains the P6A finite approximation. All loads are characteristic
and simultaneous, with no portal factors, envelopes or automatic self-weight.
This is linear elastic first-order analysis without P-Delta, second-order
stability or serviceability/code certification. The P6A conditioning-aware
test criterion and its limitations are unchanged.

## CAS and persistence

ENTER in the portal table writes exactly fourteen numeric values:
`bp_hl`, `bp_vl`, `bp_ml`, `bp_hr`, `bp_vr`, `bp_mr`, `bp_mmax`, `bp_mmin`,
`bp_nabs`, `bp_vabs`, `bp_dxl`, `bp_dxr`, `bp_wrel`, `bp_xwrel`.
Reactions and N/V are kN, moments kNm, drifts and signed w_rel mm, and the
beam-local deflection position m. PIN base moments export numeric zero.
H is right-positive, V up-positive, reaction M counterclockwise-positive,
N tension-positive; w_rel retains the P6A sign. Values are never taken from
display-rounded strings. Every value is validated before the first write.
Native var.store errors/throws stop export and never report partial success.
Only fourteen successes display `CAS: 14 variables stored`. There are no
automatic CAS writes. The eight bx_* and eight bc_* contracts remain intact.

Persistence accepts **only a complete structurally valid exact `0.6.0`
document**. It validates all three parameter sets and settings before
accepting any state. Active system, page/mode, portal member, local cursor
and side are retained at full precision. Matrices, solutions, recoveries,
samples, caches and timers are not serialized. Portal/continuous results
restore at input and wait for normal deferred results entry.

Both documents in unchanged `tests/fixtures/beam_v050_saved.lua` are now
**rejection witnesses**. They reset ALL state to defaults at the selector
and show exactly `Invalid document or version: defaults restored`. Malformed
v0.6 and other versions behave identically. There is no migration, fallback
parser or compatibility alias. Separate test-only current-format precision
witnesses exercise single-span and continuous round trips; portal precision
round trips and deferred results restore are checked in the new UI suite.

## Numerical UI witnesses

All cases execute the bundled UI restore/input → results entry → timer →
PortalPreset route, then compare every reaction, member/extrema, corner,
drift and deflection record with the P6A solution. All fourteen exported
values match the unrounded solution, including exact |V| cut extrema.
h=4 m, l=6 m, EIc=10000 and EIb=15000 kN·m²:

| Case | Loads | Left H/V/M [kN/kN/kNm] | Right H/V/M | Left/right drift [mm] | Signed w_rel [mm] @ s [m] |
| --- | --- | --- | --- | --- | --- |
| A, FIX | q=10 | 7.49994937534 / 30 / -9.99986500091 | -7.49994937534 / 30 / 9.99986500091 | 0.0000539996355 / -0.0000539996355 | -5.25002024986 @ 3 |
| B, PIN | w=10 | -29.0000148499 / -13.3333333333 / 0 | -10.99998515 / 13.3333333333 / 0 | 37.3335263108 / 37.333367911 | 2.40138618421 @ 4.45784327782 |
| C, PIN | H=10 | -5.00000674997 / -6.66666666663 / 0 | -4.99999324998 / 6.66666666663 / 0 | 16.0000928888 / 16.0000208889 | -0.769805758915 @ 1.26795324242 |
| D, PIN | q=8, P=17 at a=2.2, H=11, w=6 | -17.5235235932 / 19.4333333334 / 0 | -17.4764764067 / 45.5666666666 / 0 | 40.8424299252 / 40.842178264 | -7.12844043816 @ 2.27869825086 |
| D, FIX | same combined loads | -15.5392980264 / 29.4884913614 / 23.5513799326 | -19.4607019736 / 35.5115086386 / 36.7795682362 | 8.6658527179 / 8.66557248379 | -6.19746654525 @ 2.61153299435 |

Case A beam-side corner moments are -19.9999325005 kNm at both ends.
The classical 30 kN, |Mbase|≈10, |Mcorner|≈20, wind reactions≈-29/-11 and
nodal-H drift≈0.016 m remain witnesses, not substitutions for finite-EA
results. P6A's six analytical expressions retain 5e-5 approximation tolerance;
the independent finite-EA criteria, random seed and all 136 models are untouched.
The signed governing result may select either tied extremum as permitted by
P6A; UI and exports use the selected sol.deflection record consistently.

## Regression evidence

New `tests/test_portal_ui.py` executes `tests/portal_ui.lua` against the actual
generated bundle and TI-Lua events. It checks the ten input fields, validation
rollback, no-op cache retention, deferred execution, exact solve/query counts,
physical A/B/C/D witnesses, member-local cursor readings and jump sides,
M tension-side screen coordinates, V discontinuity geometry, PIN/FIX support
strokes, local/global deformation transformations and joint translations,
P6A relative deflection, table values and zero ratios, unrounded fourteen-value
CAS export, missing API/returned error/exception/invalid value handling,
strict full-document rejection, precision round trips, calculation-failure
rollback and all requested screen sizes.

`tests/portal_graphics.lua` records real on.paint commands and checks all
primitives and text against the viewport, plus pairwise text overlap. Layouts
cover **318×212, 320×212 and 320×240**, both base conditions, positive,
negative and zero q/P/H/w, every result mode and every input/table scroll row.
The existing selector suite now checks all six cells and 24 transitions;
its earlier five silhouettes keep their independent numerical assertions.
Only version/schema-dependent legacy UI tests are adapted; historical
numerical data and criteria are not changed.

**PASS: 16 suites in Lua 5.1.5 and liblua 5.4.7.** Also PASS: five Python USB
packaging checks. This retains 394 Frame numerical rows (265+129), all 2042
historical cases (2009 equivalent, two adjudicated, five RESOLVED, 26 invalid),
300 continuous brute-force models (1050 spans, 4500 patterns), independent
rational continuous references, all 136 P6A portal models and six classical
oracles, plus single-span/continuous UI, drawing, formatting, persistence
and bx_*/bc_* export regressions.

Commands executed:

```bash
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tests/test_portal_ui.py
python3 tests/render_portal_ui.py
python3 tools/package.py
# Exact CI test-loop form, also executed:
set -e
for test in tests/test_*.py; do
  echo "Running $test"
  python3 "$test"
done
git diff --check
```

These are local PC executions of the repository workflow checks, not a remote
GitHub run. Environment: x86_64 Linux, Intel Core i5-8300H, Python 3.13.5,
SymPy 1.13.3, Lua 5.1.5, liblua 5.4.7; test-only raster output uses existing
Pillow 11.1.0. No dependency is added to the calculator application.

## Contact sheet and package

[PORTAL_UI_CONTACT.png](PORTAL_UI_CONTACT.png) contains ten **actual application
command captures**: six-card selector, two portal input positions, M/V/N,
absolute deformed shape, base-reaction table, member-extrema table and
drift/chord-relative-deflection table. It uses combined case D FIX. The
recorder is shared with the layout tests; the Python renderer interprets
these commands rather than implementing a second UI. The PNG was visually
inspected. It is labelled **PC simulation**, with simulated font metrics;
it is not a TI-Nspire hardware screenshot.

Generated `BeamCX.lua`: **124613 bytes**. `BeamCX.tns`: **34693 bytes**,
packaged through the unchanged tools/package.py / Luna route, with no padding
needed. The guard computes:

```text
17 + (34693 % 253) = 49 bytes
49 % 64 = 49 != 0  → PASS
```

BeamCX.tns SHA-256:
`4c05456c4751b3245deacfb75665110685847aaa49b4999978c790172bfb0cd0`.

P6A PC calculation timings remain historical PC measurements: 1.143 ms in
Lua 5.1.5 and 0.743 ms in Lua 5.4.7. They are not P6B CX response times.
The new UI tests prove one solve per stale result and cached redraw/cursor
behavior. Hardware recalculation time and responsiveness remain for the owner.

## Changed and unchanged files

Changed production/build/documentation:

- build.py: bundle PortalPreset and generate version 0.6.0.
- src/beam_ui.lua: sixth system, portal lifecycle/input/results/CAS and strict persistence.
- README.md and CHANGELOG.md: v0.6 behavior, signs, precision and hardware status.
- VALIDATION_P6B.md and PORTAL_UI_CONTACT.png: qualification and visual evidence.
- Generated BeamCX.lua and BeamCX.tns: productive v0.6 application/package.

New test-only files: test_portal_ui.py, portal_ui.lua, portal_graphics.lua,
portal_contact.lua, render_portal_ui.py and current_documents.lua under tests/.
Adapted tests/load_ui.lua exposes test-only snapshots by appending code to
the bundle in the test harness. Adapted test_selector.py, test_v033.py and
ui_presentation.lua account for the sixth card and complete current-format
schema; the original v0.5 fixture is used only for rejection.

Frozen modules verified byte-for-byte by SHA-256:

```text
4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b  src/frame_core.lua
b205832ce2f7ba4371456f9898ca40611c8c589d87abdff92c50c55f424feede  src/beam_preset.lua
16186de935f91b57c5785be27880bc5d46f45de497148c01b340a8657bf1073d  src/continuous_preset.lua
921ebbf5d15bd27481e71c99440e857d87c448d4c83d2a30fcc818b6510312cf  src/portal_preset.lua
```

Historical numerical fixtures, the v0.5 saved fixture, P6A numerical tests and
Python reference, packaging algorithm, catalogue and benchmark are unchanged.
No production numerical test hooks were introduced.

## Owner hardware acceptance — still pending

On the original TI-Nspire CX CAS, using the normal transfer and document save
workflow:

1. Transfer BeamCX.tns under its plain name and open it. Check six selector
   cards, all arrow routes and the PORTAL reference silhouette.
2. Open PORTAL. Scroll all ten fields; confirm manual EI values, PIN/FIX
   switching, signed/zero load arrows and TAB input/results navigation.
3. Run case A with default geometry/EI. Check V≈30 kN each, base |M|≈10 kNm,
   corner |M|≈20 kNm, signed table values and the displayed OPEN limitation.
4. Run case B and check horizontal reactions≈-29/-11 kN. Run C and check
   drift≈16.0001 mm. Then enter combined case D with both PIN and FIX.
5. Review M/V/N and support glyphs, select members 1/2/3, move s from each
   origin, inspect both P shear sides and verify local signs and active cursor.
6. Review the magnified absolute deformation and joint continuity; separately
   check beam chord-relative w_rel and position against the table above.
7. From the table export and read all fourteen bp_* values in a Calculator
   page in the same problem. Check PIN moments are zero and no export occurs
   merely on recalculation; confirm bx_*/bc_* behavior remains intact.
8. Save and reopen a v0.6 portal with fractional inputs/member/cursor; confirm
   full precision and input-first deferred recalculation. Also exercise current
   single-span/continuous documents. Open an original v0.5 document and verify
   the exact warning and complete defaults reset, with no retained old state.
9. Check actual LCD/font readability, scrolling and no overlap, calculation
   wait feedback/time, smooth cursor movement and repeated redraws. Confirm
   ESC/timer cancellation and return between PORTAL and the earlier systems.

Only the owner can mark these physical checks accepted. Final status:
**PC IMPLEMENTATION/PASS — HARDWARE PENDING**. STOP; no commit, push or release.
