"""Small, readable R25 integration follow-up; idempotent after formatting."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    marker=ROOT/'.studio-r25-finish-applied'
    if marker.exists(): return
    p=ROOT/'lib/ui/item_workbench.dart'; s=p.read_text()
    old="actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cerrar'))]))))),"
    if old not in s: raise RuntimeError('Unexpected workbench search header')
    s=s.replace(old,old.replace(']))))),','])))))),') ,1)
    s=s.replace("import '../editor/field_semantics.dart';", "import '../editor/item_field_profile.dart';")
    s=s.replace('FieldMeaning.of(v.key)', 'ItemFieldProfile.meaning(e,v.key)')
    s=s.replace('FieldMeaning.of(b.field.spec.name)', 'ItemFieldProfile.meaning(widget.entry,b.field.spec.name)')
    s=s.replace('FieldMeaning.of(f.spec.name)', 'ItemFieldProfile.meaning(widget.entry,f.spec.name)')
    s=s.replace('    final path=ref.sourcePath, ordinal=ref.sourceOrdinal;',
      '    final capturedEntry=session!.byKey[selected]!;\n    final path=ref.sourcePath, ordinal=ref.sourceOrdinal;')
    s=s.replace('entry:session!.byKey[selected]!,bindings:fields', 'entry:capturedEntry,bindings:fields')
    s=s.replace('  bool busy=false,leaving=false,onlyUnnamed=false;', '  bool busy=false,leaving=false,onlyUnnamed=false,mobileDetail=false;')
    s=s.replace('    if(busy)return;\n    if(session?.dirty', '    if(busy)return;\n    if(mobileDetail){setState(()=>mobileDetail=false);return;}\n    if(session?.dirty')
    a='''                  onTap:(){select(e.key);if(!wide)unawaited(showModalBottomSheet<void>(context:context,isScrollControlled:true,
                    builder:(_)=>SizedBox(height:MediaQuery.sizeOf(context).height*.8,child:detail(e))));},'''
    b='''                  onTap:busy?null:(){select(e.key);if(!wide)setState(()=>mobileDetail=true);},'''
    if a not in s: raise RuntimeError('Unexpected mobile entry navigation')
    s=s.replace(a,b)
    s=s.replace('if(!wide)return list;', 'if(!wide)return mobileDetail && selected!=null ? detail(s.byKey[selected]!) : list;')
    p.write_text(s)
    p=ROOT/'lib/ui/studio_workspace.dart';s=p.read_text()
    a="""              IconButton(key: const ValueKey('open-items'), tooltip: 'Ítems · nombres del juego, iconos y edición SData',
                onPressed: widget.onOpenItems, icon: const Icon(Icons.inventory_2_outlined)),"""
    b="""              TextButton.icon(key: const ValueKey('open-items'),
                onPressed: widget.onOpenItems, icon: const Icon(Icons.inventory_2_outlined, size: 18), label: const Text('Ítems')),"""
    if a not in s: raise RuntimeError('Unexpected Items entry point')
    p.write_text(s.replace(a,b))
    p=ROOT/'test/item_workspace_test.dart';s=p.read_text()
    s=s.replace('[94,1,0,3,0,0,0,0]', '[95,1,0,3,0,0,0,0]').replace("(94,1,'Lapisia','Mejora')", "(95,1,'Lapisia','Mejora')")
    s=s.replace("import 'dart:io';", "import 'dart:io';\nimport 'package:herramienta_shaiya/editor/item_field_profile.dart';")
    s=s.replace('void main(){', """void main(){
  test('field meaning follows type without inventing generic effect units',(){
    final s=fixture();
    expect(ItemFieldProfile.meaning(s.byKey['25:1']!,'ConstHp').group,'Uso y recuperación');
    expect(ItemFieldProfile.meaning(s.byKey['1:1']!,'Effect1').group,'Daño y efectos');
    expect(ItemFieldProfile.meaning(s.byKey['95:1']!,'Effect1').group,'Mejora y efectos');
    expect(ItemFieldProfile.meaning(s.byKey['73:6']!,'Effect1').group,'Defensa y efectos');
    expect(ItemFieldProfile.meaning(s.byKey['200:1']!,'Arg12').label,contains('Arg12'));
  });
""")
    p.write_text(s)
    marker.write_text('R25 contextual native properties and stable item navigation\n')
if __name__=='__main__':main()
