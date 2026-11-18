# BeamCX v0.5 — P5A, cálculo de vigas continuas

2026-11-18. **P5A IMPLEMENTADO / PASS en PC.** Sin interfaz de vigas continuas, sin commit ni push. La aplicación v0.4.0 validada por el propietario sigue idéntica; P5B queda a cargo de interfaz, selector y validación en CX.

## Alcance y cambios autorizados

La limpieza BUILD-ZNG-R1 ya estaba hecha. Se completó el ajuste previo de una línea del mensaje final de `build.py`: `Package with: python3 tools/package.py`. No se cambió su concatenación ni se ejecutó para regenerar la aplicación.

`MAX_NODES` permanece en 20. En Frame se añadió `combine` y se cambió la firma de `deflection_extrema` según la aclaración expresa del propietario. Su búsqueda usa una sola vez los mismos candidatos; el ensamblaje, solución, recuperación, raíces, signos y tolerancias anteriores permanecen iguales. Se adaptaron BeamPreset y los seis usos originales de los tests, sin cambiar valores esperados. No hay funciones solo para tests en `src/`.

Las comparaciones SHA-256 con el inicio confirman que **BeamCX.lua, BeamCX.tns, beam_ui.lua, section_db.lua y todos los fixtures numéricos están intactos**. La aplicación conserva sus ocho `bx_*`; P5A no introduce nombres CAS.

## API final

```lua
Frame.combine(solutions, factors) --> combined | nil, 'incompatible solutions: <reason>'
Frame.deflection_extrema(sol, member) --> wmin, xmin, wmax, xmax
ContinuousPreset.MAX_SPANS --> 5 (provisional)
ContinuousPreset.model(p, 'G' or span_index) --> model | nil, message
ContinuousPreset.solve(p) --> result | nil, message
result.envelope_at(global_x, side) --> {Mmax, Mmin, Vmax, Vmin}
```

`combine` exige igualdad exacta de nodos, conectividad, EI/EA, apoyos/desplazamientos prescritos, resortes, rótulas y cortes. Superpone desplazamientos, reacciones, fuerzas de extremo y coeficientes de recuperación V/M/w/theta/qa/g/kappa. No ensambla, no resuelve y no modifica operandos. El resultado es independiente de sus tablas de entrada; los diagnósticos de los solves originales no se presentan como una nueva comprobación del combinado (`checks` se omite, salvo en la identidad con un factor 1).

`p` contiene `spans`, `left`, `right`, `g`, `q`, `EI`, factores opcionales `gG_sup=1.35`, `gG_inf=1`, `gQ=1.5` y `limit=250|300` (250 por defecto). Admite 2–5 luces positivas, PIN/FIX en ambos extremos, un EI y cargas uniformes por vano completo. El llamador incorpora el peso propio una sola vez en g. No hay cargas puntuales ni voladizos. Los apoyos intermedios restringen el desplazamiento vertical y mantienen la continuidad del giro; no son rótulas internas de barra.

Un único conversor cambia las cargas de entrada y la flecha al convenio positivo hacia abajo. Frame mantiene sus propios signos: M sagging positivo, R hacia arriba y w local hacia arriba. Longitudes y flechas del resultado continuo están en **m**, fuerzas en kN, momentos en kNm y EI en kNm².

`solve` hace **exactamente n+1 solves**, incluso con cargas cero: G sobre todos los vanos y una base Qi por vano. Recorre todos los 2^n patrones, sin regla de alternancia:

- ELU: 2·2^n combinaciones, con un mismo gammaG para todos los vanos en cada combinación.
- Flecha característica: otras 2^n combinaciones, con factores unitarios. Total: 3·2^n llamadas a `Frame.combine`, sin solves adicionales.
- Los extremos M y w proceden de las funciones de Frame; |V| usa los dos límites de cada vano, exactos para las UDL del preset. Los 101 puntos pertenecen a la verificación y al benchmark de consulta, no a la búsqueda de extremos.

El resultado expone `parameters`, `bases`, `spans`, `supports`, `shear`, `summary`, `deflection_label='w car.'` y `factor_convention.status='OPEN'`. La convención de factores queda pendiente de verificar contra EN 1990 Anexo A1 y su NA; no se declara cumplimiento normativo.

Cada vano contiene `Mmax` algebraico, `Mplus` positivo o nil, y `deflection.down`, `.up`, `.governing`, `.ratio`, `.utilization.L250/L300`, `.selected_limit` y `.status`. Cada apoyo contiene Mmin/Rmax/Rmin. Los registros llevan `value`, `absolute`, `x` local, `position` global, `pattern` (p. ej. `1-3`, o `-` sin q) y `gammaG` cuando corresponde. La flecha hacia arriba tiene valor negativo. Lref es siempre la luz individual del vano.

El resumen semántico tiene ocho campos: `moment_max`, `moment_min`, `shear_absolute_max`, `reaction_max`, `deflection_absolute_max`, `deflection_position`, `rigidity`, `span_count`. P5B decidirá el prefijo de exportación.

## Referencia y oráculos

