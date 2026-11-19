# Development

User instructions are in the [README](../README.md); numerical qualification and device observations are in [VALIDATION](VALIDATION.md).

## Repository layout

```text
src/
  frame_core.lua          shared Euler–Bernoulli frame engine
  beam_preset.lua         single-span model, signs and summary
  continuous_preset.lua   continuous bases and envelopes
  portal_preset.lua       rectangular-portal model and recovery
  section_db.lua          offline properties and self-weight
  beam_ui.lua             shared state, events, calculation, CAS and persistence
  beam_ui_single.lua      single-span presentation
  beam_ui_continuous.lua  continuous presentation
  beam_ui_portal.lua      portal presentation
  beam_ui_sections.lua    shared material/section presentation
build.py                  deterministic static inclusion
tests/                    numerical fixtures, references, UI harnesses and renderer
tools/                    packaging, independent benchmark and reference generators
docs/images/              documentation PNGs; hardware/ only for supplied photographs
artifacts/                ignored local contact sheets
```

The generated `BeamCX.lua`, `BeamCX.tns`, `bench.lua` and `BXBENCH.tns` are ignored by Git. The application is a single statically concatenated Lua chunk; presentation includes share the entry point's lexical locals. There is no runtime module loader on the calculator.

## Dependencies and Luna

On Debian, install the compiler/runtime, reference and rendering dependencies:

```bash
sudo apt install build-essential zlib1g-dev python3 liblua5.4-0 lua5.1 python3-sympy python3-pil fonts-dejavu-core
git clone https://github.com/ndless-nspire/Luna.git ~/Luna
git -C ~/Luna checkout a9924a9
make -C ~/Luna
```

The established [Luna](https://github.com/ndless-nspire/Luna) revision is `a9924a9a968954eba9adcc161a58ac607f97ce8c`. The existing CI installs SymPy **1.13.3**. Tests load liblua **5.4** through ctypes; the CLI runner executes their same Lua chunks with **lua5.1**. Pillow and DejaVu fonts are required only for rendering on the PC.

## Build, test and package

From the repository root:

```bash
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
```

`build.py` preserves the numerical module order and expands explicit presentation markers before callbacks in the UI chunk. `tools/package.py` invokes `~/Luna/luna`; its optional `--luna` selects another executable. It rejects unsafe USB closing-packet sizes, appends a comment only to generated Lua when necessary, and retries within its existing bound. Do not bypass it for distribution. Compression affects package size, so record the actual TNS size/hash and test that artifact on the calculator.

## Architecture

- One shared Frame engine assembles, solves and recovers every application model.
- Presets are the boundary for input signs, supported model families and semantic summaries; the UI does not duplicate mechanics.
- UI presentation is separated by system, with shared section rows/editing and central state, events, cache lifetime, rollback and export.
- Persistence accepts only the exact current document version, validates atomically and has no migration; portal EI comes from the saved section groups.
- Lua **5.1** compilation limits are **200 locals per function** and **60 upvalues**. Inspect the generated chunk with `luac5.1 -p -l -l BeamCX.lua`; source file boundaries do not reset lexical scope.

CAS export uses TI's `var.store` API: nil means success; a returned error or exception stops later writes. The PC harness supplies a test double rather than a calculator CAS connection.

## Benchmark

The benchmark has its own bundle and never rewrites the application:

```bash
python3 tools/build_bench.py
luac5.1 -p bench.lua
lua5.1 -e "dofile('bench.lua').pc()"
python3 tools/package.py --bench
```

Transfer `BXBENCH.tns` using a plain filename in the root folder. It starts automatically, yields between operations and excludes painting from timing. Its existing rows cover the general solver, complete continuous envelopes and the portal, with separate recovery-query timings. Arrow keys change pages. The oversized general models report the current node guard.

On the calculator it uses [`timer.getMilliSecCounter()`](https://education.ti.com/html/eguides/nspire/eg_nspire/en/content/eg_lua/m_libraries/timerlib/getmilliseccounter.HTML), handling rollover; on the PC it uses CPU `os.clock()`. Measurements use at least **three** repetitions and target **200 ms** accumulated time, with a maximum of **4096** repetitions. Recorded PC timings are not predictions of calculator responsiveness.

## Offline references

Ordinary tests consume versioned fixtures and require no external checkout or service:

```bash
python3 tests/test_frame_core.py
python3 tests/test_beam_preset.py
python3 tests/test_continuous_preset.py
python3 tests/test_portal_preset.py
python3 tests/test_dc_reference.py
```

[`tools/adjudicate_beam_golden.py`](../tools/adjudicate_beam_golden.py) reproduces the independent **60-digit** mpmath adjudication. [`tools/dc_reference.py`](../tools/dc_reference.py) generates the separate Euler reference using NumPy and a local `dinamica-computacional` checkout:

```bash
python3 tools/adjudicate_beam_golden.py --output /tmp/beam-adjudication-review.json
python3 tools/dc_reference.py ~/dinamica-computacional --output /tmp/dc-reference-review.json
```

These are reference-generation tools, not routine test prerequisites. Preserve the historical fixtures; do not replace expected results with current application output. The legacy live beam generator has been retired; its retained input provenance is not a second productive solver.

## Documentation images

Reuse the existing recorder and rasterizer:

```bash
python3 build.py
python3 tests/render_portal_ui.py --docs
python3 tests/render_portal_ui.py --docs selector portal-moment cas-export
python3 tests/render_portal_ui.py
```

`--docs` without scene names regenerates every documentation image in `docs/images/`; a list regenerates just those named scenes. The default mode preserves the existing contact sheet, now written to ignored `artifacts/PORTAL_UI_CONTACT.png`.

| Scene names | Route |
| --- | --- |
| selector | Fresh application |
| single-moment, single-deflection | PIN-PIN results / compact comparison |
| sections-steel | Shared section page, S235, IPE 300, self-weight ON |
| continuous-input, continuous-envelope, continuous-table | Default continuous input / M / support table |
| portal-input, portal-moment, portal-deformed | Default portal input / M / deformation |
| portal-sections, portal-results | HEA 200 S235 columns / IPE 300 S235 beam, self-weight ON; Beam group / provenance |
| cas-export | Default portal table, explicit export to the PC test double |

Scenes use the bundled application through `tests/load_ui.lua`, actual `on.*` events and the existing read-only snapshot for assertions. They do not restore synthetic documents or assign application state. The recorder checks viewport bounds and text overlap. CAS export uses a test double for `var.store`, checks numeric stores/count and captures the application's actual success message; it does not establish hardware CAS behavior.

Each PNG is **636×424**, the **318×212** canvas at **2×**, without contact-sheet titles. Optimized files are limited to **40 KB** each and **600 KB** in total. Byte reproducibility is checked in the same Python/Pillow/font environment, not across operating systems or graphics-library versions. Review all rendered scenes for readability, correct units, clipping and agreement with current behavior.

If the RGB PNG exceeds the per-image budget, the same rasterizer saves an optimized indexed palette without dithering; drawing geometry and text still come from the recorded application commands.

Photographs belong in `docs/images/hardware/` only when supplied. Before publishing a photograph, resize to at most **1200 px** wide and remove all EXIF/GPS metadata; use at most **three** in the README and identify them as real calculator photographs. Simulated images do not substitute for photographs or device acceptance.
