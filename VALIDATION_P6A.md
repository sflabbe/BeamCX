# P6A — STOP por precisión de Frame

2026-11-18. **P6A incompleta, sin commit ni push.** El barrido encuentra un
incumplimiento de la tolerancia exigida de 1e-9 en una llamada directa a
`Frame.solve`. Se aplica la orden de detenerse si aparece un defecto en el
motor. No se cambia el motor, la tolerancia ni el caso aleatorio.

## Bloqueo reproducible

Caso `random 44 PIN`, semilla `20261118`, dentro del intervalo solicitado de
geometría; EI aleatorios entre 1.000 y 100.000 kN·m²:

```lua
{h=7.992534030399157, l=7.2414618540177935,
 EIc=1287.6981033157158, EIb=70290.77027682829, base='PIN',
 q=-16.925034043679595, P=33.30253354749232, a=4.149634493859181,
 H=-23.25986592984502, w=2.630958639145323}
```

Se conserva EA=1e6·EI/L². El modelo directo tiene los cuatro nudos y las tres
barras indicados en P6A, q_local=-w en la barra 1, q_local=-q y P_local=-P en
la barra 2, H global en el nudo 2, y bases PIN en los nudos 1 y 4.

| Deriva [m] | Referencia Python, Decimal 50 dígitos | Frame, Lua 5.1.5 y 5.4.7 |
| --- | ---: | ---: |
| Nudo 2 | -0,67617410135640876192007845757344 | -0,67617409999015043 |
| Nudo 3 | -0,67617407312534330508360580955816 | -0,67617407175908506 |

Error relativo en el nudo 2: **2,02057e-9 > 1e-9**. Ambos intérpretes producen
los mismos resultados al resolver el modelo directamente, sin cargar
`portal_preset.lua`. Una segunda resolución racional de las ecuaciones de la
referencia con SymPy coincide con Decimal con diferencia relativa 4,57e-43.
La discrepancia se reproduce en el motor congelado; no se ha modificado ni
investigado una corrección de su factorización.

Frame acepta el modelo con `equilibrium_relative=3,69302e-10`,
`residual_relative=3,42720e-11` y `compatibility_relative=5,33454e-16`.
Esos controles no garantizan el error de desplazamiento de 1e-9 solicitado.

Reproducción persistente:

```bash
python3 tests/test_portal_preset.py
```

La suite termina con `random 44 PIN drift` y conserva la comparación fallida.
El diagnóstico directo se ejecutó también en Lua 5.1.5 y liblua 5.4.7.

## API implementada, pendiente de validación completa

- `PortalPreset.model(p)` devuelve el modelo o `nil, mensaje`. Exige h, l,
  EIc y EIb positivos y finitos; base PIN/FIX; q, P, a, H y w finitos;
  0 ≤ a ≤ l. Todos los campos son obligatorios, también las cargas cero.
- `PortalPreset.solve(p)` hace una llamada a Frame.solve y devuelve el
  resultado o `nil, mensaje`.
- `PortalPreset.at(sol, member, s, side)` y `sol.at(member, s, side)` delegan
  en Frame.at. Por defecto usan el lado izquierdo salvo en s=0, donde usan
  el derecho. Devuelven N, V, M, w y u en unidades de Frame.
- `sol.reactions.left/right`: H global hacia la derecha, V hacia arriba,
  M antihorario en FIX; M ausente en PIN.
- `sol.members[i].moments.minimum/maximum`: `{value, position}`;
  `sol.members[i].axial`: `{value, absolute, position}`, tracción positiva.
  N es constante por barra y su posición representativa es 0.
- `sol.corners.left/right`: momentos `column` y `beam` en cada esquina,
  conservando los signos locales de cada barra.
- `sol.drift.left/right`: desplazamientos horizontales de nudos 2/3 en m.
- `sol.deflection`: `{value, absolute, position}` de la máxima flecha absoluta
  de la viga relativa a su cuerda; value positivo hacia arriba, en m.
- `PortalPreset.deflection_extrema(sol)` calcula ese extremo. Divide en los
  cortes de P y en las raíces de M; aísla las raíces de theta-pendiente_cuerda
  en intervalos monótonos. Evalúa Frame.at en los candidatos, incluidos los
  nuevos estacionarios introducidos por la corrección lineal.
