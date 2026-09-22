import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/server_metadata.dart';

ItemRule item(int type,int id,{int special=0})=>ItemRule(
  type:type,id:id,image:0,icon:0,level:0,quality:0,slot:0,count:1,duration:0,grade:0,
  special:special,reqWis:0,reqRec:0,country:0,range:0,attackTime:0,
  hp:0,sp:0,mp:0,itemSkill:0,buy:0,sell:0,
);

void main(){
  test('identifies exact dye consumables from SpecialEffect.Dye',(){
    for(var id=55;id<=60;id++)expect(item(100,id,special:110).dyeItem,isTrue);
    expect(item(100,54,special:110).dyeItem,isFalse);
    expect(item(100,55,special:109).dyeItem,isFalse);
  });

  test('dye TypeId 55 accepts weapons only',(){
    final dye=item(100,55,special:110);
    expect(item(1,1).canBeDyedBy(dye),isTrue);
    expect(item(65,1).canBeDyedBy(dye),isTrue);
    expect(item(16,1).canBeDyedBy(dye),isFalse);
    expect(item(69,1).canBeDyedBy(dye),isFalse);
  });

  test('dye TypeId 56 accepts armor but not shields',(){
    final dye=item(100,56,special:110);
    expect(item(16,1).canBeDyedBy(dye),isTrue);
    expect(item(92,1).canBeDyedBy(dye),isTrue);
    expect(item(69,1).canBeDyedBy(dye),isFalse);
    expect(item(84,1).canBeDyedBy(dye),isFalse);
  });

  test('mount pet costume and wing dyes follow native type mapping',(){
    expect(item(42,1).canBeDyedBy(item(100,57,special:110)),isTrue);
    expect(item(120,1).canBeDyedBy(item(100,58,special:110)),isTrue);
    expect(item(150,1).canBeDyedBy(item(100,59,special:110)),isTrue);
    expect(item(121,1).canBeDyedBy(item(100,60,special:110)),isTrue);
    expect(item(42,1).canBeDyedBy(item(100,60,special:110)),isFalse);
  });
}
