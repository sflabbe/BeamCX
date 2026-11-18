# P5A.1 — envolvente exacta por tramos

2026-11-18. Se sustituye el recorrido exponencial de P5A en `src/continuous_preset.lua`. La aplicación v0.4.0 sigue intacta; la interfaz continúa fuera de alcance. Sin commit ni push.

## Cálculo

Se conservan exactamente **n+1 solves** (G y Qi). Reacciones Rmax/Rmin, momentos Mmax/Mmin de apoyos, cortantes en los extremos de cada vano y consultas `envelope_at` usan la suma directa de contribuciones con su signo favorable/desfavorable. Un único gammaG se elige entre los dos factores globales para cada resultado; se reportan ese factor y los vanos con contribución activa.

Para M por vano se construyen las bases cuadráticas desde `Frame.at(base, member, 0, 'right')` y la UDL. En la coordenada normalizada del vano se obtienen por fórmula estable las raíces interiores de G y cada Qi. Entre raíces el factor permanente y el conjunto Qi activo son constantes. Los únicos candidatos son extremos del tramo y vértice de la cuadrática combinada. No se muestrea ni se hace búsqueda iterativa de M, y no se usa alternancia para sus máximos/mínimos.

Cada vano expone ahora **Mmax algebraico, Mmin y Mplus** positivo o nil. Los apoyos exponen **Mmax y Mmin**, incluidos momentos positivos, además de Rmax/Rmin. Se conserva el resumen semántico sin nombres CAS y la convención de factores **OPEN**.

La flecha característica conserva máximos hacia abajo/arriba y su comparación por vano, pero solo usa los dos patrones **impares/pares** con `Frame.combine` y `Frame.deflection_extrema`. Son **dos combinaciones en total**, independientemente de n. Es una **regla verificada, no un teorema**. Los barridos de 10.445 vanos sin diferencias para flecha y de 10.590 vanos con 827 fallos de alternancia para M proceden del addendum del propietario; aquí se ejecutó el contraste reproducible detallado abajo.

## Pruebas

La fuerza bruta vive exclusivamente en `tests/continuous_bruteforce.lua`, incorporado por el arnés de `test_continuous_preset.py`.

- **300 modelos aleatorios**, semilla Python `20261118`, mismos datos en ambos Lua: n=2..5, 75 modelos por tamaño, luces 2–10 m, extremos PIN/FIX, g/q entre 0 y 30 kN/m (incluidos ceros), EI entre 5.000 y 35.000 kNm² y límites 250/300.
- **1.050 vanos y 4.500 patrones**. Por cada patrón, el oráculo calcula una combinación característica y dos ELU mediante Frame.combine: **13.500 combinaciones exhaustivas** en el arnés.
- Se comparan Mmax/Mmin/Mplus por vano, Mmax/Mmin/Rmax/Rmin por apoyo, |V| global, envolventes M/V en cinco posiciones por vano, flecha arriba/abajo y gobernante, ratio/estado y resumen. Los patrones/gammaG y posiciones reportados se validan por la respuesta física que producen. La instrumentación exige n+1 solves y dos combinaciones en la ruta optimizada.
- Se mantienen D, E y cinco vanos FIX-FIX contra la referencia independiente racional de SymPy, con sus **101 posiciones por vano**, junto con A/B/C y las regresiones anteriores.

Tolerancia: 1e-9 con las escalas por magnitud y el piso P2A. Máximos normalizados observados:

| Magnitud | Lua 5.4.7 | Lua 5.1.5 |
| --- | ---: | ---: |
| Momentos | 2,99e-15 | 2,99e-15 |
| Cortantes | 4,84e-16 | 4,84e-16 |
| Reacciones | 2,19e-16 | 2,19e-16 |
| Flechas | 1,81e-15 | 1,81e-15 |
| Posiciones/patrones, por valor alcanzado | 4,67e-15 | 4,67e-15 |
| Resumen | 2,59e-15 | 2,59e-15 |

La regresión FIX-PIN con luces 6,741127285017325 / 3,043382368681142 / 9,32755849384785, g=12,111990602786538 y q=18,185486163687962 da **Mmax en B = +28,081141172746 kNm**, patrón **`3`**, **gammaG=1,00**; también coincide con la fuerza bruta. Este caso impide sustituir la envolvente de M por la regla de alternancia.

Las **12 suites** pasan con Lua **5.1.5** y **5.4.7**, conservando los 394 oráculos Frame, barridos P1C.1 y las 2.042 entradas de equivalencia. Frame, BeamPreset, `build.py`, UI, catálogo, fixtures, `BeamCX.lua` y `BeamCX.tns` no cambiaron respecto al inicio de P5A.1.

## BXBENCH actualizado

El benchmark muestra **P5A.1** y mide los mismos cuatro modelos y el mismo cálculo completo. CPU PC Intel Core i5-8300H, Lua 5.1.5, `os.clock`, al menos tres repeticiones y objetivo existente de 200 ms acumulados:

| Vanos | Solves | Combinaciones | Cálculo completo medio | Repeticiones | 101 consultas |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 | 3 | 2 | 2,987 ms | 68 | 1,159 ms |
| 3 | 4 | 2 | 5,607 ms | 36 | 1,491 ms |
| 4 | 5 | 2 | 8,955 ms | 23 | 1,873 ms |
| 5 | 6 | 2 | 13,084 ms | 16 | 2,204 ms |

Estos son tiempos PC de esta ejecución, no una estimación de la CX. Se comprobó también el arnés de corutinas/reloj TI simulado, rollover y dos páginas a 318×212. Las filas de 40/60 nudos siguen mostrando la guardia existente de 20.

`BXBENCH.tns`: **18.110 bytes**, último paquete USB **164 bytes**, sin relleno necesario; Luna **a9924a9** mediante `tools/package.py --bench`. SHA-256: `4d11eb037dc4f8e9bca8260582f996679eef56ccfd66eed203c5d825e4503221`.

Comandos ejecutados:

```bash
python3 tests/test_continuous_preset.py
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tools/build_bench.py
luac5.1 -p bench.lua src/continuous_preset.lua
python3 tools/package.py --bench
lua5.1 -e "dofile('bench.lua').pc()"
git diff --check
```

La invocación PC del benchmark se ejecutó por stdin, equivalente al último comando Lua indicado. La medición de este nuevo paquete en CX corresponde al propietario. MAX_SPANS sigue provisionalmente en 5; no se ha cambiado la UI ni se ha añadido cálculo diferido. Se mantiene la excepción P5A: Frame.combine y ContinuousPreset no tienen llamador en la aplicación hasta P5B.
