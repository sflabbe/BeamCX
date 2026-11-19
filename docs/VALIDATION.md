# Technical validation

This document consolidates the model assumptions, numerical witnesses, acceptance criteria and reproducible tests distributed with BeamCX v0.6.1. Earlier validation reports remain in Git history; the essential evidence is retained here so a source archive is self-contained.

## Frame engine

The shared engine solves static, prismatic, linear Euler–Bernoulli plane-frame elements in m, kN and kNm. Global x is rightward, y upward and rotation counterclockwise. Each node has axial/vertical translations and rotation. Local x follows member i→j; local y is its positive perpendicular. N is tension-positive, M tensions local −y, and V satisfies dM/ds=V. End-force conversion is M(0)=−Mi and M(L)=+Mj.

The application presets expose a subset of the engine's capabilities. General-engine tests also cover inclined members, member-end releases, springs, prescribed displacements, point moments, segmented distributed loads and thermal curvature. Their presence in the engine does not expose those features in the calculator UI. Model size is limited to **20 nodes**.

The **394 numeric oracle rows** comprise **265 retained rows plus 129 additional rows**. Tests check stiffness/recovery, reactions, nodal displacement, extrema, equilibrium, compatibility, signs, endpoint loads, mechanisms and high-precision regression cases. [`frame_core_hp_regressions.json`](../tests/fixtures/frame_core_hp_regressions.json) retains independent high-precision witnesses. A separate **10-case** [`dc_reference.json`](../tests/fixtures/dc_reference.json) compares Euler–Bernoulli reactions/displacements against the independent `dinamica-computacional` reference, converting N to kN. Only horizontal members carry its uniform loads; it is not an arbitrary-inclination load oracle.

| Criterion | Value / interpretation |
| --- | --- |
| Relative pivot threshold | `PIVOT_TOL = 1e-12`, relative to the original row maximum after scaled pivoting |
| Engine equilibrium/residual/compatibility check | `CHECK_TOL = 1e-8` |
| Frame oracle comparisons | Relative `1e-9`, with the test's absolute `1e-9` rule for expected zero |
| Independent Euler reference | Relative `1e-6` for reaction/displacement sets; engine checks remain `1e-8` |

Compatibility recovery uses scales `max(end-displacement magnitudes, 1e-6·F·L³/EI)` and `max(end-rotation magnitudes, 1e-6·F·L²/EI)`. F is the larger of the member end-force reference and the summed load reference; end moments are divided by L. The load reference includes distributed and concentrated loads, moments/L and thermal curvature contribution. This prevents almost-zero displacements near rigid supports from setting the entire error scale.

With `CHECK_TOL`, the implied absolute floors are **δw=1e-14·F·L³/EI** and **δθ=1e-14·F·L²/EI**. This is an experimentally checked rounding allowance, not a rigorous forward-error bound: discrepancies below these scales can escape the compatibility check. Dedicated tiny-response and high-precision tests supplement global normalization. Mechanism detection and finite-value checks remain separate.

The ten independent external-project Euler oracles compare normalized reactions and nodal displacements at **1e-6**, while the engine diagnostics must remain within **1e-8**. Their generator explicitly selects Euler–Bernoulli behavior and converts N to kN; its uniform loads are on horizontal members. This comparison does not validate a different shear-flexible formulation.

Reproduce from the repository root:

```bash
python3 tests/test_frame_core.py
python3 tests/test_dc_reference.py
```

## Single-span beams

The four presets accept uniform q and one point P at a on a prismatic span, with downward-positive applied loads. Presets convert input signs at the Frame boundary. Recovery uses physical local displacement; the CAS maximum deflection is absolute in mm. Extrema use segment boundaries and stationary candidates, not display sampling.

The historical corpus has **2,042 cases**:

| Classification | Count | Authority |
| --- | ---: | --- |
| Ordinary equivalents | 2,009 | [`beam_v033_golden.json`](../tests/fixtures/beam_v033_golden.json) |
| Independently adjudicated | 2 | [`beam_v033_adjudicated.json`](../tests/fixtures/beam_v033_adjudicated.json), mpmath at 60 digits |
| Resolved legacy failures | 5 | Same retained inputs, successful present-engine solutions |
| Invalid inputs | 26 | Correct rejection |

