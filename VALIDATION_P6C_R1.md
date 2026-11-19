# BeamCX v0.6.1 — P6C-R1

**PC IMPLEMENTATION/PASS — HARDWARE PENDING.** 2026-11-19.

Catálogo de secciones para dos grupos del pórtico, Columns / Beam, y peso
propio opcional exclusivamente de la viga. La UI productiva usa la misma
ruta `on.timer → PortalPreset.solve → Frame.solve`, una vez por modelo
desactualizado. No se modifican física, catálogo ni los 14 `bp_*`.

## Baseline y alcance

HEAD inicial: `dc20eba7ce8ba540096bb1ea54e70bcd699b96f3`; árbol limpio.
P6C-0 está aceptada por el propietario en la CX original. La limpieza de
los cinco archivos de equivalencia ya estaba aplicada; no se repite ni se
altera la evidencia estática de `VALIDATION_P6C0.md`.

Antes de editar se registraron estado, HEAD y hashes en
`/tmp/beamcx-p6cr1/`; el bundle P6C-0 generado se conservó allí como
`baseline.lua`, SHA-256
`7c9ff32e9fc8b8e48435d2ef0e16c2e6153ef13c7647b8d7b4f1d019c9c68527`.
No se introduce un fixture permanente de bundle completo.

Cambios productivos limitados a `beam_ui.lua`, `beam_ui_portal.lua` y
`beam_ui_sections.lua`. `build.py` cambia únicamente `v0.6.0` a `v0.6.1`.
Las vistas single/continuous, el empaquetador y los fixtures históricos
permanecen intactos. Se amplían harnesses y renderer existentes; siguen
existiendo exactamente 16 suites.

## Implementación y reutilización

| Pieza implementada | Infraestructura reutilizada |
| --- | --- |
| Dos secciones independientes, una común a ambas columnas | Copias de `default_section`, mismo esquema de cinco campos |
| E, I, EI, peso y procedencia | `SectionDB.compute`; RECT conserva b·h³/12 |
| EIc/EIb derivados | `recalc()`, con validación por `PortalPreset.model` |
| Selección de grupo/material/perfil y edición b/h/EI | `section_rows`, `active_section_index`, `apply_edit`, `step_selection`, `commit` |
| Página de catálogo del pórtico | `draw_section`, `fitted`, desplazamiento existente |
| Ciclo Entrada → Resultados → Secciones → Entrada | `on.tabKey`, páginas existentes 1/2/3 |
| Peso propio de viga | Booleano y copia de parámetros antes de `PortalPreset.solve` |
| Filas de procedencia | `cache_portal`, `row()`, tabla y `fitted` existentes |
| Persistencia atómica de secciones | Validador de `section` factorizado dentro de `valid_document` |
| Oráculos, eventos y gráficos | `portal_ui.lua`, `portal_reference.py`, `portal_graphics.lua`, `portal_contact.lua`, `render_portal_ui.py`, `current_documents.lua`, snapshot existente |

El estado nuevo es `portal_sections`, `portal_section_group` y
`portal_beam_self_weight`. `active_section()` parametriza la infraestructura
existente; no hay handlers paralelos, constructor alternativo de modelo,
catálogo duplicado ni framework. Las copias guardadas para rollback siguen
la transacción existente.

`recalc()` obtiene ambas propiedades, valida una copia con EI derivados y
carga efectiva y sólo entonces actualiza las cachés `portal.EIc/EIb` y marca
el resultado stale. En MANUAL se conservan 10000 / 15000 kNm² por defecto.
El EI numérico de entrada edita `manualEI` del grupo correspondiente, sin
depender del grupo visible; un grupo de catálogo responde con el mensaje
existente `EI from section; use TAB`.

El temporizador resuelve una copia con `q = portal.q + q_sw` si está ON.
`portal.q` nunca se sustituye ni acumula peso propio. MANUAL fuerza OFF si
no hay `q_sw`. Columns muestra `Excluded (axial)`, no editable: no se añaden
cargas axiales equivalentes ni fuerzas nodales. EA sigue siendo
`1e6·EI/L²` dentro del módulo congelado; no se calcula E·A físico.

