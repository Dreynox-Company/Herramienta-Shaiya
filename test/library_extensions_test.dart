import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/library.dart';

void main(){
  test('indexes every native world-animation and water resource family',(){
    expect(supportedPath('Entity/VAni/A1_butterfly01.VANI'),isTrue);
    expect(supportedPath('Entity/MAni/World_01.mani'),isTrue);
    expect(supportedPath('World/field.wtr'),isTrue);
    expect(supportedPath('Entity/Building/test.SMOD'),isTrue);
  });
}
