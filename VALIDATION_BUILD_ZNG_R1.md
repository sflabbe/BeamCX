# BUILD-ZNG-R1 + P2B.2 — validación local

2026-11-18. Implementación completada. Sin commit ni push. Transferencia de los nuevos paquetes pendiente de prueba del propietario.

## Construcción y enlace

Entorno: LMDE 7 sobre Debian 13.0/trixie, GCC 14.2.0-19 y CMake 3.31.6. La instalación original `~/Luna/luna` enlaza dinámicamente con `/lib/x86_64-linux-gnu/libz.so.1`; su Makefile usa `-lz`.

La variante aislada conserva las fuentes de Luna **a9924a9a968954eba9adcc161a58ac607f97ce8c** sin cambios. Usa zlib-ng **2.2.4**, commit **860e4cff7917d93f54f5d7f0bc1d0e8b1a3cb988**, en modo compatible (`ZLIB_COMPAT=ON`), Release y biblioteca estática. Las opciones completas están en README y `tools/build_tns_zlibng.sh`.

El enlace pasa la ruta absoluta de `libz.a`, sin `-lz`. El mapa identifica `libz.a(deflate.c.o)` como proveedor de `deflate`; `nm` confirma su definición dentro del ejecutable y `ldd`/`readelf` confirman que no depende de libz compartida. El verificador comprueba `zlibVersion() = 1.3.1.zlib-ng`, la cadena interna `zlib-ng 2.2.4` y la recompresión idéntica del flujo DEFLATE. El helper de verificación usa `-Bsymbolic` para impedir que la zlib cargada por Python sustituya sus símbolos; no interviene en el empaquetado.

No se modificaron las bibliotecas globales de Debian ni la instalación original de Luna. Fuentes descargadas, objetos, bibliotecas y evidencia del enlace quedan en `.build-zng/`, ignorado por Git.

## Paquetes y guardia USB

| Archivo entregado | Tamaño | Último paquete USB |
| --- | ---: | ---: |
| `BeamCX.tns`, clásico con un comentario de relleno | 20.621 bytes | 145 bytes |
| `BeamCX-zng.tns`, mismo Lua final | 20.866 bytes | 137 bytes |
| `BXBENCH.tns`, sin relleno | 13.778 bytes | 133 bytes |

`tools/package.py` comparte la misma función para aplicación y benchmark. Rechaza `(17 + size % 253) % 64 == 0`, añade comentarios únicamente al final del Lua generado y permite como máximo ocho ejecuciones de Luna. El clásico inicial de 20.604 bytes activó la guardia; bastó un comentario. Su copia de diagnóstico se conserva en `.build-zng/BeamCX-classic-20604.tns`.

Ambas variantes de BeamCX contienen el mismo Lua de **66.244 bytes**, incluidos los 24 bytes del comentario añadido. SHA-256:

- Lua: `1482da090be8d4cc4eb51d7c3089e6a25877ff00c0005087e3e1bae19d9e2a60`.
- Clásico: `8f33b26cb7cd4c5d3aacf87fcaf4eefb2315062fd53f5f96e80cca7f1c517349`.
- zlib-ng: `0f85cf90e9cbb2d8372ee1b365fcd935a73fce553eecbbff1900270b9783a849`.

Con el Lua original de 66.220 bytes, zlib-ng 2.2.4 produjo 20.849 bytes, frente a los 20.721 del testigo funcional local. Se verificaron ambos: recuperan exactamente el mismo script. Sus payloads TI son 20.317 y 20.189 bytes respectivamente (incluyen 40 bytes de cabecera de cifrado); sus flujos DEFLATE son 20.277 y 20.149 bytes. La versión/configuración del testigo es desconocida; no se exige identidad binaria. La repetición local del flujo fijado de build y guardia reprodujo todos los artefactos byte por byte.

La causa del bloqueo USB y los experimentos de 20.732/20.733 bytes proceden de la confirmación del propietario en hardware. README recoge la regla y los seis archivos observados, incluidos los incidentes al 91 % y 97 %. No se atribuye el fallo a zlib clásico. La guardia de PC no equivale a una transferencia física de estos nuevos paquetes.

## Verificaciones ejecutadas

- `./tools/build_tns_zlibng.sh`: compilación, enlace explícito, sintaxis Lua 5.1, empaquetado y recuperación exacta: PASS.
- `python3 tools/package.py`, `--bench` y `--luna .build-zng/luna/luna --output BeamCX-zng.tns`: PASS.
- `python3 tools/verify_tns.py …`: los tres paquetes finales, el clásico inicial y el testigo de 20.721 bytes: cabecera TI-Nspire, directorio, límites de entradas, CRC, DEFLATE completo, envoltura y Lua exacto: PASS.
- `python3 tests/package_check.py`: **5 tests PASS**, incluidos los seis tamaños, app/benchmark, ausencia de relleno innecesario, ocho intentos y propagación de errores de Luna.
- `python3 tests/run_suites.py`: **11/11 suites PASS, Lua 5.4.7**.
- `python3 tests/run_suites.py --lua lua5.1`: **11/11 suites PASS, Lua 5.1.5**.
- Se mantienen **394 filas Frame** y **2.042 entradas de equivalencia**: 2.009 ordinarias, 2 adjudicadas, 5 RESOLVED y 26 inválidas. La autoridad numérica sigue siendo P2B.1.
- Sintaxis de Bash/Python y `git diff --check`: PASS. `src/`, `build.py` y fixtures numéricos conservan sus hashes de entrada; el único cambio en el Lua generado es el comentario de relleno.
