"""Preflight the generated runner; full Win32 behavior remains a Windows CI gate."""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import prepare


class WindowsIconTests(unittest.TestCase):
    def test_runner_refresh_is_idempotent_and_upgrades_older_block(self):
        template = 'prefix\n  window.Create(L"herramienta_shaiya", 1280, 720);\n  window.SetQuitOnClose(true);\nsuffix\n'
        expected = prepare.brand_windows_runner(template)
        self.assertEqual(prepare.brand_windows_runner(expected), expected)
        old = expected.replace('small_icon', 'small').replace('large_icon', 'big')
        self.assertEqual(prepare.brand_windows_runner(old), expected)
        self.assertEqual(expected.count('SHSTUDIO_RUNTIME_ICON:'), 1)
        self.assertIn('prefix\n', expected)
        self.assertTrue(expected.endswith('suffix\n'))
        self.assertIn('L"ShStudio"', expected)
        self.assertIn('1440, 900', expected)

    def test_unknown_or_ambiguous_template_is_rejected(self):
        for text in ('unrecognized', '  window.SetQuitOnClose(true);\n  window.SetQuitOnClose(true);'):
            with self.assertRaises(RuntimeError):
                prepare.brand_windows_runner(text)

    def test_cpp_icon_block_compiles_when_sdk_defines_small(self):
        compiler = shutil.which('c++') or shutil.which('g++') or shutil.which('clang++')
        if compiler is None:
            self.skipTest('C++ frontend unavailable; Windows native build tests the actual SDK.')
        # Win32 declarations are minimal syntax stubs, not a simulated window.
        # The troublesome SDK macro is intentionally present, never undefined.
        declarations = r'''
#include <string>
#include <cstdint>
#define small char
using HICON = void*;
using DWORD = unsigned long;
using LPARAM = std::intptr_t;
constexpr int IMAGE_ICON=1, SM_CXICON=2, SM_CYICON=3, SM_CXSMICON=4,
  SM_CYSMICON=5, LR_LOADFROMFILE=6, WM_SETICON=7, ICON_BIG=8, ICON_SMALL=9;
void DestroyIcon(HICON);
DWORD GetModuleFileNameW(void*, wchar_t*, DWORD);
void* LoadImageW(void*, const wchar_t*, int, int, int, int);
int GetSystemMetrics(int);
void SendMessageW(void*, int, int, LPARAM);
struct Window { void* GetHandle(); };
void check_generated_block(Window& window) {
'''
        with tempfile.TemporaryDirectory() as td:
            source = pathlib.Path(td) / 'runner_icons.cpp'
            source.write_text(declarations + prepare.WINDOWS_ICONS + '\n}\n', encoding='utf-8')
            run = subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                                  '-fsyntax-only', str(source)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == '__main__':
    unittest.main()
