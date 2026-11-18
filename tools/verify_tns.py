"""Read Luna a9924a9 TNS containers and recover Lua using independent DEFLATE.

Only doccrypt (the symmetric TI counter-stream transform) comes from unchanged
Luna sources. Container/CRC parsing and inflation use Python's standard library.
"""
import argparse
import ast
import binascii
import ctypes
import hashlib
from pathlib import Path
import re
import struct
import zlib


def c_bytes(source, name):
    body = re.search(r'\b' + re.escape(name) + r'\[\]\s*=\s*(.*?);', source, re.S)
    assert body, f'missing pinned Luna constant: {name}'
    return b''.join(ast.literal_eval('b"' + s + '"')
                    for s in re.findall(r'"((?:\\.|[^"\\])*)"', body[1]))


def entries(data):
    assert data.startswith(b'*TIMLP0500'), 'not a TI-Nspire TNS document'
    end = len(data) - 22
    sig, disk, cd_disk, count, total, size, start, comment = struct.unpack_from('<4s4H2IH', data, end)
    assert (sig, disk, cd_disk, count, total, comment) == (b'TIPD', 0, 0, 2, 2, 0), 'invalid TI directory footer'
    assert start + size == end, 'directory bounds mismatch'
    pos, cursor, result = start, 0, {}
    for i in range(total):
        h = struct.unpack_from('<4s6H3I5H2I', data, pos)
        assert h[0] == b'PK\x01\x02' and h[13] == 0, 'invalid directory entry'
        name_len, extra_len, comment_len = h[10:13]
        name = data[pos+46:pos+46+name_len].decode('ascii')
        assert name not in result and h[16] == cursor, 'duplicate or overlapping entry'
        magic = 10 if i == 0 else 4
        if i:
            assert data[cursor:cursor+4] == b'PK\x03\x04', 'invalid local header'
        local = struct.unpack_from('<5H3I2H', data, cursor+magic)
        assert local[:5] == h[2:7] and local[5:8] == h[7:10], 'local/directory mismatch'
        assert local[8:10] == (name_len, extra_len), 'local name/extra length mismatch'
        assert h[2] == 20 and h[3] == 0 and h[4] == 13, 'unexpected TI entry method/flags'
        assert h[8] == h[9] and extra_len == comment_len == 0, 'invalid stored TI payload'
        offset = cursor + magic + 26
        assert data[offset:offset+name_len] == name.encode('ascii'), 'local name mismatch'
        offset += name_len + extra_len
        payload = data[offset:offset+h[8]]
        assert len(payload) == h[8] and binascii.crc32(payload) == h[7], 'entry CRC/length mismatch'
        result[name] = payload
        cursor = offset + len(payload)
        pos += 46 + name_len + extra_len + comment_len
    assert cursor == start and pos == end, 'container has gaps or trailing records'
    assert set(result) == {'Document.xml', 'Problem1.xml'}, 'unexpected document structure'
    return result


def verify(tns, lua, luna_source, crypto_library, zlibng_version=None):
    source = luna_source.read_text()
    data, script = tns.read_bytes(), lua.read_bytes()
    files = entries(data)
    assert files['Document.xml'] == c_bytes(source, 'default_processed_document_xml'), 'default document mismatch'
    header = c_bytes(source, 'tien_crypted_header')
    assert files['Problem1.xml'].startswith(header), 'invalid TI encryption header'
    encrypted = files['Problem1.xml'][len(header):]
    crypto = ctypes.CDLL(str(crypto_library.resolve()))
    crypto.doccrypt.argtypes = [ctypes.c_void_p, ctypes.c_long]
    crypto.doccrypt.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(encrypted)
    assert crypto.doccrypt(buffer, len(encrypted)) == 0, 'TI decryption failed'
    inflater = zlib.decompressobj(-15)
    xml = inflater.decompress(buffer.raw[:len(encrypted)]) + inflater.flush()
    assert inflater.eof and not inflater.unused_data and not inflater.unconsumed_tail, 'invalid raw DEFLATE stream'
    prefix, suffix = c_bytes(source, 'lua_header'), c_bytes(source, 'lua_footer')
    assert xml.startswith(prefix) and xml.endswith(suffix), 'invalid Lua application envelope'
    recovered = xml[len(prefix):-len(suffix)].replace(b']]><![CDATA[', b'')
    assert recovered == script, 'recovered Lua differs from build.py output'
    assert xml == prefix + script.replace(b']]>', b']]]]><![CDATA[>') + suffix, 'invalid CDATA structure'
    if zlibng_version:
        crypto.zlibVersion.restype = ctypes.c_char_p
        assert crypto.zlibVersion() == b'1.3.1.zlib-ng', 'wrong compression provider'
        expected_version = (' zlib-ng ' + zlibng_version).encode('ascii')
        version = (ctypes.c_char * (len(expected_version)+1)).in_dll(crypto, 'z_vstring').value
        assert version == expected_version, 'wrong zlib-ng version'
        actual_version = zlibng_version
        crypto.deflate_compressed_xml.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        crypto.deflate_compressed_xml.restype = ctypes.c_long
        output = ctypes.create_string_buffer(len(xml) + len(xml)//10 + 12)
        length = crypto.deflate_compressed_xml(output, len(output), xml, len(xml))
        assert output.raw[:length] == buffer.raw[:len(encrypted)], 'DEFLATE differs from pinned zlib-ng'
        print(f'PASS zlib-ng {actual_version}: recompressed DEFLATE is byte-identical')
    print(f'PASS TI-Nspire TNS: {tns} ({len(data)} bytes); directory, entries and CRC valid')
    print(f'PASS raw DEFLATE: {len(encrypted)} bytes; TI payload {len(files["Problem1.xml"])} bytes')
    print(f'PASS recovered Lua: {len(recovered)} bytes, byte-identical; SHA-256 {hashlib.sha256(recovered).hexdigest()}')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tns', type=Path)
    parser.add_argument('lua', type=Path)
    parser.add_argument('--luna-source', type=Path, required=True)
    parser.add_argument('--crypto-library', type=Path, required=True)
    parser.add_argument('--zlibng-version', help='also require byte-identical recompression with this provider/version')
    args = parser.parse_args()
    verify(args.tns, args.lua, args.luna_source, args.crypto_library, args.zlibng_version)


if __name__ == '__main__':
    main()
