# P6A-R1 — CLOSED/PASS

2026-11-18. Se cierra la fase de cálculo P6A con los **136 modelos originales**,
los seis testigos analíticos y las **15 suites** en **Lua 5.1.5 y 5.4.7**.
La corrección del criterio de comparación queda exclusivamente en pruebas.
No cambian física, EA, motor, presets, UI ni aplicación v0.5.0. PortalPreset
permanece sin llamador productivo hasta P6B. Sin commit, push ni release.

## Fallo original y adjudicación

Se conserva el caso `random 44 PIN`, semilla `20261118`, sin excepción codificada:

```lua
{h=7.992534030399157, l=7.2414618540177935,
 EIc=1287.6981033157158, EIb=70290.77027682829, base='PIN',
 q=-16.925034043679595, P=33.30253354749232, a=4.149634493859181,
 H=-23.25986592984502, w=2.630958639145323}
```

| Deriva [m] | Python Decimal 50 dígitos | Frame, ambos Lua |
| --- | ---: | ---: |
| Nudo 2 | -0,67617410135640876192007845757344 | -0,67617409999015043 |
| Nudo 3 | -0,67617407312534330508360580955816 | -0,67617407175908506 |

La discrepancia original se reproduce: diferencia absoluta **1,36625833e-9 m**,
error relativo **2,02057181124e-9**, superior al antiguo 1e-9. También se había
reproducido con Frame.solve directamente, sin PortalPreset; la resolución
racional de SymPy coincidía con Decimal a 4,57e-43 relativo. Esa observación
motivó el STOP original, pero **no establece un defecto en Frame.solve**.

EA=1e6·EI/L² aproxima la deformación axial despreciable y separa las escalas
axiales y de flexión. El condicionamiento amplifica el redondeo binary64.
Se distinguen el error de aproximación respecto de las fórmulas clásicas y
el error numérico respecto del mismo modelo con EA finito. No se modifica
Frame para compensar la prueba.

## Condicionamiento, escalas y aceptación

La referencia conserva su ensamblaje independiente de 12 GDL, impone los
apoyos y extrae Kfree (8 GDL libres en PIN, 6 en FIX). Se calcula para cada
modelo **κ∞=||Kfree||∞·||Kfree⁻¹||∞**, usando la inversión racional de SymPy
como diagnóstico. La solución de referencia sigue siendo la misma eliminación
Decimal a 50 dígitos; no se introduce otro solucionador ni una dependencia
productiva. Kfree no procede de Frame.

Los GDL originales son traslaciones en m y giros en radianes, con las unidades
kN/m/kNm del modelo. El condicionamiento depende de unidades y escalado.
También se registra κ∞ de `S*Kfree*S`, con `Sii=1/sqrt(Kfree_ii)`; este valor
es informativo y **no interviene** en el criterio de aceptación.

| Diagnóstico de random 44 PIN | Valor |
| --- | ---: |
| κ∞ original, métrica de aceptación | 58.620.880,068742506 |
| κ∞ con escalado diagonal | 49.363.695,973835245 |
| epsilon binary64 | 2,220446049250313e-16 |
| κ∞·epsilon, estimación | 1,30164501552e-8 |
| Tolerancia de desplazamientos aplicada | 1,30164501552e-7 |
| Error de deriva observado | 2,02057181124e-9 — PASS |
| Residuo hacia atrás independiente | 6,07550967767e-17 |

El diagnóstico suministrado en R1 daba κ₂≈5,1e7 y κ₂·epsilon≈1,13e-8;
esos valores de norma 2 no se mezclan con la norma infinito usada aquí.
Ni κ·epsilon ni el multiplicador 10 son una cota rigurosa del error hacia
adelante: son una estimación y una heurística de aceptación acotada.

Solo los **desplazamientos de modelos aleatorios** emplean:

```python
EPS = 2.220446049250313e-16
base_tol = 1e-9
displacement_tol = max(base_tol, 10.0 * kappa * EPS)
# STOP si displacement_tol > 1e-6 o el error supera displacement_tol.
```

Esto incluye traslaciones y giros nodales, deriva, desplazamientos locales
recuperados u/w y flecha relativa. Los 36 modelos no aleatorios mantienen
1e-9 para desplazamientos. De los 100 aleatorios, **36 conservan 1e-9** y
64 emplean el término de condicionamiento. El máximo κ∞ aleatorio es el de
random 44 PIN y la máxima tolerancia aplicada es **1,30164501552e-7 < 1e-6**.
El máximo κ∞ de los 136 modelos es 1,53101970841e8 (`asymmetric chord PIN`),
que conserva 1e-9 y pasa; su término hipotético 10·κ∞·epsilon tampoco excede
1e-6. Ningún modelo sale del dominio de calificación.

**Reacciones, N, V, M, extremos de momento, recuperación y equilibrio Fx/Fy/Mz
conservan 1e-9**, sin excepciones. Los seis testigos conservan 5e-5 frente a
las expresiones analíticas y 1e-9 frente al modelo finito.

No cambian los denominadores de comparación originales. Con
F=|q·l|+|P|+|H|+|w·h| y Lref=max(h,l), las escalas de fuerza y momento son F y
F·Lref. La escala de deriva es el mayor valor de referencia entre ambas
bases con piso 1e-6·F·Lref³/min(EIc,EIb); la de flecha relativa es su máximo
absoluto de referencia con piso 1e-6·F·l³/EIb. Los desplazamientos locales
usan el máximo de ambas escalas; los giros usan escala_deriva/Lref. La carga
nula usa escala F=1 para definir la comparación cero. No se amplía ningún
denominador para ocultar errores pequeños.

El residuo relativo hacia atrás se evalúa en binary64, en ambos Lua, usando
**la matriz y las cargas de la referencia independiente**:

```text
eta = ||Kfree*uLua - Ffree||∞ /
      (||Kfree||∞*||uLua||∞ + ||Ffree||∞)
```

El caso sin carga tiene eta=0. Se informa el residuo, sin sustituir por él
los contrastes de respuesta, continuidad o equilibrio global.

## Máximos observados

Los valores relativos están normalizados con las escalas anteriores. El
modelo del máximo absoluto puede diferir del del máximo relativo.