The independent adjudication distinguishes old short-subelement rounding from the retained Frame response; the original golden is not rewritten. The resolved inputs include near-support loads. For F=|q|L+|P|, references are Vref=F, Mref=FL and wref=FL³/EI. Each comparison scale is the maximum case-response magnitude with a **1e-6** reference floor; acceptance is **1e-9** normalized error. A **1e-300** divisor floor prevents division by zero. These are global equivalence scales, not precision guarantees for tiny responses.

Tied extremum positions are accepted only when the reported coordinate attains the physical extreme. Ratio/utilization comparisons use deflection-implied scales; undefined zero-displacement ratios and prescribed nodal zeros are checked explicitly. A dedicated near-support FIX-PIN test uses L=6 m, P=12 kN at a=1e-7 m, q=0 and EI=10000 kNm², with its own nonzero response oracle. Historical maxima were **9.1416081774202493e-10** normalized response error and **1.9612957184259963e-9·L** coordinate difference; tied-coordinate checks still verify the achieved response.

Representative default PIN-PIN witness, L=6 m, q=10 kN/m, P=0, EI=10000 kNm²:

| Quantity | Expected |
| --- | ---: |
| M maximum | 45 kNm |
| Absolute V / each vertical reaction | 30 kN |
| Maximum absolute deflection | 16.875 mm |
| Position | 3 m |

Concrete cantilever comparisons use **Lref=2.5L**; other materials use L. This changes comparison ratios/utilizations, not physical displacement or the eight `bx_*` exports. L/250 and L/300 remain project comparisons rather than universal compliance criteria.

Reproduce:

```bash
python3 build.py
python3 tests/test_beam_preset.py
lua5.1 tests/quick_check.lua "$PWD"
python3 tests/test_v033.py
```

## Continuous beams

Assumptions: **2–5 spans**, one prismatic EI, full-span permanent g and variable q, PIN/FIX outer supports and vertical intermediate supports with continuous rotations. There are no internal rotational releases, cantilevers or point loads in this preset. Enabled self-weight is added once to g. Deflection comparisons use each individual span length.

Exactly **n+1 Frame solutions** form the permanent-load basis G and one variable-load basis Qi per span. Linear response envelopes select favorable/unfavorable contributions and both global permanent factors. Moment envelopes split each quadratic basis at its real roots; within each interval, the active combination is fixed and extrema occur at interval endpoints or the quadratic vertex. Moment envelopes are exact by pieces and do not use odd/even sampling.

Characteristic deflection uses unit factors and just **two odd/even combinations**. The rule is **verified against the retained exhaustive campaign, not proved for every beam configuration**. It must not be generalized into a moment-envelope rule. The factor convention is **OPEN (EN 1990 A1 + NA)**; defaults γG,sup=1.35, γG,inf=1 and γQ=1.5 do not establish code compliance.

`Frame.combine` does not solve again or modify operands. It requires identical geometry, connectivity, EI/EA, supports/prescribed displacements, springs, releases and recovery cuts. Summed maxima are not a valid substitute for combining the response before finding its extrema.

| Regression | Coverage / criterion |
| --- | --- |
| Independent rational SymPy reference | Reactions, polynomials, extrema and 101 positions per span |
| Brute-force campaign | 300 deterministic models, 75 per span count, 1,050 spans, 4,500 patterns, 13,500 exhaustive combinations |
| Generation | Seed 20261118; spans 2–10 m, g/q 0–30 kN/m, EI 5000–35000 kNm², all PIN/FIX ends |
| Comparison | `1e-9` normalized; positions and reported patterns checked by achieved response |
| Direct combination witnesses | `1e-12` |
| Recorded maximum normalized errors | M 2.99e-15, V 4.84e-16, R 2.19e-16, w 1.81e-15; response at reported position/pattern 4.67e-15 |

Representative default, PIN–PIN, three spans of 6 m, g=10, q=5 kN/m and EI=10000 kNm², self-weight OFF:

