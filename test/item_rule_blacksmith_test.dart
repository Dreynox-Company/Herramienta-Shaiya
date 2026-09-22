import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/game/server_metadata.dart';

ItemRule rule({
  int type=1,
  int special=0,
  int reqWis=0,
  int reqRec=0,
  int country=0,
  int range=0,
  int attackTime=0,
  int level=1,
})=>ItemRule.fromJson({
  'type':type,'id':1,'image':1,'icon':1,'level':level,'quality':1,'slot':1,
  'count':1,'duration':0,'grade':0,'special':special,
  'reqWis':reqWis,'reqRec':reqRec,'country':country,'range':range,'attackTime':attackTime,
  'hp':0,'sp':0,'mp':0,'itemSkill':0,'buy':100,'sell':10,
});

void main(){
  test('models exact recreation requirements',(){
    expect(rule(reqWis:1).composable,isTrue);
    expect(rule(reqWis:0).composable,isFalse);
    expect(rule(type:100,special:62).recreationRune,isTrue);
    expect(rule(type:100,special:86).recreationRune,isTrue);
    expect(rule(type:100,special:91).recreationRune,isTrue);
    expect(rule(type:100,special:117).absoluteRecreationRune,isTrue);
    expect(rule(type:100,special:93).recreationVial,isTrue);
    expect(rule(type:100,special:98).recreationVial,isTrue);
    expect(rule(type:100,special:92).recreationVial,isFalse);
  });

  test('models lapisia and enchant target compatibility fields',(){
    final weapon=rule(type:65);
    final armor=rule(type:92);
    final shield=rule(type:84);
    expect((weapon.enchantTarget,weapon.weaponEnchantTarget),(true,true));
    expect((armor.enchantTarget,armor.armorEnchantTarget),(true,true));
    expect((shield.enchantTarget,shield.shieldEnchantTarget),(true,true));

    final lapisia=rule(type:100,special:78,level:20,country:1,range:4,attackTime:12,reqRec:8750);
    expect(lapisia.lapisia,isTrue);
    expect(lapisia.weaponLapisia,isTrue);
    expect(lapisia.armorLapisia,isTrue);
    expect((lapisia.minEnchantLevel,lapisia.maxEnchantLevel,lapisia.explicitEnchantRate),(4,12,8750));

    expect(rule(type:95).lapisia,isTrue);
  });

  test('old metadata remains backward compatible',(){
    final old=ItemRule.fromJson({
      'type':1,'id':2,'image':0,'icon':0,'level':1,'quality':0,'slot':1,
      'count':1,'duration':0,'grade':0,'special':0,
      'hp':0,'sp':0,'mp':0,'itemSkill':0,'buy':0,'sell':0,
    });
    expect((old.reqWis,old.reqRec,old.country,old.range,old.attackTime),(0,0,0,0,0));
  });
}