La sección del pórtico usa filas de 14 px y fuente de 9 puntos para mostrar
también la exclusión de columnas con hormigón a 318×212. Vigas simples y
continuas mantienen sus medidas. Los resultados incorporan tres filas de
procedencia con etiquetas de `SectionDB.compute`, añadiendo el material.
La cabecera muestra `sw=…` sólo al estar ON; las flechas usan q efectiva.
Los pies indican `TAB sections`, conforme al ciclo de navegación.

## Pruebas y oráculos

**16/16 suites PASS en Lua 5.1.5 y liblua 5.4.7**
(`liblua5.4-0` 5.4.7-1+b2). La ejecución completa incluye las nuevas pruebas
dentro de `test_portal_ui.py`, sin una suite adicional. Después de corregir
los cierres gráficos del selector se repitió `test_selector.py` en ambos VM:
PASS a los tres tamaños; el nuevo test fallaba antes de la corrección.

Se conservan 394 filas Frame (265+129), 2042 casos históricos de vigas,
300 modelos continuos independientes, 136 modelos P6A y seis testigos
clásicos. Los criterios numéricos P6A y sus fixtures no se alteran.
También pasan las cinco pruebas del empaquetador y su guardia USB.

| Caso de catálogo, peso ON | EIc kNm² | EIb kNm² | q_sw kN/m | Resultado |
| --- | ---: | ---: | ---: | --- |
| HEA 200 S235 / IPE 300 S235 | 7753.2 | 17547.6 | 0.413982 | PASS |
| RECT 250×450 C20/25 / IPE 300 S235 | 56953.125 | 17547.6 | 0.413982 | PASS |
| MANUAL / RECT 300×500 C25/30 | 10000 | 96875 | 3.75 | PASS |

En cada caso los EI efectivos son idénticos, sin tolerancia, a
`SectionDB.compute`. La solución de la UI coincide estructural y
numéricamente con la llamada directa al mismo `PortalPreset.solve`, con
entradas idénticas. Se contrastan además reacciones, esfuerzos, extremos,
desplazamientos nodales, derivas y flecha relativa con la referencia
independiente Decimal de 50 dígitos existente. Se mantienen las escalas de
fuerza/momento y la tolerancia de desplazamiento P6A:
`max(1e-9, 10·kappa·epsilon)`; los tres casos quedan en 1e-9.

Testigo Kleinlogel: FIX, h=4 m, l=6 m, q_usuario=10 kN/m, peso ON.
`k=(EIb/l)/(EIc/h)` y `N1=k+2`. La función de referencia añadida sólo
prepara testigos; no modifica el ensamblaje ni la solución P6A.

| Magnitud | Kleinlogel / esperado | UI con EA finito | Resultado |
| --- | ---: | ---: | --- |
| EIc kNm² | 7753.2 | 7753.2 | PASS |
| EIb kNm² | 17547.6 | 17547.6 | PASS |
| q_sw kN/m | 0.413982 | 0.413982 | PASS |
| q_total kN/m | 10.413982 | 10.413982 | PASS |
| k | 1.508848 | 1.50884795955 | PASS |
| M esquina viga kNm | −17.8075233582 | −17.8074719737 | PASS |
| \|M base\| kNm | 8.90376167909 | 8.90367623920 | PASS |
| \|empuje\| kN | 6.67782125931 | 6.67778705323 | PASS |
| M centro viga kNm | 29.0553956418 | 29.0554470263 | PASS |

Los esfuerzos del testigo analítico usan tolerancia relativa 1e-4 por la
aproximación axial. Las propiedades y la paridad con la ruta directa no
usan esa tolerancia para ocultar diferencias. No se ajustó ninguna constante
física. El default reproduce P6B: M esquina ≈−20, M centro ≈25, N viga
≈−7.5; reacciones, barras y los 14 `bp_*` coinciden con la ruta original.

Las pruebas incluyen ON frente a q+q_sw, dos recálculos sin acumulación,
q_usuario intacta, paso a MANUAL con OFF, imposibilidad de activar peso de
columnas, grupos/materiales independientes, bloqueo de EI automático,
edición manual y ausencia de solves durante edición de secciones. Se
mantienen un solve diferido, cero solves al pintar/navegar y rollback de
modelo, secciones, flag y caché tras un fallo del temporizador.

## Persistencia y CAS

