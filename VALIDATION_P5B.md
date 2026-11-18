# BeamCX v0.5.0 — P5B / P5B-R1

2026-11-18. Interfaz continua activa. Validación local completa; aceptación en la calculadora pendiente del propietario. Sin commit.

## Comportamiento entregado

- Selector 3×2 con cinco sistemas, navegación que evita el hueco, esquema de tres vanos para CONTINUA, siluetas M normalizadas y rollback si falla el cálculo diferido. El arnés comprueba los nombres dentro de las tarjetas a 318×212, 320×212 y 320×240.
- Entrada continua con scroll, 2–5 vanos, luces, extremos PIN/FIX, g/q y factores. EI, catálogo y peso propio usan la página de secciones compartida. El peso propio se suma una sola vez a g. La comparación usa Lref igual a la luz de cada vano; L/250 o L/300 se selecciona en secciones.
- Editar descarta el resultado y la caché sin resolver. Entrar a resultados invalida la ventana, muestra **Calculando…** y arranca un timer de 0,05 s. `on.timer` lo detiene y ejecuta exactamente n+1 `Frame.solve`.
- Caché de 20 intervalos por vano: 21n consultas, incluidos ambos lados de los apoyos internos, más una consulta para inicializar el cursor. Se construye una sola vez por cálculo. `on.paint` no resuelve ni llama a `envelope_at`; las pruebas también prohíben recuperación `Frame.at` durante el dibujo continuo. Cambiar de modo o volver a resultados sin editar conserva el objeto de caché.
- Mmax/Mmin con M positivo abajo, Vmax/Vmin con saltos en apoyos, dos deformadas características impares/pares y tabla de vanos/apoyos. El cursor incluye los apoyos y realiza una sola consulta exacta por movimiento, con ambos lados del cortante disponibles desde la caché.
- Exportación explícita de ocho `bc_*` en continua, con `bc_wmax` en mm. El modo simple mantiene los ocho `bx_*`, el cálculo inmediato y sus testigos dorados. La convención visible de factores sigue siendo **γ: OPEN (EN 1990 A1 + NA)**.

## Persistencia P5B-R1

`on.save` emite el formato `0.5.0`. `on.restore` valida todos los campos antes de aceptar el documento completo. Cualquier campo inválido, ausente o de otra versión descarta todo el documento: parámetros, sección, ajustes, continua, modo, cursor y página vuelven a los valores por defecto, en el selector.

El aviso **Documento no válido o de otra versión: valores por defecto** permanece al repintar o guardar y se borra con la primera tecla. Se prueban por separado los campos inválidos y ausentes, un documento con L=0 y la forma real de `on.save` v0.4 sin `format` ni `continuous`. No hay migración ni mezcla de campos guardados con defaults. El foco se reinicia; no forma parte del documento. Restaurar resultados de continua abre entrada y no calcula hasta entrar a resultados.

El rechazo de un cálculo tras una **edición** se prueba por separado: no deja resultados viejos ni exportables. `quick_check.lua` navega explícitamente al perfil después de restore.

## Caso E

Entrada por eventos reales: 3×6 m, PIN–PIN, g=10, q=5, EI=10000, factores por defecto y peso propio OFF. Las tablas por vano/apoyo y el resumen son idénticos a `ContinuousPreset.solve` con los mismos parámetros.

| Variable | Valor comprobado |
| --- | ---: |
| `bc_mmax` | 66.0005357143 kNm |
| `bc_mmin` | −80.1 kNm |
| `bc_vabs` | 76.35 kN |
| `bc_rmax` | 143.1 kN |
| `bc_wmax` | 15.3264571214 mm |
| `bc_xwmax` | 2.75420947417 o 15.24579052583 m |
| `bc_ei` | 10000 kN·m² |
| `bc_n` | 3 |

Según P5B-R1 se aceptan ambas posiciones simétricas. Se exige igualdad exacta entre `bc_xwmax` y `summary.deflection_position`, y se recuperan ambas combinaciones características en esa posición para comprobar que alcanza la flecha máxima con tolerancia 1e-9. El caso asimétrico 4/5/8 m sigue seleccionando claramente el vano 3. No se introduce ninguna regla de desempate en el cálculo.

