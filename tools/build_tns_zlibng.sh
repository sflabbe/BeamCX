#!/usr/bin/env bash
# Isolated, pinned zlib-ng build; never overwrites BeamCX.tns or ~/Luna/luna.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work="$root/.build-zng"
luna_commit=a9924a9a968954eba9adcc161a58ac607f97ce8c
zng_commit=860e4cff7917d93f54f5d7f0bc1d0e8b1a3cb988 # zlib-ng 2.2.4
luna_repo=${LUNA_REPO:-"$HOME/Luna"}
mkdir -p "$work"
if [[ ! -d "$luna_repo/.git" ]]; then
    luna_repo="$work/luna-repo"
    if [[ ! -d "$luna_repo/.git" ]]; then
        git clone --no-checkout https://github.com/ndless-nspire/Luna.git "$luna_repo"
    fi
fi
if [[ ! -d "$work/zlib-ng/.git" ]]; then
    git clone --depth 1 --branch 2.2.4 https://github.com/zlib-ng/zlib-ng.git "$work/zlib-ng"
fi
[[ $(git -C "$work/zlib-ng" rev-parse HEAD) == "$zng_commit" ]]
[[ -z $(git -C "$work/zlib-ng" status --porcelain --untracked-files=no) ]]
git -C "$luna_repo" cat-file -e "$luna_commit^{commit}"
mkdir -p "$work/luna"
git -C "$luna_repo" archive "$luna_commit" | tar -x -C "$work/luna"
cmake -S "$work/zlib-ng" -B "$work/zlib-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DZLIB_COMPAT=ON -DBUILD_SHARED_LIBS=OFF \
    -DZLIB_ENABLE_TESTS=OFF -DZLIBNG_ENABLE_TESTS=OFF -DWITH_GTEST=OFF \
    -DWITH_NATIVE_INSTRUCTIONS=OFF -DWITH_RUNTIME_CPU_DETECTION=ON \
    -DWITH_OPTIM=ON -DWITH_NEW_STRATEGIES=ON
cmake --build "$work/zlib-build" --parallel 2
archive="$work/zlib-build/libz.a"
# The complete archive path replaces -lz; no system compression library is linked.
make -B -C "$work/luna" \
    CFLAGS="-O2 -flto -Wall -Wextra -DNOCRYPT -DUSE_FILE32API -Wno-unused-parameter -I$work/zlib-build" \
    LDFLAGS="-flto $archive -Wl,-Map,$work/luna-zng.map"
# Unmodified Luna sources expose doccrypt to the independent Python reader.
# This helper only verifies documents; it is never used to package them.
# -Bsymbolic prevents Python's loaded system zlib from interposing its symbols.
gcc -O2 -fPIC -shared -Wl,-Bsymbolic -Dmain=luna_cli_main -DNOCRYPT -DUSE_FILE32API \
    -I"$work/zlib-build" "$work/luna/luna.c" "$work/luna/DES.c" \
    "$work/luna/minizip-1.1/zip.c" "$work/luna/minizip-1.1/ioapi.c" \
    "$archive" -o "$work/luna-verify.so"
readelf -d "$work/luna/luna" > "$work/luna-dynamic.txt"
if grep -Eq 'NEEDED.*libz(-ng)?\.so' "$work/luna-dynamic.txt"; then
    echo 'ERROR: Luna unexpectedly depends on a shared zlib' >&2; exit 1
fi
nm --defined-only "$work/luna/luna" > "$work/luna-symbols.txt"
grep -Eq ' [Tt] deflate$' "$work/luna-symbols.txt"
grep -Eq ' [Tt] zlibVersion$' "$work/luna-symbols.txt"
grep -F "$archive(deflate.c.o)" "$work/luna-zng.map" >/dev/null
python3 "$root/build.py"
luac5.1 -p "$root/BeamCX.lua"
# Stage output until container, CRC, DEFLATE and byte-for-byte Lua checks pass.
python3 "$root/tools/package.py" --luna "$work/luna/luna" --output "$work/BeamCX-zng.tns"
python3 "$root/tools/verify_tns.py" "$work/BeamCX-zng.tns" "$root/BeamCX.lua" \
    --luna-source "$work/luna/luna.c" --crypto-library "$work/luna-verify.so" --zlibng-version 2.2.4
cp -- "$work/BeamCX-zng.tns" "$root/BeamCX-zng.tns"
{
    printf 'Luna commit: %s\nzlib-ng 2.2.4 commit: %s\n' "$luna_commit" "$zng_commit"
    cc --version | head -n 1
    cmake --version | head -n 1
    sha256sum "$archive" "$work/luna/luna" "$root/BeamCX.lua" "$root/BeamCX-zng.tns"
} > "$work/build-info.txt"
printf 'Built %s using zlib-ng 2.2.4 (static zlib-compatible archive).\n' "$root/BeamCX-zng.tns"
