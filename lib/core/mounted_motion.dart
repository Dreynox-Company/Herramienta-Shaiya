/// A mounted clip must match the actual weapon family, not merely one hand.
/// Missing families remain unavailable rather than falling back to a sword.
String? mountedMotionKey(int family) => switch (family) {
  1 || 3 || 7 => 'mounted_sword',
  2 || 4 || 8 => 'mounted_twohand',
  5 => 'mounted_dual',
  6 => 'mounted_spear',
  9 => 'mounted_reverse_dagger',
  10 => 'mounted_dagger',
  11 => 'mounted_javelin',
  12 => 'mounted_staff',
  13 => 'mounted_bow',
  14 => 'mounted_crossbow',
  15 => 'mounted_claws',
  _ => null,
};

const mountedMotionKeys = [
  'mounted_sword',
  'mounted_twohand',
  'mounted_dual',
  'mounted_spear',
  'mounted_reverse_dagger',
  'mounted_dagger',
  'mounted_javelin',
  'mounted_staff',
  'mounted_bow',
  'mounted_crossbow',
  'mounted_claws',
];