| Magnitud | Máximo relativo | Modelo | Máximo absoluto | Modelo del máximo absoluto |
| --- | ---: | --- | ---: | --- |
| Traslaciones/deriva [m] | 2.02057181124e-09 | random 44 PIN | 1.36625832869e-09 | random 44 PIN |
| Giros [rad] | 3.02252789801e-09 | random 44 PIN | 2.55708024199e-10 | random 44 PIN |
| N [kN] | 2.54262977339e-10 | asymmetric chord PIN | 3.06380343318e-08 | random 26 PIN |
| V [kN] | 1.78756639634e-10 | random 26 PIN | 2.66134065896e-08 | random 26 PIN |
| M [kNm] | 5.12221978897e-11 | random 44 PIN | 8.19414296416e-08 | random 44 PIN |
| Reacción H [kN] | 6.02641439549e-11 | random 27 PIN | 1.02522470513e-08 | random 44 PIN |
| Reacción V [kN] | 1.78756639634e-10 | random 26 PIN | 2.66134065896e-08 | random 26 PIN |
| Reacción M [kNm] | 4.80049152986e-12 | random 47 FIX | 3.55805696017e-09 | random 26 FIX |
| Flecha relativa [m] | 1.21632193857e-10 | random 47 PIN | 3.94498322898e-12 | random 26 PIN |
| Equilibrio Fx [kN] | 1.20527980223e-10 | random 27 PIN | 2.05044941026e-08 | random 44 PIN |
| Equilibrio Fy [kN] | 1.90902628468e-16 | random 26 PIN | 5.68434188608e-14 | random 08 FIX |
| Equilibrio Mz [kNm] | 1.02444395779e-10 | random 44 PIN | 1.63882859283e-07 | random 44 PIN |

Máximo residuo hacia atrás: **2.28459369477e-16**, `random 16 PIN`.
Los resultados por modelo son iguales en ambos Lua a los 12 dígitos
significativos publicados por el arnés. Las pruebas de comparación usan los
valores binary64 completos, sin redondearlos para aceptar resultados.

## Seis testigos analíticos conservados

h=4, l=6, EIc=10000, EIb=15000; k=1, N1=k+2=3, N2=6k+1=7.
Se informa el máximo de cada fila entre los valores complementarios,
ambas bases y ambas derivas cuando corresponde.

| Caso | Expresión / valor esperado | Lua vs analítica | Lua vs Python con EA finito |
| --- | --- | ---: | ---: |
| PIN q=10 | ql²/[4h(2k+3)] = 4,5 | 1,34999817747e-6 | 0 |
| FIX q=10 | Mbase=ql²/(12N1)=10; Mesquina=ql²/(6N1)=20 | 1,34999088761e-5 | 5,3290705182e-16 |
| FIX P=20, a=3 | Mbase=Pl/(8N1)=5 | 1,34999088761e-5 | 5,3290705182e-16 |
| FIX H=10 | Mbase=Hh(3k+1)/(2N2)=80/7 | 9,01780500984e-6 | 2,76434430901e-12 |
| PIN w=10 | Hsotavento=wh(5k+6)/(16k+24)=11; Hbarlovento=29 | 1,35000340473e-6 | 5,22717223041e-12 |
| PIN H=10 | deriva=Hh³/(6EIc)+Hh²l/(12EIb)=0,016 m | 5,80554758889e-6 | 4,92921675699e-12 |

PASS en los seis, sin cambios en fórmulas ni tolerancias. Máximo error
analítico **1,34999088761e-5**, frente al modelo finito **5,22717223041e-12**.
El orden de error de aproximación 1e-5 se refiere a estos testigos; no es
una garantía universal. **Atribución documental Kleinlogel OPEN**: las
expresiones son las suministradas por el dueño; no se dispone de una fuente
primaria con edición, forma y página.

## API y signos, sin cambios en R1

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

## Cobertura física y regresión completa

Se mantienen los **136 modelos originales**, la semilla 20261118, las
50 geometrías aleatorias con PIN/FIX y las cargas con signo. La referencia
Decimal/SymPy sigue siendo independiente del motor. Se comprueban:

- Reacciones, todos los GDL nodales, deriva y N/V/M/u/w en 21 posiciones por
  barra, con límites laterales y la posición adicional de P: **16.588 consultas**.
- Extremos de M con su posición y |N| con signo, momentos de extremo y
  continuidad de momentos en las uniones rígidas. Las transformaciones de
  u/w locales se contrastan con la referencia y sus GDL globales.
- Equilibrio global independiente Fx, Fy y Mz en todos los modelos, incluidos
  individuales con signo, combinados y aleatorios. No se usa Frame.applied
  como autoridad de esas comprobaciones.
- Signos de cargas locales, resultantes distribuidas y salto de P;
  simetría FIX con q; ceros, cargas en/cerca de extremos e inválidos.
- Flecha relativa a la cuerda, incluidos dos testigos asimétricos que
  rechazan usar únicamente los estacionarios de la flecha absoluta.
- **Una llamada a Frame.solve por PortalPreset.solve válido** en los 136 casos.
- Reversión de los ocho pares individuales +/- ya presentes en la campaña.
  Superposición por descomposición de las dos geometrías combinadas en
  cuatro cargas: **ocho solves suplementarios**, cada uno con una llamada
  al motor, comprobando reacciones, GDL, N/V/M/u/w y flecha relativa punto
  a punto con 1e-9. No se suman máximos de flecha.

Comprobaciones locales del workflow `.github/workflows/ci.yml`, con sus
versiones de dependencias ya disponibles:

```bash
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
set -e
for test in tests/test_*.py; do
  echo "Running $test"
  python3 "$test"
done
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
```

**PASS: 15 suites en liblua 5.4.7 y las mismas 15 en Lua 5.1.5**; cinco tests
USB adicionales pasan. Se preservan las **394 filas Frame** (265+129), los
**2.042 casos históricos** (2.009 equivalentes, dos adjudicados, cinco RESOLVED,
26 inválidos), los **300 modelos de fuerza bruta de continuas** (1.050 vanos,
4.500 patrones), además de las referencias racionales independientes D/E/F5.
Pasan los tests UI/layout, signos de dibujo, CAS `bx_*`/`bc_*`, persistencia,
precisión de formato, selector y los barridos previos cerca de apoyos.
No se alteran baselines ni assertions históricas. Estas son ejecuciones
locales de los comandos del workflow, no una nueva ejecución remota de GitHub.

## Benchmark PC y paquete