- `PortalPreset.summary(sol)` y `sol.summary`: `reactions`, `member_extrema`,
  `corner_moments`, `drift`, `beam_deflection`; sin prefijo de exportación CAS.

Convención M>0: tracciona la fibra local -y. En la columna izquierda 1→2 y
la derecha 4→3 esa fibra queda a la **derecha global**; en la viga 2→3 queda
**abajo**. N positivo significa tracción; V=dM/ds; w es desplazamiento local +y.

EA=1e6·EI/L² es una aproximación exclusiva de la plantilla, sin garantía
universal de error. Los seis testigos muestran diferencias de orden 1e-5
frente a las fórmulas sin deformación axial, con tolerancia 5e-5.

## Seis oráculos ejecutados

Máximos relativos entre los valores de cada fila, incluidas ambas bases
cuando procede, ambas derivas y los valores complementarios indicados:

| Caso | Fórmula / magnitud esperada | Lua vs expresión analítica | Lua vs Python con EA finito |
| --- | --- | ---: | ---: |
| PIN q=10 | \|H\|=4,5 | 1,35000e-6 | 0 |
| FIX q=10 | \|M_base\|=10; \|M_esquina\|=20 | 1,34999e-5 | 5,32907e-16 |
| FIX P=20, a=3 | \|M_base\|=5 | 1,34999e-5 | 5,32907e-16 |
| FIX H=10 | \|M_base\|=80/7 | 9,01781e-6 | 2,76434e-12 |
| PIN w=10 | \|H_sotavento\|=11; \|H_barlovento\|=29 | 1,35000e-6 | 5,22717e-12 |
| PIN H=10 | deriva=0,016 m | 5,80555e-6 | 4,92922e-12 |

Error analítico máximo: **1,34999e-5**; error máximo frente a la referencia
finita de esos seis testigos: **5,22717e-12**. Los signos se comprueban aparte
mediante cargas locales, saltos, resultantes y equilibrio global.
**Atribución documental Kleinlogel OPEN**: no se dispone de fuente primaria
con edición, forma y página; las expresiones proceden del prompt del dueño.

## Validación y archivos

La suite preparada contiene 136 modelos: seis testigos, casos individuales
con ambos signos, dos combinados, ceros, puntos en/cerca de extremos,
regresiones asimétricas de cuerda y 50 geometrías aleatorias con ambas bases.
Compara reacciones, deriva, N/V/M/w en 21 puntos por barra y ambos límites
cuando existen, extremos de momento y flecha relativa contra Python.
Comprueba Fx, Fy y Mz por separado con las cargas físicas; incluye simetría,
entradas inválidas y exactamente un solve por modelo. **La suite completa
no pasa** por el caso documentado; no se afirma cobertura ejecutada de los
casos posteriores al fallo.

La referencia Python usa rigidez directa con tres GDL por nudo, sin Lua,
Decimal de 50 dígitos y aislamiento racional de raíces para la flecha relativa.
No se añadieron funciones de prueba en src/.

Comandos completados:

```bash
python3 tests/test_portal_preset.py  # FAIL descrito arriba, Lua 5.4.7
python3 tools/build_bench.py
luac5.1 -p bench.lua src/portal_preset.lua
python3 tools/package.py --bench
sha256sum -c /tmp/p6a-frozen.sha256
git diff --check
```

El benchmark incorpora `portal FIX q+P+H+w` mediante la API completa de la
plantilla. Se actualizaron tools/bench_ti.lua, tools/build_bench.py y bench.lua;
`BXBENCH.tns` se reempaquetó: **19.865 bytes**, último paquete USB **148 bytes**.
**Tiempo PC pendiente**: no se ejecutó la medición tras confirmar el STOP.
La medición CX corresponde al dueño.

No se ejecutaron el CI completo ni todas las suites en ambos Lua después
del bloqueo. Las 394 filas, los 2042 casos y la fuerza bruta de continuas
permanecen intactos; no se afirma una nueva validación completa de ellos.

Las sumas SHA-256 confirman idénticos frame_core.lua, beam_preset.lua,
continuous_preset.lua, build.py, BeamCX.lua y BeamCX.tns. La UI está intacta.
PortalPreset solo tiene llamadores de prueba y benchmark; carece de llamador
productivo hasta P6B, la excepción expresamente autorizada. Los cambios
parciales se conservan para revisión. **Sin commit, sin push. STOP.**
