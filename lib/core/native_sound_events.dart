/// Sound banks cross-checked against the supplied ps0032 client and DATA.
/// This is not a claim that every unknown animation has an inferred WAV.
String? nativeWeaponSoundPrefix(int family, String event) {
  if (event != 'attack' && event != 'hit') return null;
  const stems = {
    1: 'swordone',
    2: 'swordtwo',
    3: 'axeone',
    4: 'axetwo',
    5: 'twin',
    6: 'spear',
    7: 'weaponone',
    8: 'weapontwo',
    9: 'daggerbk',
    10: 'dagger',
    11: 'javelin',
    12: 'staff',
    13: 'bow',
    14: 'crobow',
    15: 'knuckle',
  };
  return '${event == 'attack' ? 'ch_att_' : 'ch_hit_'}${stems[family] ?? 'weaponone'}';
}

String? nativeCharacterVoice(String archetype, String event) {
  if (event != 'hit' && event != 'death') return null;
  final name = archetype.toLowerCase();
  const voices = {'hum', 'huw', 'elm', 'elw', 'dem', 'dew', 'vim', 'viw'};
  if (name.length < 3 || !voices.contains(name.substring(0, 3))) return null;
  return 'ch_${name.substring(0, 3)}_${event == 'death' ? 'die' : 'dam'}.wav';
}

/// MON MO2/MO4 stores three attack sounds and a death sound, not a generic
/// jump/hit bank. Missing/LOAD references are not aliases for an arbitrary WAV.
String? nativeMonSoundSlot(String event, {int attackIndex = 0}) =>
    switch (event) {
      'attack' => 'Ataque ${attackIndex % 3 + 1}',
      'death' => 'Caída',
      _ => null,
    };