El caso existente `portal FIX q+P+H+w` usa h=4, l=6, EIc=10000, EIb=15000,
q=10, P=20, a=1,7, H=10, w=7, bases FIX y el EA aprobado. Mide
**PortalPreset.solve completo**, incluidos recuperación y extremos, y por
separado 101 consultas Frame.at. Tiene 4 nudos, 12 GDL y 6 GDL libres.
La instrumentación confirma una llamada al motor por cálculo.

Entorno: Intel Core i5-8300H @ 2,30 GHz, x86_64, Linux
6.12.117+deb13-amd64; Python 3.13.5, SymPy 1.13.3, Lua 5.1.5 y liblua
5.4.7-1+b2. Reloj **os.clock de CPU**, media aritmética por operación,
objetivo de al menos 200 ms acumulados por fase y al menos tres repeticiones,
sin pintura. Se midió después de terminar las regresiones.

| Runtime PC | Cálculo completo | Repeticiones / Frame.solve | 101 consultas | Repeticiones recuperación |
| --- | ---: | ---: | ---: | ---: |
| Lua 5.1.5 | 1,143200 ms | 175 / 175 | 0,210175 ms | 953 |
| Lua 5.4.7 | 0,742730 ms | 270 / 270 | 0,193627 ms | 1.033 |

Son tiempos **PC**, sin medición ni extrapolación a la TI-Nspire. No se
requiere medición del dueño para cerrar esta fase de cálculo.

```bash
python3 tools/build_bench.py
luac5.1 -p bench.lua
python3 tools/package.py --bench
```

La medición usa `Bench.measure(#Bench.cases)` del bundle, con contador de
Frame.solve verificado contra `Nsolve`; equivalente reproducible en Lua 5.1:

```bash
lua5.1 - <<'LUA'
local b=dofile('bench.lua')
local count,solve=0,Frame.solve
Frame.solve=function(m) count=count+1;return solve(m) end
local r=b.measure(#b.cases)
assert(count==r.Nsolve)
print(r.name,r.solve_ms,r.recovery_ms,r.Nsolve,r.Nrecover,count)
LUA
```

Lua 5.4.7 ejecutó el mismo chunk mediante ctypes. `BXBENCH.tns` se vuelve a
empaquetar correctamente: **19.865 bytes**, último paquete USB **148 bytes**,
seguro según la guardia existente; los cinco tests incluyen límites,
reintentos y propagación de fallos. El archivo resultante es idéntico al
artefacto P6A anterior; no hizo falta cambiar el harness ni añadir relleno.

SHA-256 de BXBENCH.tns:
`72fe4c9a7d432c0fa3174ba53d60834d5c9cd4d2253443d6951510b9455be0c3`.

## Integridad y archivos

R1 modifica únicamente **tests/portal_reference.py**, **tests/test_portal_preset.py**,
**README.md** (nota de precisión) y **VALIDATION_P6A.md**. No se cambia el
harness de benchmark: se completa su medición y se reempaqueta su artefacto.

Se verifican SHA-256 anteriores/posteriores de todos los archivos congelados:
frame_core.lua, beam_preset.lua, continuous_preset.lua, **portal_preset.lua**,
beam_ui.lua, build.py, BeamCX.lua y BeamCX.tns. También permanecen idénticos
los cinco fixtures históricos. La reconstrucción produce el mismo bundle
v0.5.0 byte a byte; el paquete productivo sigue intacto.

```text
4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b  src/frame_core.lua
b205832ce2f7ba4371456f9898ca40611c8c589d87abdff92c50c55f424feede  src/beam_preset.lua
16186de935f91b57c5785be27880bc5d46f45de497148c01b340a8657bf1073d  src/continuous_preset.lua
921ebbf5d15bd27481e71c99440e857d87c448d4c83d2a30fcc818b6510312cf  src/portal_preset.lua
758e47b930e306434c2dbf2c20755dbce131e66244ced6cfcfd0a9aa115ceca6  src/beam_ui.lua
edd0ff42002ba029f3be9b06b19c4bac58e99e2e213c827838edf278e71d2c6e  build.py
76bbf567ad83c2b4c111806c3af150f2a4098cb3b225b6a99eb11e75362515d2  BeamCX.lua
e52160578a3db833bb1af0046f94f8463fb7b04223e52acf50f7f27268dc86ec  BeamCX.tns
```

El modelo es lineal elástico de primer orden, sin análisis de estabilidad de
segundo orden. Derivas grandes de modelos aleatorios extremos son pruebas
de estrés numérico y no necesariamente configuraciones de ingeniería
válidas bajo hipótesis de pequeños desplazamientos. No se afirma una cota
universal de 1e-8 ni un condicionamiento uniforme para todas las geometrías.

**P6A CLOSED/PASS.** PortalPreset permanece no productivo hasta P6B, como
excepción autorizada de P6A. No se inicia P6B. Sin commit, push ni release.

## Resultados de los 136 modelos

κ∞ corresponde a la matriz sin escalar. Dabs [m] y Drel son los máximos
absoluto y normalizado entre traslaciones nodales, deriva, u/w locales y
flecha relativa; los giros se informan aparte en los máximos anteriores.
N/V/M/R son errores relativos por categoría, con R para reacciones H/V;
los momentos de reacción se incluyen en M. `eta` es el residuo hacia atrás
independiente. Se imprimen 12 dígitos significativos; la tabla usa menos por
legibilidad. Todos los valores publicados coinciden entre ambos Lua.

