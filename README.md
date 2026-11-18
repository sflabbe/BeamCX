# BeamCX

**Lightweight 2D Euler–Bernoulli beam calculator for the original TI-Nspire CX CAS (color screen).**
TI-Lua 5.1 app for one prismatic beam span, with support presets, load diagrams, deflection, and a small offline material/section catalogue. No Ndless, Python, network connection, or extra libraries are required **on the calculator**.

Version: **0.3.3 — Quick Beam Check**. A small teaching / engineering-check tool, **not** a design-code verifier.

## Features

- One horizontal span with four boundary-condition presets: pinned–pinned, fixed–free, fixed–fixed, fixed–pinned.
- Visual 2×2 system selector with compact supports and reference bending-moment silhouettes for a downward uniform load (`q>0`). These silhouettes illustrate the four support cases; they are not results from the current model.
- Uniform load `q` (kN/m) and one point load `P` (kN) at position `a` (m); positive applied loads act downwards, negative loads upwards. Distributed-load arrows follow the calculated total load, including enabled self-weight.
- Reaction forces; shear `V`, bending moment `M`, and elastic deflection `w` plots, with movable cursor and displayed extrema.
- Analytical maximum absolute deflection and position, span/deflection ratio, and selectable **L/250 / L/300** comparisons with utilization percentages.
- Optional automatic self-weight from steel catalogue mass or concrete rectangle dimensions; **OFF by default**.
- Explicit **EXPORT CAS** action for eight numeric results in the current TI-Nspire problem.
- **Plot convention:** sagging moment `M > 0` is drawn *below* the reference line, hogging `M < 0` *above* it.
- Offline `EI` input or automatic `EI = E × I` via:
  - Concrete **C20/25, C25/30, C30/37** and editable gross rectangular section `b × h` in mm.
  - Steel **S235, S355**, IPE 100–300 and HEA 100–300, using nominal strong-axis `Iy` values.