| Export | Expected |
| --- | ---: |
| bc_mmax / bc_mmin | 66.0005357143 / −80.1 kNm |
| bc_vabs / bc_rmax | 76.35 / 143.1 kN |
| bc_wmax | 15.3264571214 mm |
| bc_xwmax | 2.75420947417 or 15.24579052583 m |

Either symmetric coordinate is valid if it equals the returned summary position and attains the maximum. Other retained witnesses include upward deflection **4.20398173154e-4 m** at local **3.01724728039 m**, and positive support moment **28.081141172746 kNm** with variable-load pattern `3` and γG=1. These prevent discarding uplift or positive support moments.

Reproduce:

```bash
python3 tests/test_continuous_preset.py
python3 tests/test_continuous_ui.py
```

## Rectangular portals

The preset is one rectangular bay with equal PIN or FIX bases, independent column/beam EI, beam q and P at a, left-eave horizontal H and left-column horizontal w. Columns share a section and run base→eave. Loads are characteristic and simultaneous; there are no portal factors or envelopes. Positive M tensions global RIGHT in both columns and DOWN in the beam; N is tension-positive. Beam deflection is measured relative to the displaced end chord, separately from the absolute deformed drawing.

**EA=1e6·EI/L²** approximates negligible axial deformation. It is neither physical E·A nor a universal error guarantee. Classical infinite-axial-stiffness approximation error is distinct from binary64 error relative to the same finite-EA model. The reference uses independent **12-DOF** assembly and **50-digit Decimal** elimination, with rational SymPy conditioning diagnostics.

The **136 models** retain **50 random geometries × PIN/FIX**, the deterministic seed **20261118**, signed and combined loads, endpoint/near-endpoint loads, zeros and invalid inputs. There are **16,588 recovery queries**, member extrema, nodal displacements, independent global equilibrium, symmetry, reversal and superposition checks. Each valid portal solve invokes Frame once. Asymmetric chord witnesses reject finding relative-deflection extrema solely from absolute-displacement stationary points.

Let F=|q·l|+|P|+|H|+|w·h| and Lr=max(h,l), using F=1 for a zero-load comparison. Force and moment scales are F and F·Lr. Drift scale is the larger reference drift with floor **1e-6·F·Lr³/min(EIc,EIb)**; relative-beam-deflection scale uses its reference maximum with floor **1e-6·F·l³/EIb**. Local displacement uses the larger displacement scale and rotation uses drift_scale/Lr.

- Forces, moments and equilibrium retain **1e-9** normalized tolerance.
- The **36 nonrandom** models retain **1e-9** displacement tolerance.
- Random-model displacement tolerance is `max(1e-9, 10·κ∞(Kfree)·epsilon)`, with `epsilon=2.220446049250313e-16` and qualification ceiling **1e-6**.
- Of the random models, **36** retain the base tolerance; **64** use the conditioning term. Conditioning depends on units/scaling. Diagonally scaled conditioning is diagnostic only; neither κ·epsilon nor the multiplier is a rigorous forward-error bound.

The important conditioning witness is retained explicitly:

| Quantity, random geometry 44 / PIN | Recorded value |
| --- | ---: |
| h / l | 7.992534030399157 / 7.2414618540177935 m |
| EIc / EIb | 1287.6981033157158 / 70290.77027682829 kNm² |
| q / P / a / H / w | −16.925034043679595 / 33.30253354749232 / 4.149634493859181 / −23.25986592984502 / 2.630958639145323, in preset units |
| κ∞ of unscaled Kfree | 58620880.068742506 |
| Applied displacement tolerance | 1.30164501552e-7 |
| Normalized drift error | 2.02057181124e-9 |
| Absolute drift discrepancy | 1.36625832869e-9 m |
| Independent backward residual | 6.07550967767e-17 |

The campaign's largest recorded backward residual was **2.28459369477e-16**. It uses independent Kfree/Ffree in `||Kfree·u−Ffree||∞ / (||Kfree||∞·||u||∞+||Ffree||∞)` and does not replace response/equilibrium checks. Extreme drifts in random numerical stress cases need not satisfy engineering small-displacement assumptions.

### Classical witnesses and section routes

For h=4 m, l=6 m, EIc=10000 and EIb=15000 kNm², k=(EIb/l)/(EIc/h)=1:

