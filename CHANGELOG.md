# Changelog

All notable changes are documented here, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.6.1] — 2026-11-19

### Added

- First public release of the standalone TI-Nspire CX CAS calculator.
- Six systems: four single-span beam presets, continuous beams and rectangular portals.
- Offline MANUAL, concrete RECT and steel IPE/HEA sections, with independent portal Columns / Beam groups.
- Optional beam self-weight, including the portal beam; portal column self-weight is excluded.
- Continuous moment/shear/reaction envelopes, characteristic deflection and span/support tables.
- Portal N/V/M, magnified deformation, local member cursor and section/load provenance.
- Explicit CAS export in separate beam, continuous and portal namespaces.
- Strict document format 0.6.1, preserving full-precision input, sections and navigation; no migration from earlier formats.

### Fixed

- Closed the reference moment-diagram outlines at the portal selector's bases and corners.

## Pre-release development

- Introduced the single-span calculator, section catalogue and optional self-weight.
- Added support selection, signed load arrows, diagrams, cursor and deflection comparisons.
- Added concrete cantilever reference-length handling and full-precision CAS output.
- Unified calculation through the shared Euler–Bernoulli frame engine.
- Added continuous beams, exact piecewise moment envelopes and deferred cached drawing.
- Added rectangular PIN/FIX portals with characteristic loads and chord-relative deflection.
- Separated presentation by system and completed section-group editing, persistence and graphics regression.