| Modelo | κ∞ | Tol. D | Dabs [m] | Drel | Nrel | Vrel | Mrel | Rrel | eta | Resultado |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| PIN q | 708368 | 1e-09 | 3.25261e-18 | 1.90303e-14 | 0 | 0 | 9.86865e-18 | 1.4803e-17 | 9.47272e-21 | PASS |
| FIX q | 136912 | 1e-09 | 4.44523e-18 | 9.64911e-13 | 7.40149e-17 | 5.92119e-17 | 1.97373e-17 | 5.92119e-17 | 2.84176e-20 | PASS |
| FIX P | 136912 | 1e-09 | 1.40946e-18 | 1.44737e-12 | 1.11022e-16 | 8.88178e-17 | 3.23815e-17 | 8.88178e-17 | 3.41011e-20 | PASS |
| FIX H | 136912 | 1e-09 | 1.05319e-14 | 2.7646e-12 | 1.91385e-12 | 1.38218e-12 | 5.26542e-13 | 1.38218e-12 | 5.91017e-17 | PASS |
| PIN w | 708368 | 1e-09 | 1.84013e-13 | 4.92888e-12 | 1.26791e-11 | 1.91682e-12 | 9.58404e-13 | 1.91682e-12 | 7.98236e-17 | PASS |
| PIN H | 708368 | 1e-09 | 7.88709e-14 | 4.92972e-12 | 3.28617e-12 | 3.28608e-12 | 1.64331e-12 | 3.28617e-12 | 3.76852e-17 | PASS |
| combined PIN | 708368 | 1e-09 | 2.14627e-13 | 4.92926e-12 | 1.13033e-12 | 7.57872e-13 | 3.78916e-13 | 7.57812e-13 | 4.1115e-17 | PASS |
| zero PIN | 708368 | 1e-09 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | PASS |
| sign PIN q -1 | 708368 | 1e-09 | 7.80626e-18 | 6.09459e-13 | 9.10952e-17 | 9.10952e-17 | 6.07301e-17 | 9.10952e-17 | 1.45734e-20 | PASS |
| sign PIN q 1 | 708368 | 1e-09 | 7.80626e-18 | 6.09459e-13 | 9.10952e-17 | 9.10952e-17 | 6.07301e-17 | 9.10952e-17 | 1.45734e-20 | PASS |
| sign PIN P -1 | 708368 | 1e-09 | 6.50521e-19 | 4.92449e-13 | 0 | 1.70804e-17 | 1.841e-17 | 0 | 1.45734e-20 | PASS |
| sign PIN P 1 | 708368 | 1e-09 | 6.50521e-19 | 4.92449e-13 | 0 | 1.70804e-17 | 1.841e-17 | 0 | 1.45734e-20 | PASS |
| sign PIN H -1 | 708368 | 1e-09 | 1.02529e-13 | 4.92925e-12 | 5.14276e-12 | 3.28585e-12 | 1.64295e-12 | 3.28599e-12 | 3.39512e-17 | PASS |
| sign PIN H 1 | 708368 | 1e-09 | 1.02529e-13 | 4.92925e-12 | 5.14276e-12 | 3.28585e-12 | 1.64295e-12 | 3.28599e-12 | 3.39512e-17 | PASS |
| sign PIN w -1 | 708368 | 1e-09 | 2.39239e-13 | 4.92935e-12 | 2.54449e-12 | 1.91689e-12 | 9.58481e-13 | 1.91689e-12 | 3.39525e-17 | PASS |
| sign PIN w 1 | 708368 | 1e-09 | 2.39239e-13 | 4.92935e-12 | 2.54449e-12 | 1.91689e-12 | 9.58481e-13 | 1.91689e-12 | 3.39525e-17 | PASS |
| endpoint PIN 0 | 708368 | 1e-09 | 4.99514e-14 | 4.92944e-12 | 2.73839e-13 | 2.73886e-13 | 1.36935e-13 | 2.73839e-13 | 1.90334e-17 | PASS |
| endpoint PIN 6 | 708368 | 1e-09 | 4.99496e-14 | 4.92918e-12 | 2.73863e-13 | 2.73886e-13 | 1.36929e-13 | 2.73863e-13 | 2.41397e-17 | PASS |
| endpoint PIN 1e-07 | 708368 | 1e-09 | 4.99479e-14 | 4.92909e-12 | 6.83529e-13 | 2.73851e-13 | 1.36924e-13 | 2.73863e-13 | 7.35219e-17 | PASS |
| endpoint PIN 5.9999999 | 708368 | 1e-09 | 4.99496e-14 | 4.92918e-12 | 6.83529e-13 | 2.73874e-13 | 1.36922e-13 | 2.73863e-13 | 5.95212e-17 | PASS |
| asymmetric chord PIN | 1.53102e+08 | 1e-09 | 1.59631e-11 | 2.32156e-10 | 2.54263e-10 | 6.12031e-11 | 1.14756e-11 | 6.12031e-11 | 5.85123e-17 | PASS |
| combined FIX | 136912 | 1e-09 | 2.54657e-14 | 2.7641e-12 | 5.83699e-13 | 2.83224e-13 | 1.07896e-13 | 2.83224e-13 | 9.81308e-18 | PASS |
| zero FIX | 136912 | 1e-09 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | PASS |
| sign FIX q -1 | 136912 | 1e-09 | 8.23994e-18 | 6.84541e-13 | 9.10952e-17 | 9.10952e-17 | 5.69345e-17 | 9.10952e-17 | 2.40456e-20 | PASS |
| sign FIX q 1 | 136912 | 1e-09 | 8.23994e-18 | 6.84541e-13 | 9.10952e-17 | 9.10952e-17 | 5.69345e-17 | 9.10952e-17 | 2.40456e-20 | PASS |
| sign FIX P -1 | 136912 | 1e-09 | 7.58942e-19 | 1.02681e-12 | 1.36643e-16 | 3.41607e-17 | 2.27738e-17 | 1.36643e-16 | 1.53018e-20 | PASS |
| sign FIX P 1 | 136912 | 1e-09 | 7.58942e-19 | 1.02681e-12 | 1.36643e-16 | 3.41607e-17 | 2.27738e-17 | 1.36643e-16 | 1.53018e-20 | PASS |
| sign FIX H -1 | 136912 | 1e-09 | 1.36913e-14 | 2.76456e-12 | 5.94362e-12 | 1.38207e-12 | 5.2653e-13 | 1.38207e-12 | 1.4184e-16 | PASS |
| sign FIX H 1 | 136912 | 1e-09 | 1.36913e-14 | 2.76456e-12 | 5.94362e-12 | 1.38207e-12 | 5.2653e-13 | 1.38207e-12 | 1.4184e-16 | PASS |
| sign FIX w -1 | 136912 | 1e-09 | 2.46452e-14 | 2.76466e-12 | 3.55408e-13 | 6.21998e-13 | 2.36939e-13 | 6.21998e-13 | 7.00681e-17 | PASS |
| sign FIX w 1 | 136912 | 1e-09 | 2.46452e-14 | 2.76466e-12 | 3.55408e-13 | 6.21998e-13 | 2.36939e-13 | 6.21998e-13 | 7.00681e-17 | PASS |
| endpoint FIX 0 | 136912 | 1e-09 | 2.73891e-15 | 2.76401e-12 | 1.71182e-13 | 4.72849e-14 | 1.80114e-14 | 4.7278e-14 | 1.1603e-16 | PASS |
| endpoint FIX 6 | 136912 | 1e-09 | 2.73956e-15 | 2.76578e-12 | 2.70193e-14 | 4.73317e-14 | 1.80253e-14 | 4.73218e-14 | 2.01311e-17 | PASS |
| endpoint FIX 1e-07 | 136912 | 1e-09 | 2.73935e-15 | 2.76576e-12 | 1.23875e-13 | 4.73324e-14 | 1.80238e-14 | 4.73189e-14 | 1.39419e-16 | PASS |
| endpoint FIX 5.9999999 | 136912 | 1e-09 | 2.73783e-15 | 2.76402e-12 | 6.7598e-14 | 4.72955e-14 | 1.80148e-14 | 4.72955e-14 | 6.09642e-18 | PASS |
| asymmetric chord FIX | 3.23454e+07 | 1e-09 | 9.05928e-13 | 1.07774e-10 | 1.90722e-11 | 6.90403e-12 | 1.31077e-12 | 6.90403e-12 | 6.61817e-17 | PASS |
| random 00 PIN | 1.85859e+06 | 4.12691e-09 | 5.08482e-14 | 5.8883e-14 | 7.04331e-14 | 1.47247e-15 | 7.5696e-16 | 1.39067e-15 | 5.66094e-18 | PASS |
| random 00 FIX | 253012 | 1e-09 | 6.43097e-14 | 5.99443e-13 | 4.33561e-15 | 1.02255e-14 | 4.45976e-15 | 1.01846e-14 | 1.23022e-18 | PASS |
| random 01 PIN | 8.75445e+06 | 1.94388e-08 | 2.04245e-12 | 9.26971e-12 | 4.58043e-12 | 3.96298e-12 | 9.93797e-13 | 3.96298e-12 | 9.17711e-18 | PASS |
| random 01 FIX | 370071 | 1e-09 | 1.60184e-14 | 1.71367e-12 | 3.48387e-13 | 1.72281e-13 | 1.60324e-13 | 1.72281e-13 | 3.07524e-17 | PASS |
| random 02 PIN | 3.99609e+06 | 8.87309e-09 | 5.33185e-14 | 1.14961e-12 | 5.21312e-13 | 9.21979e-14 | 4.61675e-14 | 9.21192e-14 | 5.87736e-18 | PASS |
| random 02 FIX | 359861 | 1e-09 | 5.41841e-15 | 7.54023e-13 | 1.45189e-14 | 6.71484e-14 | 3.88368e-14 | 6.71484e-14 | 8.48574e-18 | PASS |
| random 03 PIN | 618685 | 1.37376e-09 | 9.99617e-14 | 8.89716e-13 | 4.33763e-14 | 1.4505e-14 | 5.49444e-15 | 1.44773e-14 | 1.97034e-17 | PASS |
| random 03 FIX | 125461 | 1e-09 | 1.29202e-14 | 2.63382e-13 | 5.69476e-15 | 7.7679e-15 | 1.65252e-15 | 7.7471e-15 | 9.97004e-18 | PASS |
| random 04 PIN | 543512 | 1.20684e-09 | 2.37588e-14 | 6.46764e-14 | 4.73151e-12 | 1.12946e-14 | 5.64388e-15 | 1.13384e-14 | 8.29151e-17 | PASS |
| random 04 FIX | 111016 | 1e-09 | 2.00506e-13 | 2.58198e-12 | 1.22638e-12 | 3.88919e-13 | 1.05185e-13 | 3.88919e-13 | 5.94289e-17 | PASS |
| random 05 PIN | 687927 | 1.5275e-09 | 2.27995e-14 | 5.07286e-12 | 1.35665e-12 | 5.23222e-13 | 2.60324e-13 | 5.23209e-13 | 7.29764e-17 | PASS |
| random 05 FIX | 121438 | 1e-09 | 1.71651e-15 | 1.56538e-12 | 5.8335e-13 | 1.60645e-13 | 4.34425e-14 | 1.60645e-13 | 6.05611e-17 | PASS |
| random 06 PIN | 1.98321e+06 | 4.40361e-09 | 7.75613e-12 | 1.53452e-11 | 7.0716e-12 | 5.45983e-12 | 2.50252e-12 | 5.45983e-12 | 9.10839e-17 | PASS |
| random 06 FIX | 413626 | 1e-09 | 1.33094e-12 | 1.15095e-11 | 1.72941e-12 | 1.76192e-12 | 9.69309e-13 | 1.76192e-12 | 1.00349e-16 | PASS |
| random 07 PIN | 771413 | 1.71288e-09 | 2.43746e-14 | 1.16308e-11 | 1.80094e-13 | 1.80099e-13 | 9.00452e-14 | 1.80094e-13 | 7.14038e-17 | PASS |
| random 07 FIX | 129895 | 1e-09 | 9.25096e-17 | 4.3211e-13 | 2.31038e-14 | 2.64572e-15 | 7.5219e-16 | 2.62698e-15 | 1.13897e-17 | PASS |
| random 08 PIN | 654402 | 1.45306e-09 | 2.28539e-13 | 1.61629e-12 | 3.55184e-14 | 7.16827e-14 | 1.6962e-14 | 7.16612e-14 | 1.86732e-17 | PASS |
| random 08 FIX | 118849 | 1e-09 | 1.12098e-14 | 4.04915e-13 | 1.29197e-14 | 1.43408e-14 | 1.83884e-15 | 1.43408e-14 | 1.55928e-18 | PASS |
| random 09 PIN | 2.6719e+06 | 5.93281e-09 | 1.03424e-11 | 1.62331e-11 | 4.29152e-12 | 4.29147e-12 | 1.84633e-12 | 4.29152e-12 | 1.38397e-17 | PASS |
| random 09 FIX | 285985 | 1e-09 | 8.29614e-14 | 2.06748e-12 | 5.37629e-14 | 1.2976e-13 | 1.06578e-13 | 1.29688e-13 | 5.26146e-17 | PASS |
| random 10 PIN | 1.88578e+06 | 4.18728e-09 | 3.70948e-12 | 5.17884e-12 | 8.55634e-13 | 8.55654e-13 | 4.27797e-13 | 8.55634e-13 | 4.74363e-20 | PASS |
| random 10 FIX | 259765 | 1e-09 | 4.94882e-14 | 5.34618e-13 | 6.89391e-14 | 6.73534e-14 | 2.85814e-14 | 6.73336e-14 | 2.42874e-18 | PASS |
| random 11 PIN | 749173 | 1.6635e-09 | 2.00334e-12 | 1.83016e-11 | 1.09321e-12 | 1.09321e-12 | 5.46607e-13 | 1.09321e-12 | 1.02351e-16 | PASS |
| random 11 FIX | 155114 | 1e-09 | 8.22207e-14 | 9.76814e-12 | 8.3136e-14 | 1.41236e-13 | 5.02227e-14 | 1.41214e-13 | 8.3184e-17 | PASS |
| random 12 PIN | 619090 | 1.37465e-09 | 1.88349e-12 | 3.34229e-12 | 3.35021e-13 | 2.50693e-13 | 1.00145e-13 | 2.50693e-13 | 4.87792e-17 | PASS |
| random 12 FIX | 125515 | 1e-09 | 1.34906e-13 | 1.17544e-12 | 3.78659e-14 | 7.45083e-14 | 1.67048e-14 | 7.45083e-14 | 4.28657e-17 | PASS |
| random 13 PIN | 4.71693e+06 | 1.04737e-08 | 3.75535e-11 | 1.65502e-10 | 3.60834e-11 | 3.60834e-11 | 1.64843e-11 | 3.60834e-11 | 1.17491e-16 | PASS |
| random 13 FIX | 1.00124e+06 | 2.22319e-09 | 1.41922e-12 | 3.52958e-11 | 2.63765e-12 | 2.63769e-12 | 1.29618e-12 | 2.63765e-12 | 1.14058e-16 | PASS |
| random 14 PIN | 6.65369e+06 | 1.47742e-08 | 8.47586e-14 | 2.09375e-12 | 8.51486e-14 | 8.12415e-14 | 2.30463e-14 | 8.12634e-14 | 1.65819e-18 | PASS |
| random 14 FIX | 402836 | 1e-09 | 5.65086e-16 | 1.55578e-13 | 5.63147e-15 | 7.90151e-15 | 2.01315e-15 | 7.90151e-15 | 8.97101e-19 | PASS |
| random 15 PIN | 771869 | 1.71389e-09 | 2.70128e-12 | 4.32066e-12 | 1.07061e-12 | 3.27891e-13 | 1.63951e-13 | 3.27848e-13 | 6.25876e-17 | PASS |
| random 15 FIX | 155023 | 1e-09 | 1.25844e-13 | 9.51087e-13 | 4.71097e-14 | 6.51293e-14 | 2.09003e-14 | 6.51293e-14 | 1.06307e-17 | PASS |
| random 16 PIN | 5.04857e+06 | 1.12101e-08 | 1.57224e-10 | 1.21337e-10 | 2.63286e-11 | 1.16679e-11 | 5.83394e-12 | 1.16679e-11 | 2.28459e-16 | PASS |
| random 16 FIX | 1.03149e+06 | 2.29037e-09 | 5.16487e-12 | 1.71035e-11 | 1.48248e-12 | 1.18756e-12 | 3.87883e-13 | 1.18757e-12 | 8.16915e-17 | PASS |
| random 17 PIN | 1.18452e+06 | 2.63016e-09 | 3.02347e-12 | 4.88921e-12 | 5.27492e-13 | 2.84506e-13 | 1.42308e-13 | 2.84554e-13 | 3.02854e-18 | PASS |
| random 17 FIX | 204737 | 1e-09 | 5.09315e-15 | 7.34848e-14 | 1.86301e-14 | 1.7571e-15 | 8.77135e-16 | 1.7571e-15 | 1.03032e-17 | PASS |
| random 18 PIN | 974084 | 2.1629e-09 | 1.24649e-11 | 6.41206e-12 | 4.73933e-12 | 1.99761e-12 | 9.98779e-13 | 1.99757e-12 | 2.14571e-17 | PASS |
| random 18 FIX | 181670 | 1e-09 | 5.62661e-13 | 1.44685e-12 | 1.51998e-13 | 3.72473e-13 | 1.40073e-13 | 3.72552e-13 | 2.96332e-18 | PASS |
| random 19 PIN | 2.32149e+06 | 5.15474e-09 | 1.93422e-16 | 4.70999e-14 | 4.3242e-15 | 1.49528e-15 | 2.68501e-16 | 1.47508e-15 | 1.69033e-19 | PASS |
| random 19 FIX | 314847 | 1e-09 | 3.46945e-17 | 5.4171e-15 | 8.89088e-16 | 8.08261e-17 | 2.61952e-17 | 8.08261e-17 | 2.8305e-20 | PASS |
| random 20 PIN | 4.63111e+06 | 1.02831e-08 | 1.25049e-11 | 1.89373e-10 | 3.57348e-11 | 3.57348e-11 | 1.54385e-11 | 3.57348e-11 | 2.07073e-16 | PASS |
| random 20 FIX | 929733 | 2.06442e-09 | 1.98565e-13 | 2.39017e-11 | 2.09258e-12 | 1.0895e-12 | 5.15444e-13 | 1.08949e-12 | 8.67538e-17 | PASS |
| random 21 PIN | 734567 | 1.63107e-09 | 3.42365e-12 | 1.11945e-11 | 5.15327e-13 | 3.66149e-13 | 1.8308e-13 | 3.66132e-13 | 1.48598e-16 | PASS |
| random 21 FIX | 147330 | 1e-09 | 2.30534e-15 | 3.30073e-12 | 1.97835e-15 | 6.74643e-16 | 3.24035e-16 | 6.38176e-16 | 3.53176e-18 | PASS |
| random 22 PIN | 3.69807e+06 | 8.21136e-09 | 1.17162e-11 | 9.65106e-11 | 2.30113e-11 | 2.30113e-11 | 6.63249e-12 | 2.30113e-11 | 2.45791e-17 | PASS |
| random 22 FIX | 764866 | 1.69834e-09 | 1.02588e-12 | 3.0636e-11 | 3.61883e-12 | 3.61883e-12 | 1.40234e-12 | 3.61883e-12 | 8.52137e-17 | PASS |
| random 23 PIN | 2.82742e+06 | 6.27814e-09 | 1.09141e-10 | 3.55522e-11 | 4.99782e-12 | 4.99789e-12 | 2.49899e-12 | 4.99782e-12 | 1.16283e-17 | PASS |
| random 23 FIX | 601930 | 1.33655e-09 | 5.21083e-12 | 8.46867e-12 | 9.9891e-13 | 5.17186e-13 | 2.50542e-13 | 5.17149e-13 | 1.06589e-16 | PASS |
| random 24 PIN | 556624 | 1.23595e-09 | 1.23236e-13 | 1.08371e-11 | 1.88341e-13 | 2.8877e-13 | 9.42107e-14 | 2.88791e-13 | 6.76729e-17 | PASS |
| random 24 FIX | 97982.5 | 1e-09 | 1.48839e-15 | 4.68337e-13 | 7.6774e-15 | 1.39868e-14 | 2.35623e-15 | 1.39663e-14 | 1.18454e-17 | PASS |
| random 25 PIN | 1.8298e+07 | 4.06298e-08 | 9.21457e-13 | 2.6676e-11 | 3.08786e-11 | 9.07757e-12 | 1.99063e-12 | 9.07757e-12 | 5.84214e-17 | PASS |
| random 25 FIX | 3.83337e+06 | 8.5118e-09 | 2.41283e-14 | 4.73869e-12 | 1.16025e-12 | 4.57648e-13 | 1.0915e-13 | 4.57609e-13 | 2.43834e-17 | PASS |
| random 26 PIN | 8.96809e+06 | 1.99132e-08 | 4.06795e-10 | 1.39995e-10 | 2.05789e-10 | 1.78757e-10 | 3.91645e-11 | 1.78757e-10 | 9.72073e-17 | PASS |
| random 26 FIX | 1.90599e+06 | 4.23214e-09 | 1.49819e-11 | 2.37879e-11 | 1.29206e-11 | 1.22068e-11 | 3.22487e-12 | 1.22067e-11 | 5.60611e-17 | PASS |
| random 27 PIN | 7.04654e+06 | 1.56465e-08 | 1.3306e-10 | 1.77708e-10 | 1.05927e-10 | 6.89494e-11 | 3.44748e-11 | 6.89494e-11 | 1.08101e-16 | PASS |
| random 27 FIX | 1.42346e+06 | 3.16071e-09 | 4.25215e-13 | 2.32146e-12 | 3.08236e-11 | 7.70448e-13 | 2.21807e-13 | 7.70525e-13 | 8.59011e-17 | PASS |
| random 28 PIN | 2.85268e+06 | 6.33423e-09 | 1.14783e-12 | 5.63297e-11 | 3.77533e-12 | 2.31869e-12 | 1.15932e-12 | 2.31865e-12 | 7.54869e-17 | PASS |
| random 28 FIX | 537357 | 1.19317e-09 | 2.95586e-13 | 4.14304e-11 | 1.75482e-12 | 1.80617e-12 | 6.12794e-13 | 1.80617e-12 | 9.64866e-17 | PASS |
| random 29 PIN | 1.34209e+06 | 2.98004e-09 | 1.11353e-12 | 5.55075e-12 | 3.36968e-13 | 3.36985e-13 | 1.68548e-13 | 3.36968e-13 | 9.40383e-18 | PASS |
| random 29 FIX | 219250 | 1e-09 | 1.33747e-14 | 4.757e-13 | 1.23418e-13 | 1.7002e-14 | 7.99683e-15 | 1.69732e-14 | 2.18517e-17 | PASS |
| random 30 PIN | 1.00019e+06 | 2.22087e-09 | 2.28355e-15 | 1.29141e-12 | 5.73255e-14 | 3.02983e-14 | 1.2538e-14 | 3.02983e-14 | 2.86283e-18 | PASS |
| random 30 FIX | 180486 | 1e-09 | 5.15809e-17 | 2.15654e-13 | 9.56331e-16 | 3.09721e-15 | 7.94151e-16 | 3.09721e-15 | 1.04139e-18 | PASS |
| random 31 PIN | 1.69942e+07 | 3.77348e-08 | 1.24074e-13 | 2.81641e-12 | 4.63659e-14 | 4.56118e-14 | 1.96322e-14 | 4.5589e-14 | 5.31278e-19 | PASS |
| random 31 FIX | 438731 | 1e-09 | 2.24784e-16 | 5.31625e-14 | 1.59961e-16 | 3.31349e-16 | 1.24792e-16 | 3.19923e-16 | 2.06698e-19 | PASS |
| random 32 PIN | 3.79562e+06 | 8.42796e-09 | 8.77076e-15 | 1.10364e-13 | 2.60063e-14 | 6.68602e-15 | 1.32237e-15 | 6.68602e-15 | 7.46366e-19 | PASS |
| random 32 FIX | 376128 | 1e-09 | 1.33743e-15 | 6.66282e-14 | 1.08821e-14 | 4.05772e-15 | 6.57363e-16 | 3.9655e-15 | 1.01478e-19 | PASS |
| random 33 PIN | 1.2558e+06 | 2.78844e-09 | 3.01414e-12 | 5.81297e-12 | 3.83137e-13 | 2.48634e-13 | 1.24316e-13 | 2.48585e-13 | 1.1572e-17 | PASS |
| random 33 FIX | 211188 | 1e-09 | 8.69027e-14 | 7.5487e-13 | 4.04713e-14 | 3.62889e-14 | 1.37144e-14 | 3.62643e-14 | 5.86818e-19 | PASS |
| random 34 PIN | 1.07794e+06 | 2.3935e-09 | 5.05318e-12 | 5.5427e-12 | 2.92685e-12 | 8.97597e-13 | 4.4879e-13 | 8.97503e-13 | 4.21082e-17 | PASS |
| random 34 FIX | 193846 | 1e-09 | 2.38781e-13 | 1.53734e-12 | 2.65132e-13 | 1.30985e-13 | 7.0526e-14 | 1.30979e-13 | 2.04951e-17 | PASS |
| random 35 PIN | 9.53421e+06 | 2.11702e-08 | 2.70617e-15 | 3.70355e-14 | 1.8738e-14 | 4.72387e-16 | 3.04095e-16 | 4.72387e-16 | 1.19578e-18 | PASS |
| random 35 FIX | 361798 | 1e-09 | 1.18135e-15 | 1.14655e-13 | 7.96168e-15 | 2.46035e-15 | 1.47901e-15 | 2.43082e-15 | 1.5868e-18 | PASS |
| random 36 PIN | 3.00866e+06 | 6.68058e-09 | 3.06005e-13 | 1.52033e-12 | 1.04543e-13 | 1.08263e-13 | 5.24635e-14 | 1.08256e-13 | 4.13274e-19 | PASS |
| random 36 FIX | 320270 | 1e-09 | 6.59195e-16 | 3.59376e-14 | 7.63154e-15 | 1.98892e-15 | 7.64358e-16 | 1.98892e-15 | 4.38877e-18 | PASS |
| random 37 PIN | 612248 | 1.35946e-09 | 3.78475e-13 | 5.83903e-12 | 2.61633e-14 | 3.04543e-14 | 1.09843e-14 | 3.04543e-14 | 1.13473e-17 | PASS |
| random 37 FIX | 123156 | 1e-09 | 1.09947e-14 | 6.41873e-13 | 3.78444e-15 | 3.63544e-15 | 7.32573e-16 | 3.63544e-15 | 6.49405e-18 | PASS |
| random 38 PIN | 2.5027e+07 | 5.55712e-08 | 1.66533e-14 | 6.35425e-14 | 3.57425e-14 | 5.12289e-15 | 1.21632e-15 | 5.12289e-15 | 1.68421e-19 | PASS |
| random 38 FIX | 458116 | 1.01722e-09 | 1.60982e-15 | 1.46526e-14 | 8.24373e-16 | 8.24373e-16 | 1.56149e-16 | 8.24373e-16 | 2.86169e-20 | PASS |
| random 39 PIN | 1.5729e+06 | 3.49254e-09 | 2.56328e-12 | 6.53529e-12 | 5.5786e-12 | 2.22304e-12 | 1.1117e-12 | 2.22296e-12 | 4.04544e-17 | PASS |
| random 39 FIX | 235987 | 1e-09 | 4.18415e-14 | 7.55694e-13 | 4.72041e-13 | 1.24889e-13 | 8.26099e-14 | 1.24889e-13 | 5.37321e-17 | PASS |
| random 40 PIN | 3.23231e+06 | 7.17718e-09 | 6.36982e-11 | 6.02971e-11 | 1.22153e-11 | 1.22154e-11 | 6.1077e-12 | 1.22153e-11 | 1.8379e-17 | PASS |
| random 40 FIX | 645488 | 1.43327e-09 | 1.25708e-12 | 5.62023e-12 | 2.22457e-12 | 7.8926e-13 | 2.45345e-13 | 7.8926e-13 | 4.54286e-18 | PASS |
| random 41 PIN | 1.49402e+06 | 3.3174e-09 | 5.38e-13 | 4.67966e-12 | 4.01661e-13 | 4.0457e-13 | 2.00817e-13 | 4.0457e-13 | 7.85489e-18 | PASS |
| random 41 FIX | 233871 | 1e-09 | 2.17187e-15 | 1.18914e-13 | 2.54724e-14 | 9.29981e-15 | 3.31467e-15 | 9.29981e-15 | 5.86237e-18 | PASS |
| random 42 PIN | 3.02537e+06 | 6.71766e-09 | 2.02219e-11 | 4.33364e-11 | 7.29167e-12 | 2.653e-12 | 1.32653e-12 | 2.65299e-12 | 1.43954e-16 | PASS |
| random 42 FIX | 644640 | 1.43139e-09 | 1.62902e-12 | 3.77549e-11 | 4.51513e-13 | 4.45113e-13 | 2.24528e-13 | 4.45113e-13 | 6.75306e-17 | PASS |
| random 43 PIN | 1.21069e+06 | 2.68827e-09 | 2.70617e-13 | 1.31623e-12 | 7.21895e-14 | 2.57445e-14 | 1.0438e-14 | 2.57243e-14 | 9.67103e-18 | PASS |
| random 43 FIX | 208407 | 1e-09 | 2.10526e-14 | 3.55093e-13 | 1.42644e-14 | 1.02897e-14 | 2.8028e-15 | 1.02696e-14 | 5.08331e-18 | PASS |
| random 44 PIN | 5.86209e+07 | 1.30165e-07 | 1.36626e-09 | 2.02057e-09 | 1.1307e-10 | 1.1307e-10 | 5.12222e-11 | 1.1307e-10 | 6.07551e-17 | PASS |
| random 44 FIX | 1.23592e+07 | 2.7443e-08 | 2.79723e-11 | 1.3127e-10 | 7.55207e-12 | 4.61727e-12 | 2.10325e-12 | 4.61728e-12 | 3.48634e-17 | PASS |
| random 45 PIN | 637628 | 1.41582e-09 | 4.66371e-12 | 8.89451e-12 | 3.12891e-13 | 4.10609e-13 | 1.56413e-13 | 4.10587e-13 | 5.30204e-17 | PASS |
| random 45 FIX | 127383 | 1e-09 | 1.78663e-13 | 2.47136e-12 | 4.56461e-14 | 6.53362e-14 | 1.39985e-14 | 6.53362e-14 | 4.39314e-17 | PASS |
| random 46 PIN | 512415 | 1.13779e-09 | 4.38982e-13 | 5.22939e-12 | 8.54438e-13 | 2.84222e-13 | 9.98788e-14 | 2.84222e-13 | 1.012e-16 | PASS |
| random 46 FIX | 102668 | 1e-09 | 3.6221e-14 | 2.02546e-12 | 3.15298e-14 | 9.4612e-14 | 1.7541e-14 | 9.4612e-14 | 5.16544e-17 | PASS |
| random 47 PIN | 1.72874e+07 | 3.83858e-08 | 1.07193e-10 | 1.97332e-10 | 9.93753e-11 | 9.93753e-11 | 4.03045e-11 | 9.93753e-11 | 5.68802e-17 | PASS |
| random 47 FIX | 3.59473e+06 | 7.98191e-09 | 6.30435e-12 | 4.6749e-11 | 3.45836e-11 | 1.15521e-11 | 4.80049e-12 | 1.15521e-11 | 4.12349e-17 | PASS |
| random 48 PIN | 5.70361e+07 | 1.26646e-07 | 6.25749e-14 | 1.21522e-12 | 1.2683e-14 | 1.00695e-14 | 3.53573e-15 | 9.86454e-15 | 9.47567e-20 | PASS |
| random 48 FIX | 428978 | 1e-09 | 6.48787e-16 | 2.16616e-15 | 1.53733e-16 | 7.68666e-17 | 3.75343e-17 | 7.68666e-17 | 2.79349e-20 | PASS |
| random 49 PIN | 702790 | 1.56051e-09 | 5.73652e-13 | 3.28752e-12 | 1.9595e-13 | 6.86631e-14 | 3.43246e-14 | 6.86631e-14 | 4.8572e-17 | PASS |
| random 49 FIX | 137650 | 1e-09 | 7.79654e-14 | 1.43831e-12 | 5.76623e-14 | 3.56748e-14 | 1.12969e-14 | 3.56607e-14 | 1.15895e-17 | PASS |