Formato estricto **0.6.1**. Campos nuevos: `portal_sections` con ambos grupos,
`portal_section_group` y `portal_beam_self_weight`. Se admite page=3; el resto
del modelo, cursor y modo conserva el contrato existente. Restaurar resultados
abre entrada y espera el cálculo diferido normal.

| Comprobación | Resultado |
| --- | --- |
| Round-trip completo y preciso 0.6.1, página 3 y grupo Beam | PASS |
| EI guardados contradictorios −77/0: prevalecen los grupos antes de validar, incluso con otro sistema activo | PASS |
| Documento de entrada sin mutaciones durante la validación | PASS |
| Rechazo 0.6.0 y ambos testigos históricos 0.5 | PASS |
| Grupo ausente, tipo erróneo, material/perfil inválido, dimensiones o EI inválidos/no finitos | PASS |
| Peso ON sin q_sw, flag de tipo incorrecto o grupo activo inválido | PASS |
| Modelo físico inválido o carga de tipo incorrecto | PASS |
| Tras rechazo: defaults completos, sin restauración parcial | PASS |

El validador calcula propiedades de ambos grupos en variables locales,
sobrescribe EI en una copia de los parámetros, comprueba la compatibilidad
del peso y llama a `PortalPreset.model` con carga efectiva. Sólo devuelve
el candidato aceptado después de validar el documento completo. El q
usuario se conserva al publicar el estado; no hay migración de 0.6.0.
El aviso continúa siendo `Invalid document or version: defaults restored`.

`export_cas` no cambia: catorce `bp_*` con iguales nombres, orden, unidades,
significados, validación y tratamiento de errores. El resultado exportado
incluye el peso propio cuando corresponde. Se mantienen las comprobaciones
de los ocho `bx_*` y ocho `bc_*`.

## Regresión gráfica

El harness existente comprueba 318×212, 320×212 y 320×240, todos los modos,
filas de entrada/tabla, materiales mixtos, grupos y cargas con signo. El
recorder exige geometría dentro del viewport y ausencia de solapes de texto.
Los casos con q_usuario cero o negativo y q_total positiva verifican también
que las flechas sigan la carga efectiva.

La comparación temporal con el bundle P6C-0 da **1800 streams ordenados de
comandos idénticos** para secciones de los cuatro presets y CONTINUOUS:
seis materiales, dos perfiles, tres tamaños y diez posiciones de foco.
Sólo se normaliza el texto de versión del encabezado. Script y log:
`/tmp/beamcx-p6cr1/sections_unchanged.lua` y `sections-unchanged.log`; no se
añade un fixture, framework o dependencia para futuras pruebas ordinarias.

`PORTAL_UI_CONTACT.png` contiene 14 pantallas del bundle real, generadas por
el renderer existente. Las cuatro añadidas muestran Columns HEA 200 S235
con `Excluded (axial)`, Beam IPE 300 S235 con ON, cabecera `sw=0.41` y
M=29.06, y las tres filas de procedencia. Es simulación PC con las fuentes
del renderer; no se infiere un resultado físico de la imagen.

La revisión posterior identificó cortes reales en el trazo naranja de M
de la tarjeta PORTAL: faltaban las ordenadas de cierre en bases y esquinas.
Se añadieron seis segmentos hasta el marco, conservando los trazos originales,
colores y escalas. `test_selector.py` comprueba ahora que ningún extremo
naranja queda aislado fuera de los nodos del marco, a los tres tamaños.
Las otras cinco tarjetas, el marco blanco y la física no cambian. La hoja
de contacto y el paquete incluyen esta corrección de presentación solicitada
por el propietario; la comprobación anterior de pilares/dintel no cubría
la continuidad del trazo naranja.

## Diff, presupuesto y build

Los cinco módulos congelados conservan estos SHA-256, idénticos al baseline:

```text
4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b  src/frame_core.lua
b205832ce2f7ba4371456f9898ca40611c8c589d87abdff92c50c55f424feede  src/beam_preset.lua
16186de935f91b57c5785be27880bc5d46f45de497148c01b340a8657bf1073d  src/continuous_preset.lua
921ebbf5d15bd27481e71c99440e857d87c448d4c83d2a30fcc818b6510312cf  src/portal_preset.lua
46b102cf8a56d0a0d621b23aaf8170e2825f6340aaedd87fefb3654f4c17c641  src/section_db.lua
```

