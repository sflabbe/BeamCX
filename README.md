# BeamCX

**Lightweight 2D Euler–Bernoulli beam calculator for the original TI-Nspire CX CAS (color screen).**
TI-Lua 5.1 app for single-span beams, continuous prismatic beams and rectangular portals, with support presets, load envelopes, deflection, and a small offline material/section catalogue. No Ndless, Python, network connection, or extra libraries are required **on the calculator**.

Version: **0.6.1 — Portal section groups**. **PC IMPLEMENTATION/PASS — HARDWARE PENDING.** A small teaching / engineering-check tool, **not** a design-code verifier.

The application uses one numerical engine: `BeamPreset → Frame.solve` for the four single-span systems and `ContinuousPreset → Frame.solve / Frame.combine` for **CONTINUOUS**. PORTAL uses `PortalPreset.solve → Frame.solve`, exactly once per stale model. Single-span calculation remains immediate; continuous beams and portals use deferred calculation and cached plots. Only complete, valid **0.6.1** saved documents are accepted. A v0.6.0 or earlier document, or any malformed current document, resets ALL state to defaults at the selector with `Invalid document or version: defaults restored`. There is no compatibility parser or migration.

## Features

- Four single-span presets: pinned–pinned, fixed–free, fixed–fixed, fixed–pinned; plus **CONTINUOUS** with **2–5 spans**, PIN/FIX ends and one shared EI.
- Visual 3×2 system selector with six cards, including **PORTAL** (one rectangular bay, equal PIN/FIX bases). All cells are accessible with arrows. Each card has compact supports and a reference bending-moment silhouette for a downward uniform load (`q>0`). These silhouettes illustrate the support cases; they are not results from the current model.
- Uniform load `q` (kN/m) and one point load `P` (kN) at position `a` (m); positive applied loads act downwards, negative loads upwards. Distributed-load arrows follow the calculated total load, including enabled self-weight.
- Reaction forces; shear `V`, bending moment `M`, and elastic deflection `w` plots, with movable cursor and displayed extrema.
- Analytical maximum absolute deflection and position, span/deflection ratio, and selectable **L/250 / L/300** comparisons with utilization percentages.
- Optional automatic self-weight from steel catalogue mass or concrete rectangle dimensions; **OFF by default**.
- PORTAL has independent **Columns / Beam** catalogue groups, with one common section for both columns. Optional portal self-weight applies to the beam only; columns display **Excluded (axial)**.
- Explicit **EXPORT CAS** action for eight numeric results in the current TI-Nspire problem: `bx_*` for single-span beams, `bc_*` for continuous beams; PORTAL explicitly exports fourteen `bp_*` values.
- **Single-span plot convention:** sagging moment `M > 0` is drawn *below* the reference line, hogging `M < 0` *above* it.
- Offline `EI` input or automatic `EI = E × I` via:
  - Concrete **C20/25, C25/30, C30/37** and editable gross rectangular section `b × h` in mm.
  - Steel **S235, S355**, IPE 100–300 and HEA 100–300, using nominal strong-axis `Iy` values.