| Case | Classical expected magnitude |
| --- | --- |
| PIN, q=10 kN/m | Horizontal reaction 4.5 kN |
| FIX, q=10 kN/m | Base M=10, beam corner M=−20, center M=25 kNm; beam N≈−7.5 kN |
| FIX, central P=20 kN | Base moment 5 kNm |
| FIX, H=10 kN | Base moment 80/7 kNm |
| PIN, w=10 kN/m | Horizontal reactions of magnitudes 29 / 11 kN |
| PIN, H=10 kN | Eave drift 0.016 m |

The six classical witnesses use **5e-5** relative tolerance against the negligible-axial-deformation expressions, and **1e-9** against the independent finite-EA model. The recorded maximum classical discrepancy is **1.34999088761e-5**. The formulas are supplied comparison witnesses; the bibliographic edition/form/page for their Kleinlogel attribution has not been established.

The section-route witness additionally uses FIX, h=4 m, l=6 m, Columns HEA 200 S235, Beam IPE 300 S235, q_user=10 kN/m and self-weight ON. With N1=k+2:

| Quantity | Classical / supplied reference | Finite-EA UI |
| --- | ---: | ---: |
| EIc / EIb | 7753.2 / 17547.6 kNm² | Same catalogue properties |
| q_sw / q_total | 0.413982 / 10.413982 kN/m | Same effective inputs |
| k | 1.50884795955 | Same stiffness ratio |
| Beam corner M | −17.8075233582 kNm | −17.8074719737 kNm |
| Absolute base M | 8.90376167909 kNm | 8.90367623920 kNm |
| Absolute horizontal reaction | 6.67782125931 kN | 6.67778705323 kN |
| Beam center M | 29.0553956418 kNm | 29.0554470263 kNm |

This classical section witness uses relative **1e-4** tolerance; the independent finite-EA comparison keeps its conditioning criterion. Steel/steel, concrete/steel and MANUAL/concrete routes verify that effective EI equals `SectionDB.compute` exactly and that UI/direct-preset results coincide for identical inputs. Repeated calculation does not accumulate weight; columns cannot enable it and MANUAL disables unavailable weight. No material properties are inferred from the diagram.

Reproduce:

```bash
python3 tests/test_portal_preset.py
python3 tests/test_portal_ui.py
```

## Application contracts and graphics

The **16 existing suites** pass in **Lua 5.1.5 and liblua 5.4.7**. Tests exercise the bundled application: selector transactions, invalid-edit and calculation rollback, numeric editing, section groups, deferred timing/cancellation, exact solver/query counts and cached drawing. Single-span calculation remains immediate; continuous/portal painting does not solve.

Persistence accepts exact **0.6.1** only, atomically validating all groups and physical inputs. Saved EI caches are replaced with group-derived properties before model validation. Page 3 and active portal group round-trip; earlier formats and malformed documents restore defaults with the existing notice. [`current_documents.lua`](../tests/current_documents.lua) supplies precision witnesses; [`beam_v050_saved.lua`](../tests/fixtures/beam_v050_saved.lua) remains a rejection fixture.

The **8 bx_*, 8 bc_* and 14 bp_*** exports are checked for names, units, full precision, order, validation before writes and returned/raised CAS errors. Native stores are replaced with test doubles on the PC; those tests do not prove device CAS operation. Formatting is presentation-only: **two decimals**, scientific notation below **0.005** or from **10⁷**, and normalized negative zero.

Layout/command tests cover **318×212, 320×212 and 320×240**, scrolling rows, signed/zero loads, all result modes, material mixes and cursor sides. The portal selector's orange moment ordinates close onto the frame; regression rejects disconnected endpoints. Documentation images use those real drawing commands at **2×**, with keyboard-event scenes and an explicitly simulated CAS API. Reproducibility is required only in the same controlled graphics environment.

The presentation separation retained **62 identical function bodies**, moving **16** into static views. Its recorded differential campaign compared **2,263 observations**, **213,389 ordered graphics commands** and **63** selected screens across the same viewport sizes. Result/cache identities, scheduling, CAS and documents matched the original application. The temporary full-bundle comparison harness was subsequently removed; these historical results supplement the retained ordinary UI suites rather than requiring an extra fixture or a Git checkout.

