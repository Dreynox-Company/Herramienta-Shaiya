"""Build both Windows apps, stopping on any failed test; never modify game DATA."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    if os.name != 'nt':
        raise RuntimeError('Esta compilación nativa requiere Windows.')
    flutter = shutil.which('flutter')
    dart = shutil.which('dart')
    if not flutter or not dart:
        raise RuntimeError('Flutter/Dart no están en PATH. Instala tu SDK y verifica flutter doctor.')
    output = ROOT / '.build-logs'
    output.mkdir(exist_ok=True)
    logfile = output / ('control-vuelo-' + time.strftime('%Y%m%d-%H%M%S') + '.log')
    with logfile.open('x', encoding='utf-8') as log, tempfile.TemporaryDirectory(prefix='shaiya-key-') as temp:
        env = os.environ.copy()
        env['SHAIYA_FIXTURE_PATH'] = str(Path(temp) / 'fixture')
        env['SHAIYA_QA_PATH'] = str(ROOT / 'qa-native')

        def run(command, cwd=ROOT):
            title = '\n> ' + subprocess.list2cmdline([str(x) for x in command])
            print(title, flush=True)
            log.write(title + '\n')
            process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
                log.flush()
            if process.wait():
                raise RuntimeError('Etapa fallida. Registro: ' + str(logfile))

        run([flutter, '--version'])
        run([sys.executable, 'tool/prepare.py', '--platforms', 'windows'])
        run([flutter, 'pub', 'get', '--enforce-lockfile'])
        run([dart, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test', 'tool'])
        run([flutter, 'analyze'])
        run([flutter, 'test'])
        run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tool/tests', '-v'])
        run([sys.executable, 'tool/make_native_fixture.py', env['SHAIYA_FIXTURE_PATH']])
        run([flutter, 'test', 'integration_test/native_studio_test.dart', '-d', 'windows', '--reporter', 'expanded'])
        run([flutter, 'build', 'windows', '--release'])
        run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tool/smoke_windows.ps1'])
        # Packaging needs git provenance. A sources ZIP without .git can still
        # produce the EXEs, but never attributes binaries to an invented commit.
        has_git = (ROOT / '.git').exists()
        if has_git:
            run([sys.executable, 'ci/package_windows.py'])
        env['SHAIYA_QA_PATH'] = str(ROOT / 'qa-game')
        run([flutter, 'test', 'integration_test/local_game_test.dart', '-d', 'windows', '--reporter', 'expanded'])
        run([sys.executable, 'tool/prepare_local_game.py', '--platforms', 'windows'])
        game = ROOT / 'ingenieria_inversa/flutter_game'
        run([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=game)
        run([flutter, 'build', 'windows', '--release'], cwd=game)
        if has_git:
            run([sys.executable, 'ci/package_local_game.py'])
        else:
            print('EXE disponibles en build/windows/.../Release y en ingenieria_inversa/flutter_game/build/windows/.../Release.')
            print('Sin historial Git: no se generaron ZIP con una procedencia no comprobada.')
    print('Ambas compilaciones y pruebas nativas terminaron correctamente. Registro:', logfile)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print('ERROR:', error, file=sys.stderr)
        sys.exit(1)
