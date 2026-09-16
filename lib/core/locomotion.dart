enum GroundMotion { idle, walk, run }

/// Explicit identities: swnormal must never match standing normal.
List<String> groundMotionCandidates(Iterable<String> paths, GroundMotion motion) {
  final suffixes = switch (motion) {
    GroundMotion.idle => ['000_normal', '000_nomal', '000_stand'],
    GroundMotion.walk => ['001_walk'],
    GroundMotion.run => ['002_run'],
  };
  final out=<String>[];
  for(final suffix in suffixes){
    final matches=paths.where((p)=>p.replaceAll('\\','/').split('/').last.toLowerCase().endsWith('_$suffix.ani')).toList()..sort((a,b)=>a.toLowerCase().compareTo(b.toLowerCase()));
    out.addAll(matches);
  }
  return out;
}
class LocomotionTransitions {
  GroundMotion _requested=GroundMotion.idle;
  bool _wasBlocked=false,_invalidated=false;
  GroundMotion get requested=>_requested;
  void invalidate()=>_invalidated=true;
  GroundMotion? update({required double x,required double z,required bool running,required bool blocked}){
    final next=x!=0||z!=0?(running?GroundMotion.run:GroundMotion.walk):GroundMotion.idle;
    final changed=next!=_requested;_requested=next;
    if(blocked){_wasBlocked=true;return null;}
    final apply=changed||_wasBlocked||_invalidated;_wasBlocked=false;_invalidated=false;
    return apply?next:null;
  }
}