## Verificación ejecutada

Secuencia local idéntica al CI, completa en verde:

```bash
set -e
python3 build.py
luac5.1 -p BeamCX.lua
lua5.1 tests/quick_check.lua "$PWD"
for test in tests/test_*.py; do
  echo "Running $test"
  python3 "$test"
done
```

Los 13 `test_*.py` usan **liblua 5.4.7** (`liblua5.4-0` 5.4.7-1+b2). Se ejecutaron además las mismas 13 suites con **Lua 5.1.5**:

```bash
python3 tests/run_suites.py --lua lua5.1
python3 tests/package_check.py
python3 tools/package.py
luac5.1 -p BeamCX.lua
```

Resultados en ambos Lua:

- **394 filas numéricas Frame** conservadas.
- **2042 casos** del fixture dorado: 2009 equivalentes ordinarios, dos adjudicados, cinco RESOLVED y 26 inválidos; testigos P0 y los ocho `bx_*` preservados. Fixtures sin cambios.
- **P5A.1: 300 modelos, 1050 vanos y 4500 patrones**, con fuerza bruta exclusivamente en el arnés; n+1 solves y dos combinaciones en el preset. Máximos normalizados: M 2,99e-15, V 4,84e-16, R 2,19e-16, w 1,81e-15, posiciones/patrones por respuesta alcanzada 4,67e-15 y resumen 2,59e-15.
- Regresión de momento positivo en apoyo B: +28.081141172746, patrón `3`, γG=1.00.
- UI continua: caso E, cálculo diferido, caché única, signos y curvas, saltos V, cursor exacto, secciones/peso propio, límites, exportación, rollback y cancelación del timer. Se dibujan todas las pantallas con 2, 3, 4 y 5 vanos en 318×212, 320×212 y 320×240.
- Cinco pruebas del empaquetador en verde. `git diff --check` sin errores.

## Auditoría de alcance y ruta productiva

`frame_core.lua`, incluido `Frame.combine`, y `continuous_preset.lua` permanecen idénticos al inicio de P5B-R1; no se conserva el cambio de desempate autorizado en el mensaje anterior. `beam_preset.lua` y `section_db.lua` tampoco cambian.

No hay hooks de prueba en `src/`. La instrumentación y el snapshot viven en el arnés. Las funciones de UI tienen llamadores en dibujo, eventos o persistencia; `valid_document` se llama desde `on.restore`. La ruta continua productiva es entrada/secciones → parámetros → `on.timer` → `ContinuousPreset.solve` → resumen/tablas/CAS. El preset llama a `Frame.solve` y `Frame.combine`; la caché de deformadas usa además `Frame.combine` con las bases ya calculadas. No quedan componentes de P5B sin llamador productivo.

## Paquete

Generado mediante `python3 tools/package.py`, sin relleno necesario:

| Artefacto | Tamaño | Último paquete USB |
| --- | ---: | ---: |
| `BeamCX.lua` | 100080 bytes | — |
| `BeamCX.tns` | **28765 bytes** | **193 bytes** |

El paquete final cumple la guardia USB: `17 + (28765 % 253) = 193`, que no es múltiplo de 64.

SHA-256 de `BeamCX.tns`: `ab4a45233593238eff98c8842795b85a3e6c66d91b0c391b5a23d1bb52ba06d0`.
SHA-256 de `BeamCX.lua`: `bb3b9a874fa426e0ef3a7075b11c63d3e796d483dd11a619c94e761688e906d4`.

## Aceptación pendiente en la CX por el propietario

- [ ] Caso E, tablas y las ocho variables exportadas.
- [ ] Tiempo de cálculo y muestreo con cinco vanos, con Calculando… visible antes de empezar.
- [ ] Cursor fluido y lectura de ambos lados de V en apoyos.
- [ ] Exportación `bc_*` en Calculator del mismo problema.
- [ ] Save/restore en ambos modos, cálculo diferido tras restaurar continua y aviso de documento inválido.

No se ha realizado validación física de este paquete v0.5.0. Sin commit. STOP.
