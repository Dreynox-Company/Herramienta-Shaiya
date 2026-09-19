"""Generate the standalone Flutter game runner without touching game resources."""
from pathlib import Path
import argparse, subprocess, shutil
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--platforms',default='windows');a=p.parse_args()
    if not set(a.platforms.split(','))<={'windows','linux','android'}:raise ValueError('Plataforma inválida')
    game=ROOT/'ingenieria_inversa/flutter_game';flutter=shutil.which('flutter')
    if not flutter:raise RuntimeError('Flutter no está en PATH')
    names=['pubspec.yaml','pubspec.lock','lib/main.dart','analysis_options.yaml']
    original={name:(game/name).read_bytes() for name in names if (game/name).exists()}
    template=game/'test/widget_test.dart';old_test=template.read_bytes() if template.exists() else None
    try:
        subprocess.run([flutter,'create','--no-pub','--project-name','shaiya_local_game','--org','com.dreynox',f'--platforms={a.platforms}',str(game)],check=True)
    finally:
        for name,body in original.items():(game/name).write_bytes(body)
        if old_test is not None:template.write_bytes(old_test)
        elif template.exists() and 'counter increments' in template.read_text():template.unlink()
    if 'windows' in a.platforms.split(','):
        cm=game/'windows/CMakeLists.txt';s=cm.read_text().replace('set(BINARY_NAME "shaiya_local_game")','set(BINARY_NAME "game")');cm.write_text(s)
        cpp=game/'windows/runner/main.cpp';s=cpp.read_text().replace('L"shaiya_local_game"','L"Shaiya Local - Cliente Flutter"').replace('1280, 720','1440, 900');cpp.write_text(s)
    print('Cliente independiente preparado. No reemplaza ni modifica el game.exe original.')
if __name__=='__main__':main()
