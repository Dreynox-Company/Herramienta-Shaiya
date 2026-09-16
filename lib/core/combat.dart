import 'dart:math' as math;
/// Local laboratory rules, not the Shaiya server formulas.
class Combat {
  double playerHealth=1000,enemyHealth=1000,maxHealth=1000;
  double damage=90,enemyDamage=45,range=2.5,cooldown=1.1;
  bool active=false,automatic=false,counterattack=true;
  double attackDuration=1;
  double _clock=0,_nextPlayer=0,_nextEnemy=0;
  final List<_Hit> _pending=[];
  void Function(String actor,String event)? onEvent;
  final List<String> log=[];
  double get cooldownRemaining=>math.max(0,_nextPlayer-_clock);
  bool get alive=>playerHealth>0&&enemyHealth>0;
  void reset(){playerHealth=maxHealth;enemyHealth=maxHealth;active=false;automatic=false;_clock=0;_nextPlayer=0;_nextEnemy=0;_pending.clear();log.clear();}
  bool attack(double distance,{double? duration}){
    final time=duration??attackDuration;
    if(!alive||_clock<_nextPlayer)return false;
    if(distance>range){record('Fuera de alcance (${distance.toStringAsFixed(1)} m).');return false;}
    active=true;_nextPlayer=_clock+math.max(cooldown,time);_pending.add(_Hit(_clock+time*.45,true));onEvent?.call('player','attack');return true;
  }
  void step(double dt,double distance){
    if(dt<0||!dt.isFinite)return;_clock+=math.min(dt,.25);
    if(!active||!alive)return;
    if(automatic)attack(distance);
    if(counterattack&&distance<=range&&_clock>=_nextEnemy){_nextEnemy=_clock+1.8;_pending.add(_Hit(_clock+.55,false));onEvent?.call('enemy','attack');}
    for(final hit in List<_Hit>.from(_pending)){
      if(hit.at>_clock)continue;_pending.remove(hit);if(distance>range||!alive)continue;
      if(hit.player){enemyHealth=math.max(0,enemyHealth-damage);record('Impacto: ${damage.round()} de daño.');onEvent?.call('enemy',enemyHealth==0?'death':'hit');}
      else{playerHealth=math.max(0,playerHealth-enemyDamage);record('Recibido: ${enemyDamage.round()} de daño.');onEvent?.call('player',playerHealth==0?'death':'hit');}
      if(!alive){active=false;automatic=false;_pending.clear();record(enemyHealth==0?'Prueba terminada: criatura derrotada.':'Prueba terminada: personaje derrotado.');}
    }
  }
  void record(String text){log.insert(0,text);if(log.length>80)log.removeLast();}
}
class _Hit{final double at;final bool player;_Hit(this.at,this.player);}