- TI document save/restore through `on.save` / `on.restore`.
- Small app: all code is bundled into **one Lua script** and packaged as `.tns` with [Luna](https://github.com/ndless-nspire/Luna).

## Install / build on Debian Linux

Requires **Python 3**, **Luna** and the TI-Nspire file-transfer tool of your choice. `liblua5.4-0` is needed only for the local Python-based test harness.

```bash
sudo apt install build-essential zlib1g-dev python3 liblua5.4-0

# Once only, if Luna is not already installed:
git clone https://github.com/ndless-nspire/Luna.git ~/Luna
git -C ~/Luna checkout a9924a9
make -C ~/Luna

# From the root of this BeamCX repository:
python3 build.py
for test in tests/test_*.py; do python3 "$test"; done
~/Luna/luna BeamCX.lua BeamCX.tns
```

If Lua 5.1 is installed, also check the target syntax and run the new analytical/UI regressions:

```bash
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
```

Releases are packaged with official **Luna commit `a9924a9`**. Luna compresses with the system zlib, so `.tns` sizes differ between machines (classic zlib vs. zlib-ng: e.g. 11,938 vs. 12,006 bytes for the same v0.3.2 script); both are valid, and size is not a cross-machine build check. One upload of v0.3.2 stalled N-Link at 91 %. That attempt used the file name `BeamCX_0.3.tns` (extra dot), the `Apps` folder and the classic-zlib build; the transfer that worked used a plain name, the root folder and the zlib-ng build. The cause was not isolated. The classic-zlib v0.3.3 build later transferred fine under a plain name in the root folder. Recommended practice: plain file names without extra dots (e.g. `BeamCX033.tns`) and the root folder.

The generated `BeamCX.tns` can be transferred using [N-Link Web](https://n-link.lights0123.com/) in Chrome/Chromium. Open it under **My Documents** on the TI-Nspire. The generated `.lua` and `.tns` files are ignored by Git. **Do not use** N-Link's *Upload OS* button for a `.tns` document.

Supported target / hardware history: original TI-Nspire CX CAS with OS **4.5.5.79**. **v0.3 was tested on 2026-11-18** using S235, IPE 300 and `q = 10 kN/m` with automatic self-weight: results, the L/250 deflection comparison and CAS export were checked, including `bx_mmax = 46.8629` read in a Calculator page.

**v0.3.2 was also validated on hardware on 2026-11-18:** selector and silhouettes; returning with Esc; Esc during editing; inert Tab in the selector; retained result after `invalid number` and recovery of EXPORT CAS; saving in the selector. FIX-PIN with `q = 10 kN/m`, `L = 6 m`, `EI = 10,000 kN·m²` gave `RA = 37.5 kN`, `RB = 22.5 kN`, `M(3 m) = 22.5 kNm`, `Mmin = −45 kNm`, `Mmax = 25.313 kNm`, matching the analytical values.

**v0.3.3 was hardware-tested on a TI-Nspire CX CAS on 2026-11-18:** load arrows followed the sign for negative q and P, including upward P with downward q; titles and supports had no overlaps. A C25/30 cantilever with self-weight and `Lref=2.5L (EC2/NA)` gave `|w|max = 31.446 mm` and `Lref/|w| = 477.01`. Other materials displayed `AGREE LIMIT`. The classic-zlib package transferred successfully with a plain file name in the root folder.

## Keys

New documents open at **SELECT SYSTEM**. Choose a card with the arrows and press `ENTER` to confirm the system and open beam input. A failed calculation keeps the previous confirmed model and leaves the selector open with an error. `ESC` returns to the selector; while entering a number, the first `ESC` only cancels that edit. Documents saved on an existing input, diagram or section page reopen on that page.

| Key | System selector | Beam input | Diagrams / results | Material / section |
| --- | --- | --- | --- | --- |
| `TAB` | No effect | Diagrams | Material / section | Beam input |
| `↑` / `↓` | Choose row | Choose field | Move cursor; in results select L/250 or L/300 | Choose field |
| `←` / `→` | Choose column | Change support preset | Cycle M / V / w / results | Change material, profile or self-weight ON/OFF |
| `ENTER` | Confirm and open input | Apply numerical input | Open results; in results **EXPORT CAS** | Apply input or toggle selection |
| `ESC` | No effect | Cancel active edit; otherwise selector | Selector | Cancel active edit; otherwise selector |

In the input page: `L` and `a` in **m**, `q` in **kN/m**, `P` in **kN**, `EI` in **kN·m²**. Numerical `EI` is editable when material is `MANUAL`; catalogue EI displays `(auto)` beside its value. In the sections page, choose a material and either a steel profile or concrete dimensions. Use the calculator's normal document save command to retain settings.

### Deflection comparison and self-weight

The compact results view shows `|w|max` in **mm**, its position in **m**, `L/|w|` using consistent length units, and utilization `|w|max / (L / limit)` for both limits. Maxima include all segment boundaries and stationary points of the existing analytical deflection function; they do not depend on plot samples or cursor position. If equal absolute maxima exist, one maximizing position is reported. The selected comparison reports **OK**, **EXCEEDED**, or **N/A** for an undefined ratio (zero deflection). The default limit is L/250. These are user-selected comparison limits, not universal code-compliance certificates.

For **concrete cantilevers**, the comparisons use **`Lref = 2.5 × L`**, following DIN EN 1992-1-1/NA, NCI to **7.4.1(4)** ([official publication, PDF page 144](https://www.niedersachsen.de/download/140002/Nds._MBl._Nr._3_2019_vom_24.01.2019_Anlagenband_1-Teil_1.pdf#page=144)). The screen shows `Lref/|w|` and `Lref=2.5L (EC2/NA)`; utilization is `|w|max / (Lref / limit)`. **This changes the ratio and L/250 / L/300 utilization only for concrete cantilevers**, relative to v0.3.2. It does not change maximum deflection, reactions, moments or exported `bx_` values. The three other support presets continue to use `Lref = L` for every material.

For **steel or MANUAL cantilevers**, `Lref = L` remains the comparison reference and the screen displays **CANTILEVER: AGREE LIMIT**. Cantilever deflection limits must be agreed for the project or supplied by the applicable National Annex; EN 1993-1-1, **7.2**, does not supply a universal equivalent cantilever span. L/250 and L/300 are comparison settings here, not asserted normative cantilever limits.

Choose **Self-weight** on the section page and press `ENTER` or `←` / `→` to switch it ON/OFF. Steel uses `mass [kg/m] × 9.81 / 1000`; concrete uses `25 × (b/1000) × (h/1000)`, both in **kN/m**, positive downward. Input `q user` remains separate; each solve uses `q total = q user + q sw` only when ON. The results view shows available `q sw`, the ON/OFF state and the applied `q total`. With OFF, the displayed available self-weight is not added. Recalculation, section changes and restore never accumulate it. Manual EI or missing weight data show **N/A** and force self-weight OFF. Old saves default to OFF and L/250; both settings persist in new saves.

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

- **One span only.** Not a general 2D frame, continuous-beam, seismic or dynamic solver. No multiple load points, partial/trapezoidal UDL, thermal or prescribed displacements.
- Linear, small-deflection, prismatic Euler–Bernoulli analysis; self-weight is included only when explicitly switched ON. No load combinations or resistance checks.
- **Concrete:** `Ecm` with **gross uncracked** rectangular inertia only. Displayed deflections are **not** cracked/creep-adjusted reinforced-concrete service deflections. No reinforcement or EC2 design verification.
- Steel profile values are nominal and not geometric/material strength checks; neither steel nor concrete code verification is performed.
- Point loads extremely close to a support can trigger the existing ill-conditioning guard; a point at an exact end is supported.
- If `P != 0`, changing `L` below the existing position `a` is rejected until `a` is adjusted.
- No warranty of fitness for structural design: independently verify results for engineering use.

## Source layout

```text
BeamCX/
├── src/
│   ├── beam_core.lua       # Solver and result recovery
│   ├── frame_core.lua (v0.4-P1C, not yet used by the app)
│   ├── section_db.lua      # Offline materials, IPE / HEA Iy and mass
│   └── beam_ui.lua         # TI-Lua painting, keys, persistence
├── tests/
│   ├── test_port.py        # Beam calculations + UI smoke test
│   ├── test_catalog.py     # EI, materials, inputs and persistence
│   ├── test_plot_sign.py   # M/V/w plotting conventions
│   ├── test_arrows.py      # One filled arrowhead per load
│   ├── test_quick_check.py # Quick Beam Check harness
│   ├── test_selector.py    # Visual selector, reference moments, Esc, restore
│   ├── test_v033.py        # Signed loads, text bounds, Lref, CAS regression
│   └── quick_check.lua     # Analytical checks, self-weight, CAS, UI / persistence
├── .github/workflows/ci.yml
├── build.py                # Bundle to BeamCX.lua
├── CHANGELOG.md
└── README.md
```

The Python tests use standard library `ctypes` to execute actual Lua code against `liblua5.4.so.0` and a stub TI graphics canvas. `quick_check.lua` also runs directly under **Lua 5.1**. For v0.3.3, all seven suites' Lua scripts passed under Lua 5.4 and Lua 5.1.5; the generated bundle passed the Lua 5.1 syntax check and Luna packaging. Drawing checks cover 318×212, 320×212 and 320×240, with simulated font metrics. On the calculator, load clearance uses `gc:getStringHeight`; without it, a 10 pt font plus a fixed 4 px text-box margin is used. These checks do not replace physical-device validation.

## Data references

- Concrete `Ecm` (30 / 31 / 33 GPa): [Betontechnische Daten](https://www.betontechnische-daten.de/de/betontechnologie/formaenderungen/elastische-verformung).
- Steel modulus: `210 GPa` for both S235 and S355, standard EN 1993 elastic convention.
- Nominal IPE / HEA strong-axis properties: [crosssections.app IPE](https://crosssections.app/en/guides/ipe-complete-guide) and [HEA](https://crosssections.app/en/hea). Values are statically embedded in `src/section_db.lua`.
- Steel mass per metre: **ArcelorMittal, Sections and Merchant Bars, 2021 Sales Programme**, column `G [kg/m]`, IPE and HE A tables ([manufacturer PDF](https://sections.arcelormittal.com/repository2/Sections/Sections_MB_ArcelorMittal_FR_EN_RU.pdf), PDF pages 48/50 and 56/58). HE A corresponds to the app's HEA names. All 21 catalogue masses are embedded alongside the unchanged `Iy` values; e.g. IPE 200 = **22.4 kg/m**, HEA 200 = **42.3 kg/m**.
- Concrete self-weight: documented nominal assumption **25 kN/m³** for normal-weight concrete sections, including a conventional reinforcement allowance. It is not inferred from concrete grade or reinforcement quantity.

## License

MIT — see [LICENSE](LICENSE).

## Development note

The beam formulation was adapted for a restricted single-span TI-Lua application using Euler–Bernoulli frame-element stiffness terms; it is **not** a complete port of the original `dinamica-computacional` project. Existing numerical mechanics have not been changed as part of packaging this repository.
# BeamCX
