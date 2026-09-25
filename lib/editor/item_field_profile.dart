import 'field_semantics.dart';
import 'item_workspace.dart';

/// Context changes captions/groups only, never the native schema or its values.
/// Unknown arguments and units remain explicit instead of being fabricated.
class ItemFieldProfile {
  static FieldMeaning meaning(ItemEntry item, String field) {
    final n = field.toLowerCase(), category = item.category;
    if ({'itemtype','itemtypeid','type','typeid'}.contains(n)) {
      return FieldMeaning(n.contains('id') ? 'ID dentro del tipo' : 'Tipo nativo',
        'Identidad', 'Identidad estable Type:TypeId. Reasignarla requiere migrar todas sus referencias; no se cambia como un stat.');
    }
    if ({'itemname','name','text','description'}.contains(n)) {
      return FieldMeaning(n == 'itemname' || n == 'name' ? 'Nombre en el juego' : 'Descripción en el juego',
        'Nombre y descripción', 'Texto de la tabla localizada seleccionada. Se conserva la codificación original y no se traduce automáticamente.');
    }
    if (n == 'icon' || n == 'image') {
      return FieldMeaning(n == 'icon' ? 'Icono del inventario' : 'Índice visual / Image',
        'Aspecto', n == 'icon'
          ? 'Índice nativo de 1 a 255 en el perfil ps0032. La familia de atlas y su página dependen del tipo, no del nombre del objeto.'
          : 'Referencia visual original. En equipo puede seleccionar una fila MLT, ITM o MON; no equivale al ItemTypeId. Otros tipos pueden interpretarla de otra manera.');
    }
    if (n == 'consthp' || n == 'constsp' || n == 'constmp') {
      final stat = n.substring(5).toUpperCase();
      return FieldMeaning('${item.type == 25 ? 'Recuperación / efecto' : 'Valor constante'} $stat',
        item.type == 25 ? 'Uso y recuperación' : 'Estadísticas',
        item.type == 25
          ? 'Campo nativo $field. La Manzana 25:1 suministrada declara ConstHp=119 y su descripción confirma la recuperación de 119 HP. Otros subtipos o Special pueden cambiar su comportamiento; no se fuerza una regla universal.'
          : 'Valor constante de $stat según la tabla. El efecto aplicado también depende del servidor y del tipo de objeto.');
    }
    const stats = {'str':'Fuerza','dex':'Destreza','rec':'Resistencia','int':'Inteligencia','wis':'Sabiduría','luc':'Suerte'};
    if (n.startsWith('const') && stats.containsKey(n.substring(5))) {
      return FieldMeaning('Bonificación · ${stats[n.substring(5)]}', 'Estadísticas',
        'Bonificación constante original, distinta del requisito ${n.substring(5)}. No cambia los valores base del personaje.');
    }
    if (stats.containsKey(n)) {
      return FieldMeaning('Requisito · ${stats[n]}', 'Requisitos', 'Campo original $field; distinto de Const${field[0].toUpperCase()}${field.substring(1)}. Se conserva incluso cuando el tipo no lo utiliza.');
    }
    if (RegExp(r'^effect[1-4]$').hasMatch(n)) {
      final group = category == 'Armas' ? 'Daño y efectos' : category == 'Armaduras' || category == 'Escudos'
        ? 'Defensa y efectos' : category == 'Lapisias' || category == 'Lapis y materiales' ? 'Mejora y efectos' : 'Uso y efectos';
      return FieldMeaning('Parámetro de efecto ${n.substring(6)}', group,
        '$field es un parámetro polivalente. No se etiqueta automáticamente como daño máximo, porcentaje o duración: esa interpretación depende de Type/Special y del consumidor nativo/servidor.');
    }
    if ({'special','itemskill','usecontype','useconvar','casttime','duration','extduration'}.contains(n)) {
      const labels = {'special':'Comportamiento especial','itemskill':'Habilidad del ítem',
        'usecontype':'Tipo de condición de uso','useconvar':'Valor de condición de uso','casttime':'Tiempo de uso / lanzamiento',
        'duration':'Duración','extduration':'Duración extendida'};
      return FieldMeaning(labels[n]!, category == 'Lapisias' ? 'Mejora y efectos' : 'Uso y efectos',
        'Parámetro $field en su unidad original. No se convierten códigos a comportamientos ni enteros a segundos sin una regla verificada para este tipo.');
    }
    if ({'range','attacktime','attrib','quality','slot'}.contains(n)) {
      const labels={'range':'Alcance','attacktime':'Intervalo de ataque','attrib':'Atributo / elemento','quality':'Calidad / durabilidad','slot':'Ranuras'};
      return FieldMeaning(labels[n]!, category == 'Armas' ? 'Daño y efectos' : 'Equipamiento',
        'Valor nativo de $field. Se conserva su tipo; la unidad y el efecto final deben coincidir con el cliente y servidor objetivo.');
    }
    if ({'level','reqlv','maxlevel','country','grow','attackfighter','defensefighter','patrolrogue','shootrogue','attackmage','defensemage'}.contains(n)) {
      final base=FieldMeaning.of(field);
      return FieldMeaning(n=='level'?'Nivel requerido':n=='maxlevel'?'Nivel máximo':base.label,
        'Requisitos','Restricción original $field. Cambiarla aquí no modifica automáticamente la validación del servidor.');
    }
    if ({'buy','sell','buymethod','moneytype','count','grade','drop','server','og','vg','ig'}.contains(n)) {
      const labels={'buy':'Precio de compra','sell':'Precio de venta','count':'Cantidad / apilado','grade':'Grupo / Grade',
        'drop':'Parámetro de botín','server':'Servidor','buymethod':'Método de compra','moneytype':'Tipo de moneda'};
      final base=FieldMeaning.of(field);
      return FieldMeaning(labels[n]??base.label,'Economía y disponibilidad',base.help);
    }
    final base=FieldMeaning.of(field);
    if (n=='mesh' || n=='texture' || n.contains('meshindex') || n.contains('textureindex') || n.startsWith('parts[')) {
      return FieldMeaning(base.label,'Aspecto y recursos',base.help);
    }
    return base;
  }
}