Reproduce:

```bash
python3 build.py
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/render_portal_ui.py --docs
```

## Hardware observations

Recorded test platform: original TI-Nspire CX CAS, OS **4.5.5.79**. Device checks below are historical observations, separate from desktop qualification. Physical acceptance of v0.6.1 has not been recorded; no device photos are supplied with this documentation.

| Date | Build / platform record | Checked on the calculator |
| --- | --- | --- |
| 2026-11-18 | v0.3, OS 4.5.5.79 | S235 / IPE 300 with self-weight, results, L/250 comparison and CAS; bx_mmax=46.8629 |
| 2026-11-18 | v0.3.2, same recorded platform | Selector, arrows, ESC, typing cancel, invalid-number recovery, CAS and selector save; FIX-PIN RA=37.5, RB=22.5 kN and M(3)=22.5 kNm |
| 2026-11-18 | v0.3.3, same recorded platform | Signed q/P arrows, title/support clearance; C25/30 cantilever with weight: absolute w=31.446 mm and Lref/absolute w=477.01; document transfer |
| Not separately recorded | v0.4, v0.5 and v0.6.0 | Acceptance was reported; a separate dated, OS-specific checklist is not retained here |

Historical BXBENCH general-solver measurements:

| Model | Solve time |
| --- | ---: |
| Single-span beam | 76.67 ms |
| Continuous beam, five spans | 470 ms |
| Gable frame | 276.67 ms |
| 20 nodes | 2726.67 ms |
| 40 nodes | 8830 ms |
| 60 nodes | 20670 ms |

The oversized rows are historical measurements, not supported model sizes in the current guarded build. They measure solver work, not the application UI. Dates were not recorded with this timing table.

Complete continuous-envelope times on the same calculator family were **0.72 / 1.39 / 2.26 / 3.25 s** for **2 / 3 / 4 / 5 spans**; an exact envelope query took about **4–8 ms**. The recording did not include a separate date or OS stamp. The complete UI additionally constructs its sample cache, so those times are not promises of total screen latency. No portal-device timing is claimed.

