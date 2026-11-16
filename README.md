# BeamCX

**Lightweight 2D Euler–Bernoulli beam calculator for the original TI-Nspire CX CAS (color screen).**
TI-Lua 5.1 app for one prismatic beam span, with support presets, load diagrams, deflection, and a small offline material/section catalogue. No Ndless, Python, network connection, or extra libraries are required **on the calculator**.

Version: **0.2.3**. A small teaching / engineering-check tool, **not** a design-code verifier.

## Features

- One horizontal span with four boundary-condition presets: pinned–pinned, fixed–free, fixed–fixed, fixed–pinned.
- Uniform load `q` (kN/m) and one point load `P` (kN) at position `a` (m); positive applied loads act downwards.
- Reaction forces; shear `V`, bending moment `M`, and elastic deflection `w` plots, with movable cursor and displayed extrema.
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
make -C ~/Luna

# From the root of this BeamCX repository:
python3 build.py
for test in tests/test_*.py; do python3 "$test"; done
~/Luna/luna BeamCX.lua BeamCX.tns
```

The generated `BeamCX.tns` can be transferred using [N-Link Web](https://n-link.lights0123.com/) in Chrome/Chromium. Open it under **My Documents** on the TI-Nspire. The generated `.lua` and `.tns` files are ignored by Git. **Do not use** N-Link's *Upload OS* button for a `.tns` document.

Supported target / hardware history: original TI-Nspire CX CAS with OS **4.5.5.79**. Earlier BeamCX versions were observed running on hardware. The **v0.2.3 load-arrow rendering** has not yet been confirmed on physical hardware; this repository's tests simulate drawing calls, not LCD pixels.

## Keys

| Key | Beam input | Diagrams | Material / section |
| --- | --- | --- | --- |
| `TAB` | Next page | Next page | Next page |
| `↑` / `↓` | Choose field | Move result cursor | Choose field |
| `←` / `→` | Change support preset | Change M / V / w | Change material or steel profile |
| Numbers then `ENTER` | Apply numerical input | — | Apply b, h, or manual EI |

In the input page: `L` and `a` in **m**, `q` in **kN/m**, `P` in **kN**, `EI` in **kN·m²**. Numerical `EI` is editable when material is `MANUAL`. In the sections page, choose a material and either a steel profile or concrete dimensions. Use the calculator's normal document save command to retain settings.

## Example / sanity check

Pinned–pinned beam, `L = 6 m`, uniform `q = 10 kN/m`, `P = 0`:

- Left and right reactions: **30 kN** each.
- Maximum sagging moment at midspan: **45 kN·m**.
- For `EI = 10,000 kN·m²`, midspan deflection: **−16.875 mm** (negative means downward in the model).

The same beam with S235 and IPE 200 uses `E = 210,000 MPa` and `Iy = 1,943 cm⁴`, giving `EI = 4,080.3 kN·m²`.

## Scope and limitations

- **One span only.** Not a general 2D frame, continuous-beam, seismic or dynamic solver. No multiple load points, partial/trapezoidal UDL, thermal or prescribed displacements.
- Linear, small-deflection, prismatic Euler–Bernoulli analysis; no self-weight is added automatically.
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
│   ├── section_db.lua      # Offline materials, IPE / HEA Iy
│   └── beam_ui.lua         # TI-Lua painting, keys, persistence
├── tests/
│   ├── test_port.py        # Beam calculations + UI smoke test
│   ├── test_catalog.py     # EI, materials, inputs and persistence
│   ├── test_plot_sign.py   # M/V/w plotting conventions
│   └── test_arrows.py      # One filled arrowhead per load
├── .github/workflows/ci.yml
├── build.py                # Bundle to BeamCX.lua
├── CHANGELOG.md
└── README.md
```

The tests use Python standard library `ctypes` to execute actual Lua code against `liblua5.4.so.0` and a stub TI graphics canvas. On-device runtime uses **TI-Lua 5.1**: automated CI is a compatibility-adjacent test, **not** a replacement for a real 5.1 interpreter or a physical-device check.

## Data references

- Concrete `Ecm` (30 / 31 / 33 GPa): [Betontechnische Daten](https://www.betontechnische-daten.de/de/betontechnologie/formaenderungen/elastische-verformung).
- Steel modulus: `210 GPa` for both S235 and S355, standard EN 1993 elastic convention.
- Nominal IPE / HEA strong-axis properties: [crosssections.app IPE](https://crosssections.app/en/guides/ipe-complete-guide) and [HEA](https://crosssections.app/en/hea). Values are statically embedded in `src/section_db.lua`.

## License

MIT

## Development note

The beam formulation was adapted for a restricted single-span TI-Lua application using Euler–Bernoulli frame-element stiffness terms; it is **not** a complete port of the original `dinamica-computacional` project. Existing numerical mechanics have not been changed as part of packaging this repository.
# BeamCX