También permanecen intactos los fixtures históricos, `tools/package.py`,
`beam_ui_single.lua` y `beam_ui_continuous.lua`. `build.py` sólo cambia el
encabezado de versión. El snapshot añade únicamente lecturas para observar
los grupos y la selección en los harnesses existentes.

| Archivo en src | Añadidas | Eliminadas | Neto |
| --- | ---: | ---: | ---: |
| beam_ui.lua | 125 | 50 | +75 |
| beam_ui_portal.lua | 9 | 5 | +4 |
| beam_ui_sections.lua | 22 | 14 | +8 |
| Total | **156** | **69** | **+87** |

`luac5.1 -p -l -l BeamCX.lua`: **146 locales** top-level (baseline 142,
límite 150), **35 upvalues** máximos por función (baseline 32, límite 50).
148 slots en el chunk principal. No runtime require/dofile ni nuevos globals
productivos. El crecimiento neto queda por debajo de aproximadamente 150
líneas y corresponde a la extensión de rutas existentes.

| Artefacto | P6C-0 | v0.6.1 |
| --- | ---: | ---: |
| BeamCX.lua empaquetado | 125001 bytes | 130679 bytes |
| BeamCX.tns | 34896 bytes | 36119 bytes |
| Último paquete USB | 252 bytes | 210 bytes |

Guardia `(17 + size % 253) % 64 != 0`: **PASS**. El build Lua produce 130655
bytes; el empaquetador añadió su comentario de padding existente (+24 bytes)
tras rechazar un primer TNS de 36101 bytes con paquete USB final de 192 bytes.
El segundo intento genera el TNS seguro indicado arriba.
`tools/package.py` permanece intacto. Lua/TNS se generaron en el workspace;
siguen ignorados por Git según la configuración existente.

SHA-256 finales:

```text
d30ec6dd23166763fd2069c2231203e26fa0d034e1fc9002848e1733517a27dd  BeamCX.lua
f5e1c88051940c34d9e1cdfad17623a83ac5be22722a26de8d1ab1d319d2369d  BeamCX.tns
11117ee310fc834d0eb02f04cdf2b876e79d71d1d7113611a298e263fb9e6613  PORTAL_UI_CONTACT.png
```

Cinco módulos congelados: SHA-256 idénticos al baseline:

```text
4eeb568504db1b9471b8aef72934f8bf70d7f2dd8dccd47204f092feeb807e4b  src/frame_core.lua
b205832ce2f7ba4371456f9898ca40611c8c589d87abdff92c50c55f424feede  src/beam_preset.lua
16186de935f91b57c5785be27880bc5d46f45de497148c01b340a8657bf1073d  src/continuous_preset.lua
921ebbf5d15bd27481e71c99440e857d87c448d4c83d2a30fcc818b6510312cf  src/portal_preset.lua
46b102cf8a56d0a0d621b23aaf8170e2825f6340aaedd87fefb3654f4c17c641  src/section_db.lua
```

Comandos ejecutados con PASS:

```bash
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
python3 tests/run_suites.py
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tests/render_portal_ui.py
python3 tools/package.py
luac5.1 -p -l -l BeamCX.lua
sha256sum -c /tmp/beamcx-p6cr1/frozen.sha256
git diff --check
```

Logs finales: `/tmp/beamcx-p6cr1/suites51-final.log` y `suites54-final.log`.
No commit, push ni release. No se han implementado peso de columnas,
EA físico, P-Delta, nuevos perfiles, cargas o geometrías.

## Checklist del propietario — CX original

1. Transferir `BeamCX.tns` sin bloqueo.
2. Default: M esquina ≈−20 kNm, M centro ≈25 kNm, N viga ≈−7.5 kN.
3. Columns HEA 200 S235 / Beam IPE 300 S235, peso ON: M centro ≈29.06 kNm
   y cabecera `sw=0.41`.
4. Columns: `Excluded (axial)`, sin posibilidad de activación.
5. Guardar, cerrar y reabrir: ambos grupos, grupo activo y peso correctos.
6. Vigas simples y continuas: catálogo y edición sin regresión.

La transferencia, legibilidad y respuesta de esta versión necesitan prueba
del propietario en la TI-Nspire CX CAS original. **No se declara hardware
PASS para v0.6.1.**