`tests/continuous_reference.py` es una referencia propia en Python/SymPy **sin Lua ni Frame**. Resuelve la rigidez exacta en racionales con solo giros nodales, calcula reacciones y polinomios de cada vano, aísla las raíces de la derivada y recorre por fuerza bruta todos los patrones y ambos gammaG. Se usó SymPy 1.13.3.

| Grupo de comprobaciones | Máximo error normalizado observado, ambas versiones Lua |
| --- | ---: |
| A/B/C, posiciones por valor, simetría y testigo redondeado de levantamiento | 3,72e-14 |
| D: valores, patrones, ELU, arriba/abajo y 101 puntos/vano | 1,31e-15 |
| E: valores, patrones, simetría y 101 puntos/vano | 1,22e-15 |
| Cinco vanos 3/5/4/6/2 m, FIX-FIX, contra referencia | 1,95e-15 |
| `combine`, incluyendo recuperación general | 4,59e-15 |

Se usan escalas por magnitud con el piso de referencia P2A y tolerancia 1e-9; las posiciones se validan por el valor físico alcanzado. Las seis comparaciones directas de combinación en D/E usan **1e-12**, incluidos reacciones, M/V/w en 101 puntos y extremos. También se verifican identidad con factor 1, inmutabilidad de operandos y un caso con axial, rótula, resorte, temperatura y cortes que activa todos los coeficientes superpuestos. Se rechazan cortes/nudos/EI/EA/resortes/rótulas incompatibles y factores inválidos.

El vano 1 de D gobierna **hacia arriba**, 4,20398173154e-4 m, x local 3,01724728039 m y patrón `2`; la regresión lo exige explícitamente. Se verifican los otros levantamientos de D y el de 3,375e-3 m del vano central de E. El patrón C `1-3` conserva Mmax central = -18; un caso adicional continuo con vano central corto exige `Mplus=nil` cuando el máximo algebraico es negativo. PIN-FIX se contrasta con el espejo de D. Hay pruebas de cargas cero, límites L/250/L/300 y entradas inválidas.

**12/12 suites pasan en Lua 5.1.5 y Lua 5.4.7**: las once existentes más la nueva. Las 394 filas conservan exactamente sus identificadores y valores esperados; los barridos P1C.1 permanecen. La equivalencia de 2.042 entradas pasa tanto en el bundle v0.4.0 congelado como, reutilizando las mismas aserciones, en los módulos Frame/BeamPreset actualizados: 2.009 ordinarias, dos adjudicadas, cinco RESOLVED y 26 inválidas. Su máximo error normalizado sigue dentro de 1e-9.

Comandos ejecutados:

```bash
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/test_continuous_preset.py
python3 tests/test_continuous_preset.py --lua lua5.1
python3 tools/build_bench.py
luac5.1 -p bench.lua src/frame_core.lua src/beam_preset.lua src/continuous_preset.lua
python3 tools/package.py --bench
```

## BXBENCH: medición PC y paquete

Medición con el benchmark generado, **Lua 5.1.5, os.clock (CPU)**, Intel Core i5-8300H/x86_64. Cada fila mide el cálculo completo n+1 bases + todas las combinaciones ELU/características + extremos. Se mantiene el procedimiento existente de al menos tres repeticiones y objetivo 200 ms acumulados.

| Vanos | Solves por cálculo | ELU / características | Cálculo completo medio PC | Repeticiones | 101 consultas de envolvente |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 | 3 | 8 / 4 | 7,803 ms | 26 | 0,801 ms |
| 3 | 4 | 16 / 8 | 24,110 ms | 9 | 1,068 ms |
| 4 | 5 | 32 / 16 | 98,177 ms | 3 | 2,305 ms |
| 5 | 6 | 64 / 32 | 283,525 ms | 3 | 1,767 ms |

Son tiempos de esta ejecución PC, no estimaciones de la CX. Las filas originales se conservan; las de 40/60 nudos muestran la guardia existente de 20 y no impiden medir las envolventes. Una prueba del arnés con reloj TI simulado comprobó las diez filas, rollover, corutinas y navegación entre dos páginas a 318×212. No es validación física.

`BXBENCH.tns` se empaquetó con Luna a9924a9 y la guardia USB de `tools/package.py --bench`: **17.392 bytes**, último paquete **205 bytes**, sin relleno necesario. SHA-256: `30bd8620b24b717a467d0cb033c6f4752470098d3d6a8474a28b0612127618dd`.

## Excepción de llamador productivo hasta P5B

Sin llamador en la aplicación v0.4.0 quedan **Frame.combine** y la API de **ContinuousPreset.model / ContinuousPreset.solve**, incluido el `result.envelope_at` que devuelve. Sus consumidores actuales son los tests y el benchmark. Esta es la excepción deliberada de P5A; no se añadió una ruta oculta a la UI ni un sistema nuevo al selector.

El propietario medirá BXBENCH en la CX. P5B fijará MAX_SPANS y decidirá si el cálculo requiere ejecución diferida y un mensaje de progreso. P5A no toma esas decisiones ni afirma validación hardware.