To repeat timings, build and transfer the independent benchmark, then run it on the calculator; a PC run cannot reproduce device wall-clock measurements. See [benchmark controls](DEVELOPMENT.md#benchmark). Historical acceptance dates themselves cannot be recreated by a command.

```bash
python3 tools/build_bench.py
python3 tools/package.py --bench
```

## USB transfer observations

N-Link/libnspire transfers of some TNS sizes stalled. The observations correlate with the calculated closing-packet length **17 + size % 253** being a multiple of **64**. This is an observed size/transport correlation, not proof that a particular compression library caused the failure or a universal transfer guarantee.

| Observed document | TNS bytes | Calculated last packet bytes | Device observation |
| --- | ---: | ---: | --- |
| Earlier selector build, classic zlib | 11938 | 64 | Stalled at 91% |
| Same selector build, zlib-ng | 12006 | 132 | Transferred |
| Shared-engine build, classic zlib | 20604 | 128 | Stalled at 97% |
| Shared-engine build, zlib-ng witness | 20721 | 245 | Transferred |
| BXMALO.tns | 20732 | 256 | Stalled |
| BXBUENO.tns | 20733 | 257 | Transferred |

The controlled BXMALO/BXBUENO pair used the same Lua and zlib-ng. Different compression can change size and therefore membership in the unsafe class. The packager rejects **`(17 + size % 253) % 64 == 0`**, appends a comment to generated Lua only and repackages, with at most **8 attempts**. The established guard has avoided the observed problematic sizes; normal device transfer testing is still required.

The five packaging checks cover known size witnesses, identical app/benchmark guards, safe-size preservation, the retry bound and packager failures. Actual artifact size/hash belongs to the release preparation record, since compression and environment can affect it.

Reproduce the guard and build a checked document:

```bash
python3 tests/package_check.py
python3 build.py
python3 tools/package.py
```

## Evidence index

This index maps each group of numeric claims above and in the README to the retained test, fixture or recorded observation. Compiler/runtime versions and metadata are not model accuracy claims. References to standards identify source documents, not checks implemented by this application.

| Claims / numbers | Reproducible authority |
| --- | --- |
| Six systems, four presets; 2–5 spans; cursor members 1/2/3; 20-node limit | [selector](../tests/test_selector.py), [continuous UI](../tests/continuous_ui.lua), [portal UI](../tests/portal_ui.lua), [Frame](../tests/test_frame_core.py) |
| 394=265+129; 10 independent Euler models; pivot/check/oracle tolerances and compatibility floors | [Frame tests](../tests/test_frame_core.py), [Euler tests](../tests/test_dc_reference.py), [Frame source](../src/frame_core.lua) |
| 2042=2009+2+5+26; 60 digits; scales, floors, historical errors and tiny-response input | [beam tests](../tests/test_beam_preset.py), [golden](../tests/fixtures/beam_v033_golden.json), [adjudication](../tests/fixtures/beam_v033_adjudicated.json), [adjudicator](../tools/adjudicate_beam_golden.py) |
| Single-span witness 6/10/0/10000, 45/30/16.875/3; L/250, L/300 and concrete 2.5L | [quick check](../tests/quick_check.lua), [reference-length regression](../tests/test_v033.py) |
| n+1, two combinations, all continuous counts/seed/ranges, 101 points, factors and errors | [continuous suite](../tests/test_continuous_preset.py), [brute force](../tests/continuous_bruteforce.lua), [rational reference](../tests/continuous_reference.py) |
| Continuous default exports, tied positions, uplift and positive-support witnesses | [continuous UI](../tests/continuous_ui.lua), [continuous suite](../tests/test_continuous_preset.py) |
| All portal counts, DOFs, 50-digit reference, seed, scales, conditioning values and classical witnesses | [portal suite](../tests/test_portal_preset.py), [independent reference](../tests/portal_reference.py) |
| Default portal −20 / 25 / −7.5; all section/Kleinlogel values, weight and exact route parity | [portal UI](../tests/portal_ui.lua), [section witnesses](../tests/portal_reference.py), [UI harness](../tests/test_portal_ui.py) |
| Section designations S235/S355, C20/25/C25/30/C30/37, IPE/HEA sizes and E=210 GPa; concrete weight 25 kN/m³ | [catalogue tests](../tests/test_catalog.py), [section database](../src/section_db.lua), [quick check](../tests/quick_check.lua); manufacturer year/page identifiers are retained reference metadata in the README |
| Format 0.6.1, page 3, 30=8+8+14 CAS fields and units, two decimals/0.005/10⁷/0.00; viewport sizes | [presentation](../tests/ui_presentation.lua), [portal UI](../tests/portal_ui.lua), [quick check](../tests/quick_check.lua), [exports](../src/beam_ui.lua) |
| 62 bodies, 16 extracted functions; 2263 event observations, 213389 commands and 63 screens | Recorded presentation-separation campaign summarized above; retained [UI harness](../tests/load_ui.lua) and UI suites check the current application |
| IPE 300/S235, steel/concrete catalogue values, 2021 publication and cited PDF pages, nominal 25 kN/m³ | [catalogue tests](../tests/test_catalog.py), [section data](../src/section_db.lua), manufacturer/data links in the [README](../README.md#data-references) |
| OS 4.5.5.79, acceptance dates/versions/results, BXBENCH times and continuous timing/query ranges | Recorded hardware observations reproduced in the hardware tables above; tests establish numerical responses, not those historical dates/times |
| USB constants, all size/packet pairs and percentages, retry limit and five packaging checks | Recorded transfer table above and [packager tests](../tests/package_check.py) |
| Lua 5.1.5 / liblua 5.4.7 and 16 suites | Current [suite runner](../tests/run_suites.py), [CI configuration](../.github/workflows/ci.yml) and recorded full executions |
| 2D / first-order model, standards identifiers EN 1990 A1, EN 1992-1-1/NA 7.4.1(4), EN 1993-1-1 7.2 and PDF page 144 | Model definitions above; existing data/standard links in the [README](../README.md#data-references); no normative verification is claimed |

Run the full retained evidence set with the commands in [Build, test and package](DEVELOPMENT.md#build-test-and-package).
