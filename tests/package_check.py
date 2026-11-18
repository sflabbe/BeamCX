"""Focused Python checks; the 11 existing Lua suites remain unchanged."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('package', Path(__file__).resolve().parents[1]/'tools/package.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class PackageTests(unittest.TestCase):
    def test_hardware_witness_sizes(self):
        for size, last, bad in ((11938,64,True), (12006,132,False), (20604,128,True),
                                (20721,245,False), (20732,256,True), (20733,257,False)):
            with self.subTest(size=size):
                self.assertEqual(pack.last_packet_size(size), last)
                self.assertEqual(pack.unsafe_size(size), bad)

    def test_same_guard_for_app_and_bench(self):
        for name in ('BeamCX', 'bench'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                lua, output = Path(tmp)/(name+'.lua'), Path(tmp)/'output.tns'
                original = b'print("test")\n'
                lua.write_bytes(original)
                def luna(command, check):
                    self.assertTrue(check)
                    self.assertEqual(command[1:], [str(lua), str(output)])
                    output.write_bytes(b'x'*(20604 if lua.read_bytes()==original else 20733))
                with patch.object(pack.subprocess, 'run', side_effect=luna) as run:
                    self.assertEqual(pack.package(lua, output), 20733)
                    self.assertEqual(run.call_count, 2)
                self.assertEqual(lua.read_bytes(), original+b'-- N-Link USB padding 1\n')

    def test_safe_size_preserves_lua(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua, output = Path(tmp)/'BeamCX.lua', Path(tmp)/'output.tns'
            lua.write_bytes(b'return 1')
            output.write_bytes(b'x'*20721)
            with patch.object(pack.subprocess, 'run') as run:
                pack.package(lua, output)
                self.assertEqual(run.call_count, 1)
            self.assertEqual(lua.read_bytes(), b'return 1')

    def test_eight_attempt_limit(self):
        with tempfile.TemporaryDirectory() as tmp:
            lua, output = Path(tmp)/'BeamCX.lua', Path(tmp)/'output.tns'
            lua.write_bytes(b'return 1\n')
            output.write_bytes(b'x'*20732)
            with patch.object(pack.subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'after 8 attempts'):
                    pack.package(lua, output)
                self.assertEqual(run.call_count, 8)
            self.assertEqual(lua.read_bytes().count(b'-- N-Link USB padding'), 7)

    def test_packager_failure_propagates(self):
        with patch.object(pack.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'luna')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                pack.package(Path('missing.lua'), Path('missing.tns'))
            self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