- TI document save/restore through `on.save` / `on.restore`.
- Small app: all code is bundled into **one Lua script** and packaged as `.tns` with [Luna](https://github.com/ndless-nspire/Luna).

## Install / build on Debian Linux

Requires **Python 3**, **Luna** and the TI-Nspire file-transfer tool of your choice. `liblua5.4-0` is needed only for the local Python-based test harness.

```bash
sudo apt install build-essential zlib1g-dev python3 liblua5.4-0 lua5.1 python3-sympy

# Once only, if Luna is not already installed:
git clone https://github.com/ndless-nspire/Luna.git ~/Luna
git -C ~/Luna checkout a9924a9
make -C ~/Luna

# From the root of this BeamCX repository:
python3 build.py
luac5.1 -p BeamCX.lua
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
```

The analytical/UI Lua check can also run directly:

```bash
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
```

Packages use official **Luna commit `a9924a9`**. Use `python3 tools/package.py` after generating Lua. It runs `~/Luna/luna`, checks the document size and adds a comment line at the end of the generated Lua only if required, then repackages (at most eight total attempts). `src/` is never padded. To package the existing benchmark, use `python3 tools/package.py --bench`; both use the same guard. Rebuilding Lua removes any previous padding.

The owner confirmed the **N-Link/libnspire USB closing-packet failure in hardware**: libnspire sends file chunks of 253 bytes; the last USB packet has `17 + (tns_size % 253)` bytes. When that length is a multiple of 64, the short closing packet is missing and transfer hangs. The packaging guard rejects `(17 + size % 253) % 64 == 0`. The controlled experiment used the same Lua and zlib-ng for both files: `BXMALO.tns` (20,732 bytes) hung, while `BXBUENO.tns` (20,733 bytes) transferred successfully. Compression changes document size and therefore whether this condition occurs; the failure is not assigned to a compression library.

| Observed document | TNS bytes | Last USB packet | Hardware result |
| --- | ---: | ---: | --- |
| v0.3.2, classic zlib | 11,938 | 64 | Hung at 91% |
| v0.3.2, zlib-ng | 12,006 | 132 | Transferred |
| v0.4.0, classic zlib | 20,604 | 128 | Hung at 97% |
| v0.4.0, zlib-ng witness | 20,721 | 245 | Transferred |
| BXMALO.tns, zlib-ng | 20,732 | 256 | Hung |
| BXBUENO.tns, zlib-ng | 20,733 | 257 | Transferred |

Keep the recommendation to use **simple file names without extra dots** (e.g. `BeamCX.tns`) and the calculator's root folder. Newly generated packages still require owner transfer testing; the guard checks the confirmed size condition on the PC.

The generated `BeamCX.tns` can be transferred using [N-Link Web](https://n-link.lights0123.com/) in Chrome/Chromium. Open it under **My Documents** on the TI-Nspire. The generated `.lua` and `.tns` files are ignored by Git. **Do not use** N-Link's *Upload OS* button for a `.tns` document.

Supported target / hardware history: original TI-Nspire CX CAS with OS **4.5.5.79**. **v0.3 was tested on 2026-11-18** using S235, IPE 300 and `q = 10 kN/m` with automatic self-weight: results, the L/250 deflection comparison and CAS export were checked, including `bx_mmax = 46.8629` read in a Calculator page.

**v0.3.2 was also validated on hardware on 2026-11-18:** selector and silhouettes; returning with Esc; Esc during editing; inert Tab in the selector; retained result after `invalid number` and recovery of EXPORT CAS; saving in the selector. FIX-PIN with `q = 10 kN/m`, `L = 6 m`, `EI = 10,000 kN·m²` gave `RA = 37.5 kN`, `RB = 22.5 kN`, `M(3 m) = 22.5 kNm`, `Mmin = −45 kNm`, `Mmax = 25.313 kNm`, matching the analytical values.

**v0.3.3 was hardware-tested on a TI-Nspire CX CAS on 2026-11-18:** load arrows followed the sign for negative q and P, including upward P with downward q; titles and supports had no overlaps. A C25/30 cantilever with self-weight and `Lref=2.5L (EC2/NA)` gave `|w|max = 31.446 mm` and `Lref/|w| = 477.01`. Other materials displayed `AGREE LIMIT`. The classic-zlib package transferred successfully with a plain file name in the root folder.

**v0.6.0 / P6C-0 is accepted on the original CX CAS by the owner.** v0.6.1 portal section groups remain hardware pending. See [P6C-R1 validation and owner checklist](VALIDATION_P6C_R1.md), the [simulated contact sheet](PORTAL_UI_CONTACT.png), historical [P6B validation](VALIDATION_P6B.md) and [P5B validation](VALIDATION_P5B.md). See the historical [P2B validation report](VALIDATION_P2B.md) and the [P5A calculation report](VALIDATION_P5A.md).

## Keys

The table below describes the single-span pages; CONTINUOUS controls follow it.

New documents open at **SELECT SYSTEM**. Choose a card with the arrows and press `ENTER` to confirm the system and open beam input. A failed calculation keeps the previous confirmed model and leaves the selector open with an error. `ESC` returns to the selector; while entering a number, the first `ESC` only cancels that edit. Valid current documents reopen on their saved page, except continuous and portal results reopen at input and wait for the user to enter results. Input/section focus is reset and is not part of the saved document. Invalid documents open at the default selector with “Invalid document or version: defaults restored” until the first key action.

| Key | System selector | Beam input | Diagrams / results | Material / section |
| --- | --- | --- | --- | --- |
| `TAB` | No effect | Diagrams | Material / section | Beam input |
| `↑` / `↓` | Choose row | Choose field | Move cursor; in results select L/250 or L/300 | Choose field |
| `←` / `→` | Choose column | Change support preset | Cycle M / V / w / results | Change material, profile or self-weight ON/OFF |
| `ENTER` | Confirm and open input | Apply numerical input | Open results; in results **EXPORT CAS** | Apply input or toggle selection |
| `ESC` | No effect | Cancel active edit; otherwise selector | Selector | Cancel active edit; otherwise selector |

In the input page: `L` and `a` in **m**, `q` in **kN/m**, `P` in **kN**, `EI` in **kN·m²**. Numerical `EI` is editable when material is `MANUAL`; catalogue EI displays `(auto)` beside its value. In the sections page, choose a material and either a steel profile or concrete dimensions. Use the calculator's normal document save command to retain settings.

### CONTINUOUS

Select **CONTINUOUS** and press `ENTER`. Use `↑` / `↓` to scroll the input list. `←` / `→` changes the number of spans (2–5, default 3) and PIN/FIX end supports. Type a number and press `ENTER` for each span length, g, q and the three factors. Lengths must be positive; added spans copy the last retained length. Defaults are 6 m per span, PIN–PIN, g=10 and q=5 kN/m, γG,sup=1.35, γG,inf=1.00 and γQ=1.50.

Edits mark the result **Outdated** and discard the plot cache. `TAB` enters results, displays **Calculating…**, and schedules calculation in a short timer; painting never solves. On completion, approximately 20 points per span and both sides of each internal support are stored once. Repainting and switching result modes use this cache. `↑` / `↓` moves the cursor over the total length, including each support, with one exact envelope query per movement. Shear readings at internal supports show both sides.

Use `←` / `→` to cycle **M envelope**, **V envelope**, **characteristic w** and **compact table**. Positive M is below the axis. V includes support jumps. The w plot shows the two characteristic odd/even load patterns, positive downward, in mm. This deflection rule is verified against exhaustive test cases; it is not a theorem for all beam configurations. In the table, `↑` / `↓` selects spans or supports. Span rows show L, positive M maximum (or —), governing w with ↓/↑, L/|w| and status; support rows show Mmin, positive Mmax when present, Rmax and Rmin. Global |V|max and the actual factors appear below both tables.

`TAB` from results opens the shared material/section page. EI and self-weight use the same catalogue as single-span beams. Enabled self-weight is added **once to g**, never to q. Select **Defl. limit** there to choose L/250 or L/300; each span uses its own length as Lref. `TAB` returns to input. Continuous calculation runs only on entering results after an edit.

The displayed factor convention is **γ: OPEN (EN 1990 A1 + NA)**. Factors are editable project inputs; their defaults do not establish compliance with EN 1990 Annex A1 or the applicable National Annex. Moment, shear and reaction envelopes use favorable/unfavorable contributions and both global γG choices. Characteristic w uses unit factors.

On the compact table, `ENTER` exports only these eight variables; the single-span `bx_*` namespace is unchanged and is exported only in that mode:

| Variable | Meaning | Unit |
| --- | --- | --- |
| `bc_mmax` | Global algebraic M maximum | kNm |
| `bc_mmin` | Global M minimum | kNm |
| `bc_vabs` | Global maximum absolute shear | kN |
| `bc_rmax` | Maximum support reaction | kN |
| `bc_wmax` | Governing absolute characteristic deflection | **mm** |
| `bc_xwmax` | Its global position | m |
| `bc_ei` | Shared flexural rigidity | kN·m² |
| `bc_n` | Span count | — |

Case E (3×6 m, PIN–PIN, g=10, q=5, EI=10000, default factors, self-weight OFF) exports Mmax=66.0005357143, Mmin=−80.1, |V|max=76.35, Rmax=143.1 and |w|max=15.3264571214 mm. The symmetric maximum may be reported at 2.75420947417 or 15.24579052583 m; `bc_xwmax` equals the solver summary position and attains that characteristic maximum.

### Numerical display and editing

The interface is English throughout. Numerical results use two decimal places, for example `15.00 kN`, `3.96 mm`, `5.10 m` and `1.35` for a load factor. Exact zero, including negative zero, displays as `0.00`. Nonzero magnitudes below 0.005 use scientific notation with a two-decimal mantissa, such as `-1.23e-08`, to retain their sign and magnitude. Values of magnitude 10⁷ or greater also use scientific notation to fit the small display.

This formatting only changes the text shown on screen. Keyboard text stays unrounded while editing; solver input, extrema, comparisons, saved numbers and `bx_*`/`bc_*`/`bp_*` exports retain full precision. Only complete v0.6.1 documents are accepted; v0.6.0 and earlier documents are rejected, never migrated. Long selector diagnostics wrap instead of being truncated. See the [R2 validation and naming report](VALIDATION_P5B_UI_POLISH_R2.md).

### PORTAL

Choose the sixth card and press ENTER. Geometry is one rectangular bay with
height h and beam width l. Both bases are PIN or both FIX. Nodes 1/4 are the
left/right bases, nodes 2/3 the left/right eaves; members are 1→2 (left column),
2→3 (beam), and 4→3 (right column). **Both columns run bottom to top.**

UP/DOWN selects a field in the scrolling input list. LEFT/RIGHT toggles Base.
Type numbers and press ENTER to confirm; editing retains full precision.
Defaults: FIX, h=4 m, l=6 m, EIc=10000 and EIb=15000 kN·m², q=10 kN/m,
P=0 kN at a=3 m, H=0 kN and w=0 kN/m. Both section groups initially use
MANUAL, retaining the accepted default results. EIc/EIb are derived from
the Columns/Beam sections. Input EI edits update the corresponding manual
section; catalogue groups display `(auto)` and reject edits with
`EI from section; use TAB`.

TAB cycles **Input → Results → Sections → Input**. The existing section
page starts with **Group | Columns / Beam**; LEFT/RIGHT switches groups.
Each group independently uses the existing materials, steel profiles,
concrete b/h dimensions or manual EI. All properties come from the offline
catalogue; concrete bending uses I=b·h³/12. Section changes mark results
outdated and never solve on the section page. No deflection-limit row is
shown for portals.

Beam self-weight is optional and OFF by default. With ON, each solve uses
a copy with q_total=q_user+q_sw; input q remains unchanged. MANUAL or absent
weight data forces OFF. Columns show **Excluded (axial)** and cannot enable
self-weight. The load header adds `sw=…` only when ON, and arrows follow
the effective beam load. The results table begins with Columns, Beam and
Self-weight provenance rows, using the catalogue labels and materials.

q and P are positive downward on the beam. H acts at the left eave, positive
rightward. w is uniform on the left column, positive rightward. Negative
values reverse arrows; zero loads draw none. Loads are characteristic and
simultaneous, with no factors or combinations. Validation delegates to
PortalPreset.model; invalid edits preserve valid parameters and results.
When P=0, reducing l below inactive a resets a=l/2; active invalid a is rejected.

Valid changes mark results stale. TAB queues the normal TI timer and displays
`Calculating...`; one PortalPreset.solve and one Frame.solve then populate the
result and plot cache. TAB advances through sections to input and cancels
pending work when leaving results. Repaints, mode changes, table
scrolling and CAS export do not solve. A failed calculation restores the prior
confirmed model; there is no partial result publication.

LEFT/RIGHT cycles **M, V, N, Deformed, Results**. Keys **1/2/3** select the
left column/beam/right column; UP/DOWN moves along its local coordinate s.
Columns start at the base; the beam starts at the left eave. Cursor readings
use one PortalPreset.at query per change. At beam P the cursor visits left
and right shear limits separately, with an explicit side label. ENTER opens
the table; ENTER in the table exports CAS. UP/DOWN scrolls table rows.
ESC cancels an edit or returns to the system selector.

N is positive in tension. V keeps Frame's local-member convention
(dM/ds=V, dV/ds=q_local). **M positive tensions local −y**: rightward for
both columns and downward for the beam. Moments are drawn on that tension
side with a common scale, without flipping the right column. V/N ordinates
use local +y; N tension is orange and compression cyan. Graphics use roughly
20 intervals per member plus endpoints and the exact P cut; V draws the jump
at a, including both sides. Reported M extrema come from PortalPreset, and
maximum |V| uses exact recovery endpoints and both P limits, not screen pixels.

The deformed view transforms recovered local axial/transverse displacements
to global coordinates and shows the original geometry faintly. The displayed
magnification factor is for visibility. This **absolute displaced shape** is
separate from the reported **beam deflection relative to the displaced end
chord**, taken unchanged from sol.deflection. Drift is global horizontal
motion at each eave. The table shows drift and signed w_rel in mm, h/|drift|,
l/|w_rel| and its local position; zero ratios display a dash. Deformation
limits remain **OPEN (project / NA)**. There is no serviceability certification.

EA=1e6·EI/L² is a finite approximation to negligible axial deformation, not a
physical EA input or universal precision guarantee. This is a linear elastic
first-order model, without P-Delta or stability analysis. Gable frames, multiple
bays/stories, inclined loads, joint releases, portal envelopes and code design
checks are outside v0.6. See the [P6A precision qualification](VALIDATION_P6A.md).

Portal CAS exports are unrounded numeric values, only on explicit ENTER in
the results table. PIN moments export numeric zero. All fourteen values are
validated before any store; partial failures show an error, never success.
Only fourteen successful stores display `CAS: 14 variables stored`.
Enabled beam self-weight is included in these results; names, count, units
and meanings are unchanged. The `bx_*` and `bc_*` contracts are unchanged.

| Variable | Meaning | Unit |
| --- | --- | --- |
| bp_hl | Left base horizontal reaction (+right) | kN |
| bp_vl | Left base vertical reaction (+up) | kN |
| bp_ml | Left base reaction moment (+CCW) | kNm |
| bp_hr | Right base horizontal reaction | kN |
| bp_vr | Right base vertical reaction | kN |
| bp_mr | Right base reaction moment | kNm |
| bp_mmax | Global algebraic member M maximum | kNm |
| bp_mmin | Global algebraic member M minimum | kNm |
| bp_nabs | Maximum absolute member N | kN |
| bp_vabs | Maximum absolute member V, including both P sides | kN |
| bp_dxl | Signed left eave horizontal drift | mm |
| bp_dxr | Signed right eave horizontal drift | mm |
| bp_wrel | Signed governing beam chord-relative deflection | mm |
| bp_xwrel | Local position of governing beam deflection | m |

Save/restore persists all three parameter sets, both `portal_sections`, the
active section group, beam self-weight flag, active system, page/mode,
portal member and local cursor. Portal page 3 is retained; results reopen
at input and wait for normal deferred calculation. EIc/EIb are recomputed
from the saved groups before physical validation; contradictory saved EI
caches never override the catalogue. Invalid groups, incompatible ON weight
or an invalid physical model reject the whole document and restore defaults.
Matrices, solutions, samples and timers are not serialized.
**Only exact format 0.6.1 is accepted; no v0.6.0 migration.**

### Deflection comparison and self-weight

The compact results view shows `|w|max` in **mm**, its position in **m**, `L/|w|` using consistent length units, and utilization `|w|max / (L / limit)` for both limits. Maxima include all segment boundaries and stationary points of Frame's analytical deflection recovery; they do not depend on plot samples or cursor position. If equal absolute maxima exist, one maximizing position is reported. The selected comparison reports **OK**, **EXCEEDED**, or **N/A** for an undefined ratio (zero deflection). The default limit is L/250. These are user-selected comparison limits, not universal code-compliance certificates.

For **concrete cantilevers**, the comparisons use **`Lref = 2.5 × L`**, following DIN EN 1992-1-1/NA, NCI to **7.4.1(4)** ([official publication, PDF page 144](https://www.niedersachsen.de/download/140002/Nds._MBl._Nr._3_2019_vom_24.01.2019_Anlagenband_1-Teil_1.pdf#page=144)). The screen shows `Lref/|w|` and `Lref=2.5L (EC2/NA)`; utilization is `|w|max / (Lref / limit)`. **This changes the ratio and L/250 / L/300 utilization only for concrete cantilevers**, relative to v0.3.2. It does not change maximum deflection, reactions, moments or exported `bx_` values. The three other support presets continue to use `Lref = L` for every material.

For **steel or MANUAL cantilevers**, `Lref = L` remains the comparison reference and the screen displays **CANTILEVER: AGREE LIMIT**. Cantilever deflection limits must be agreed for the project or supplied by the applicable National Annex; EN 1993-1-1, **7.2**, does not supply a universal equivalent cantilever span. L/250 and L/300 are comparison settings here, not asserted normative cantilever limits.

Choose **Self-weight** on the section page and press `ENTER` or `←` / `→` to switch it ON/OFF. Steel uses `mass [kg/m] × 9.81 / 1000`; concrete uses `25 × (b/1000) × (h/1000)`, both in **kN/m**, positive downward. Input `q user` remains separate; each solve uses `q total = q user + q sw` only when ON. The results view shows available `q sw`, the ON/OFF state and the applied `q total`. With OFF, the displayed available self-weight is not added. Recalculation, section changes and restore never accumulate it. Manual EI or missing weight data show **N/A** and force self-weight OFF. Both settings persist in valid current documents. An invalid document or another saved format resets all settings and input together.

Concrete results display **RC: GROSS EI ONLY**. No cracked stiffness, creep or long-term deflection is calculated.

### CAS export

On the results view, press `ENTER` at **EXPORT CAS**. After a successful solve, native [`var.store`](https://education.ti.com/html/eguides/nspire/eg_nspire/en/content/eg_lua/m_libraries/variablelib/store.HTML) writes these numeric variables. Add or open **Calculator in the same TI-Nspire problem**, then enter a variable name such as `bx_wmax` to use it. The stable `bx_` namespace is overwritten only on explicit export; units are conventions for the numeric values, not attached CAS unit objects.

| Variable | Meaning | Unit |
| --- | --- | --- |
| `bx_mmax` | Maximum signed bending moment | kNm |
| `bx_mmin` | Minimum signed bending moment | kNm |
| `bx_vabs` | Maximum absolute shear, including segment sides | kN |
| `bx_wmax` | Maximum absolute deflection | mm |
| `bx_xwmax` | Position of maximum absolute deflection | m |
| `bx_ra` | Left vertical reaction | kN |
| `bx_rb` | Right vertical reaction (zero at the free end, apart from roundoff) | kN |
| `bx_ei` | Flexural rigidity used in the solve | kN·m² |

**CAS: 8 variables stored** appears only if every store succeeds. API errors identify the failed variable; a partial export may have updated earlier variables. A failed calculation blocks export until a successful calculation. Previously exported CAS variables remain unchanged until another export.

## Example / sanity check

Pinned–pinned beam, `L = 6 m`, uniform `q = 10 kN/m`, `P = 0`:

- Left and right reactions: **30 kN** each.
- Maximum sagging moment at midspan: **45 kN·m**.
- For `EI = 10,000 kN·m²`, midspan deflection: **−16.875 mm** (negative means downward in the model).

The same beam with S235 and IPE 200 uses `E = 210,000 MPa` and `Iy = 1,943 cm⁴`, giving `EI = 4,080.3 kN·m²`.

## Scope and limitations

- The UI offers four single-span presets and continuous beams with 2–5 spans, PIN/FIX ends and one EI. General frames, seismic and dynamic analysis remain outside the application scope. Continuous input supports full-span g/q only. No multiple load points, partial/trapezoidal UDL, thermal or prescribed displacements.
- Linear, small-deflection, prismatic Euler–Bernoulli analysis; self-weight is included only when explicitly switched ON. Continuous load envelopes use the editable factors described above; no resistance checks are performed.
- **Concrete:** `Ecm` with **gross uncracked** rectangular inertia only. Displayed deflections are **not** cracked/creep-adjusted reinforced-concrete service deflections. No reinforcement or EC2 design verification.
- Steel profile values are nominal and not geometric/material strength checks; neither steel nor concrete code verification is performed.
- The five independently resolved legacy failures now solve through Frame, including loads near supports. The engine limit is 20 model nodes, based on the CX CAS measurements below; numerical checks remain unchanged.
- If `P != 0`, changing `L` below the existing position `a` is rejected until `a` is adjusted.
- No warranty of fitness for structural design: independently verify results for engineering use.

## Source layout

```text
BeamCX/
├── src/
│   ├── frame_core.lua      # Single productive numerical engine and recovery
│   ├── beam_preset.lua     # Four presets; downward input sign boundary; CAS summary
│   ├── continuous_preset.lua # Productive continuous bases, envelopes and summary
│   ├── portal_preset.lua   # Frozen P6A rectangular portal, one Frame.solve
│   ├── section_db.lua      # Offline materials, IPE / HEA Iy and mass
│   └── beam_ui.lua         # TI-Lua painting, keys, persistence
├── tests/
│   ├── test_port.py        # Independent structural witnesses + UI smoke test
│   ├── test_catalog.py     # EI, materials, inputs and persistence
│   ├── test_plot_sign.py   # M/V/w plotting conventions
│   ├── test_arrows.py      # One filled arrowhead per load
│   ├── test_quick_check.py # Quick Beam Check harness
│   ├── test_selector.py    # Visual selector, reference moments, Esc, restore
│   ├── test_v033.py        # Signed loads, text bounds, Lref, CAS regression
│   ├── test_beam_preset.py # Generated bundle vs frozen golden/adjudication
│   ├── test_productive_route.py # UI → Frame instrumentation, cursors, RESOLVED
│   ├── test_frame_core.py  # 394 original Frame oracles and retained regressions
│   ├── test_continuous_preset.py # Rational reference, patterns, combine, uplift
│   ├── test_continuous_ui.py # Deferred solve, cache, cursor, bc_* and strict restore
│   ├── test_ui_presentation.py # English text/names, numeric display and precision
│   ├── ui_presentation.lua  # All-screen bounds/overlap checks and saved contracts
│   ├── continuous_ui.lua    # Real continuous UI events, test-only instrumentation
│   ├── continuous_reference.py # Independent SymPy rotation-only stiffness
│   ├── run_suites.py       # Complete suite under liblua5.4 or a Lua CLI
│   ├── test_dc_reference.py # Frame vs frozen dc Euler reference
│   ├── fixtures/beam_v033_golden.json # Frozen v0.3.3 inputs and outputs
│   ├── fixtures/beam_v033_adjudicated.json # Independent 60-digit references
│   ├── fixtures/dc_reference.json # Frozen dc Euler reactions/displacements
│   └── quick_check.lua     # Analytical checks, self-weight, CAS, UI / persistence
├── tools/
│   ├── make_beam_golden.py # Retained input provenance / Lua fixture serialization
│   ├── adjudicate_beam_golden.py # Independent mpmath oracle (offline)
│   ├── dc_reference.py    # dc fixture generator (offline)
│   ├── bench_ti.lua      # Independent CX timing screen and PC measurement
│   ├── package.py        # Shared bounded USB size guard, app / benchmark
│   └── build_bench.py    # Bundle only bench.lua
├── .github/workflows/ci.yml
├── build.py                # Bundle to BeamCX.lua
├── bench.lua               # Generated independent benchmark
├── BXBENCH.tns             # Generated benchmark for the calculator
├── VALIDATION_P2B.md       # Migration results and hardware acceptance status
├── CHANGELOG.md
└── README.md
```

The Python tests use standard library `ctypes` to execute actual Lua code against `liblua5.4.so.0` and a stub TI graphics canvas. `tests/run_suites.py --lua lua5.1` executes the same Lua chunks with the target interpreter; `quick_check.lua` also runs directly. All **16 suites pass under Lua 5.1.5 and Lua 5.4.7**, including the 136-model P6A campaign and productive portal UI suite. The P5A test-only reference requires SymPy; the numerical application has no Python dependency. This includes the unchanged 394 Frame oracles, frozen 2,042-case equivalence/adjudication suite loaded through the generated application, all four P0/eight-CAS witnesses, and a real UI recalculation instrumenting `Frame.solve`. The five RESOLVED cases also succeed via UI restore and export. Single-span limit changes and all repaint operations do not solve again. Continuous edits, including the comparison limit, defer calculation until results entry. Drawing checks cover 318×212, 320×212 and 320×240, with simulated font metrics. On the calculator, load clearance uses `gc:getStringHeight`; without it, a 10 pt font plus a fixed 4 px text-box margin is used. These checks do not replace physical-device validation.

## Benchmark (P2A / P5A)

Build and package the independent benchmark with official Luna `a9924a9`:

```bash
python3 tools/build_bench.py
python3 tools/package.py --bench
# Optional PC CPU reference, including complete continuous-beam envelopes:
lua5.1 -e "dofile('bench.lua').pc()"
```

Transfer **BXBENCH.tns** under that plain name into the calculator's root folder and open it. It starts automatically and shows Frame's version/hash, nodes/GDL, solution time and time for 101 recovery calls. The six original model rows are retained; the 40/60-node rows now report the existing 20-node guard and measurement continues. Four added rows, `continua 2 env` through `continua 5 env`, time the P5A.1 complete calculation (n+1 bases, exact quadratic moment envelopes, linear support/shear envelopes and two characteristic deflection combinations); their recovery column measures 101 exact envelope queries. Arrow keys switch between the two result pages. Each phase uses at least three repetitions and targets at least 200 ms accumulated measured time (maximum 4096 repetitions). Measurement yields between operations so the screen can update. Painting is excluded. The clock is TI's [`timer.getMilliSecCounter()`](https://education.ti.com/html/eguides/nspire/eg_nspire/en/content/eg_lua/m_libraries/timerlib/getmilliseccounter.HTML), available since API 1.0; 32-bit rollover is handled. PC reference runs use `os.clock` CPU time. The reference measurements below were obtained on the original TI-Nspire CX CAS. They measure the general solver and do not guarantee application UI timings. This build does not change `BeamCX.lua`.

Existing BXBENCH solve-time references (P2A closed):

| Model | Measured solve time |
| --- | ---: |
| Single-span beam | 76.67 ms |
| Continuous beam, five spans | 470 ms |
| Gable frame | 276.67 ms |
| 20 nodes | 2726.67 ms |
| 40 nodes | 8830 ms |
| 60 nodes | 20670 ms |

The numerical guard permits 20 model nodes; 21 or more return `model too large for handheld`. No new performance threshold or confirmation screen is introduced.

Offline oracle tools (normal tests need neither numpy, dc nor mpmath):

```bash
# Consume the frozen golden; legacy live regeneration was retired with its solver:
python3 tests/test_beam_preset.py
python3 tools/adjudicate_beam_golden.py  # mpmath, 60 digits
python3 tools/dc_reference.py ~/dinamica-computacional  # numpy + local dc checkout
```

The retained P2A comparison rules distinguish **2,009 ordinary equivalent cases, two independently adjudicated cases, five RESOLVED legacy failures and 26 invalid inputs**. P2B consumes these fixtures without regenerating them or changing the numerical authority. Global equivalence uses `S_X = max(case response magnitudes, 1e-6·X_ref)`, with `F=|q|L+|P|`, `V_ref=F`, `M_ref=FL` and `w_ref=FL³/EI`. It is not a precision bound for nearly zero responses. The tiny FIX-PIN deflection has its own nonzero oracle; support zeros are checked in prescribed nodal DOFs. The adjudicated fixture is separate from the untouched golden. The dc generator explicitly uses Euler–Bernoulli and compares reactions/displacements only, with N→kN conversion; only horizontal members carry its uniform loads.

The frozen rectangular portal preset (P6A, now productive through PORTAL) uses
`EA = 1e6 * EI / L²` to approximate negligible axial deformation. Finite-EA
approximation error and floating-point roundoff are distinct; neither has a
universal bound for every geometry. The independent random-model tests use
`max(1e-9, 10·κ∞(Kfree)·epsilon)` for displacement comparisons only, with a
qualification limit of `1e-6`; force, moment and equilibrium thresholds stay at
`1e-9`. Conditioning depends on matrix units and scaling. This is a linear
elastic first-order model without second-order stability analysis. Large drifts
in extreme random cases are numerical stress tests and need not represent valid
small-displacement engineering configurations. See [P6A validation](VALIDATION_P6A.md).

## Continuous-beam calculation (P5A / P5A.1)

The productive `ContinuousPreset` handles 2–5 spans (definitive `MAX_SPANS=5`), PIN/FIX ends, continuous rotations over intermediate vertical supports, one EI, and full-span uniform g/q loads. Supply self-weight once as part of g. P5B connects these calculations to the selector, shared sections, persistent input, plots, tables and `bc_*` export. Point loads remain exclusive to the single-span presets.

`ContinuousPreset.model(p, 'G' or span_index)` creates the permanent and individual variable-load cases; `solve(p)` uses exactly n+1 Frame solves. Its result exposes `envelope_at(global_x, side)`, span algebraic `Mmax`/`Mmin` and positive `Mplus`, signed downward/upward characteristic deflection records and the governing L/250 or L/300 comparison, support Mmin/Mmax/Rmax/Rmin, global absolute shear and a semantic summary. Records include local/global position, load pattern text and the governing global gammaG where applicable. P5A.1 removes pattern enumeration from `src/`. Linear quantities use the exact sum of favorable/unfavorable basis contributions and both global gammaG choices. Moment envelopes split the span at the real roots of G and Qi; on each piece only its endpoints and quadratic vertex are candidates. This includes positive support moments and does not use alternating patterns for moments. Characteristic deflection uses unit factors and the two odd/even patterns with Frame extrema, labelled **w char.** That deflection rule is experimentally verified, **not a theorem**. Defaults are gammaG_sup=1.35, gammaG_inf=1 and gammaQ=1.5; their convention is explicitly **OPEN**, to be checked against EN 1990 Annex A1 and the applicable NA. No normative compliance is claimed.

`Frame.combine(solutions, factors)` superposes compatible recovered results without assembly/solve and without changing its operands. Geometry, connectivity, EI/EA, supports, springs, releases and recovery cuts must match. Incompatibilities return `nil, 'incompatible solutions: ...'`. Per the approved API change, standalone `Frame.deflection_extrema` now returns `wmin, xmin, wmax, xmax` in one search; BeamPreset selects the larger absolute value, preserving its API. The generated application includes both presets and this shared Frame API. P5B-R1 left both calculation modules unchanged. UI polish R2 only translates ContinuousPreset display labels and renames its local characteristic-result variable; all formulas and the complete Frame module, including `Frame.combine`, remain unchanged.

P5A tests retain independent rational SymPy stiffness (rotational DOFs only), direct Frame load sums, 101 points/span, and separate uplift/downward extrema. P5A.1 additionally checks 300 deterministic random models (1,050 spans, all PIN/FIX end combinations, spans 2–10 m, g/q in 0–30 kN/m) against test-only exhaustive Frame combinations. Values, positions and reported governing patterns are compared at 1e-9. The positive support-B regression requires +28.081141172746 with pattern `3` and gammaG=1.00. [The P5A.1 report](VALIDATION_P5A1.md) gives errors and current PC timings; [P5A](VALIDATION_P5A.md) retains the initial exhaustive baseline and API description. Measured complete envelopes on the CX take 0.72 / 1.39 / 2.26 / 3.25 s for 2 / 3 / 4 / 5 spans. A single envelope query takes about 4–8 ms. These measurements fix MAX_SPANS=5 and deferred continuous calculation. UI sampling adds work after the solve; the delivered package still needs owner timing on the CX.

## Data references

- Concrete `Ecm` (30 / 31 / 33 GPa): [Betontechnische Daten](https://www.betontechnische-daten.de/de/betontechnologie/formaenderungen/elastische-verformung).
- Steel modulus: `210 GPa` for both S235 and S355, standard EN 1993 elastic convention.
- Nominal IPE / HEA strong-axis properties: [crosssections.app IPE](https://crosssections.app/en/guides/ipe-complete-guide) and [HEA](https://crosssections.app/en/hea). Values are statically embedded in `src/section_db.lua`.
- Steel mass per metre: **ArcelorMittal, Sections and Merchant Bars, 2021 Sales Programme**, column `G [kg/m]`, IPE and HE A tables ([manufacturer PDF](https://sections.arcelormittal.com/repository2/Sections/Sections_MB_ArcelorMittal_FR_EN_RU.pdf), PDF pages 48/50 and 56/58). HE A corresponds to the app's HEA names. All 21 catalogue masses are embedded alongside the unchanged `Iy` values; e.g. IPE 200 = **22.4 kg/m**, HEA 200 = **42.3 kg/m**.
- Concrete self-weight: documented nominal assumption **25 kN/m³** for normal-weight concrete sections, including a conventional reinforcement allowance. It is not inferred from concrete grade or reinforcement quantity.

## License

MIT — see [LICENSE](LICENSE).

## Development note

The beam formulation was adapted for a restricted single-span TI-Lua application using Euler–Bernoulli frame-element stiffness terms; it is **not** a complete port of the original `dinamica-computacional` project. P2B activates the already validated Frame engine without changing its mechanics, tolerances or sign conventions. Load signs convert at the existing BeamPreset and ContinuousPreset boundaries.
# BeamCX
