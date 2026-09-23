import 'package:flutter/material.dart';

import '../dreynox_game_theme.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class CharacterArchetypeChoice {
  final String key;
  final String label;
  final bool panda;
  final bool female;

  const CharacterArchetypeChoice({
    required this.key,
    required this.label,
    required this.panda,
    required this.female,
  });
}

class CharacterCreateScreen extends StatelessWidget {
  final UiAssetCache ui;
  final TextEditingController nameController;
  final int classIndex;
  final int genderIndex;
  final int tabIndex;
  final int faceIndex;
  final int hairIndex;
  final int modeIndex;
  final List<CharacterArchetypeChoice> archetypes;
  final String? archetypeKey;
  final ValueChanged<int> onClass;
  final ValueChanged<int> onGender;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onFace;
  final ValueChanged<int> onHair;
  final ValueChanged<int> onMode;
  final ValueChanged<String> onArchetype;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onPause;
  final VoidCallback onReset;

  const CharacterCreateScreen({
    super.key,
    required this.ui,
    required this.nameController,
    required this.classIndex,
    required this.genderIndex,
    required this.tabIndex,
    required this.faceIndex,
    required this.hairIndex,
    required this.modeIndex,
    required this.archetypes,
    required this.archetypeKey,
    required this.onClass,
    required this.onGender,
    required this.onTab,
    required this.onFace,
    required this.onHair,
    required this.onMode,
    required this.onArchetype,
    required this.onBack,
    required this.onCreate,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onPause,
    required this.onReset,
  });

  DataImage image(
    String path, {
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) =>
      DataImage(cache: ui, path: path, fit: fit, fallback: fallback);

  Widget _glass({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
    bool selected = false,
  }) =>
      Container(
        padding: padding,
        decoration: DreynoxGameStyle.panelDecoration(
          selected: selected,
          opacity: .93,
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          text,
          style: const TextStyle(
            color: DreynoxGameStyle.accentSoft,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .25,
          ),
        ),
      );

  Widget classButton(int i, String label, String path) {
    final selected = classIndex == i;
    final row = selected ? 3 : 0;
    return GestureDetector(
      onTap: () => onClass(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 91,
        height: 75,
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 4),
        decoration: DreynoxGameStyle.panelDecoration(
          selected: selected,
          opacity: .82,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Opacity(
              opacity: selected ? 1 : .82,
              child: DataRegion(
                cache: ui,
                path: path,
                sheetWidth: 128,
                sheetHeight: 512,
                source: Rect.fromLTWH(1, row * 128 + 1, 95, 80),
                width: 83,
                height: 67,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xaa06111f),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? DreynoxGameStyle.accentSoft
                        : DreynoxGameStyle.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _archetypeStrip() {
    if (archetypes.isEmpty) {
      return const Text(
        'No se encontraron arquetipos en DATA.',
        style: TextStyle(fontSize: 9, color: DreynoxGameStyle.textMuted),
      );
    }
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: archetypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, index) {
          final item = archetypes[index];
          final selected = item.key == archetypeKey;
          return GestureDetector(
            onTap: () => onArchetype(item.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minWidth: 104, maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: DreynoxGameStyle.panelDecoration(
                selected: selected,
                opacity: selected ? .95 : .72,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    item.panda
                        ? Icons.pets
                        : item.female
                            ? Icons.female
                            : Icons.male,
                    size: 15,
                    color: selected
                        ? DreynoxGameStyle.accent
                        : DreynoxGameStyle.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.6,
                        height: 1.15,
                        color: selected
                            ? DreynoxGameStyle.text
                            : DreynoxGameStyle.textMuted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _genderButton(int value, String label, IconData icon) {
    final selected = genderIndex == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onGender(value),
        child: Container(
          height: 35,
          decoration: DreynoxGameStyle.buttonDecoration(active: selected),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected
                    ? DreynoxGameStyle.accentSoft
                    : DreynoxGameStyle.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: selected
                      ? DreynoxGameStyle.text
                      : DreynoxGameStyle.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(int index, String text) {
    final selected = tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTab(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 31,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? DreynoxGameStyle.surfaceSelected
                : DreynoxGameStyle.panelSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? DreynoxGameStyle.borderStrong
                  : DreynoxGameStyle.border,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 9,
              color: selected
                  ? DreynoxGameStyle.accentSoft
                  : DreynoxGameStyle.textMuted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _baseInfoContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle('Nombre'),
          SizedBox(
            height: 34,
            child: TextField(
              controller: nameController,
              style: const TextStyle(
                fontSize: 10,
                color: DreynoxGameStyle.text,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xb80a1525),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: DreynoxGameStyle.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: DreynoxGameStyle.borderStrong),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Raza / cuerpo · DATA completo'),
          _archetypeStrip(),
          const SizedBox(height: 12),
          _sectionTitle('Clase'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              classButton(
                0,
                'Guerrero',
                'interface/charactermake/button/fighter_worrior.tga',
              ),
              classButton(
                1,
                'Defensor',
                'interface/charactermake/button/defender_guardian.tga',
              ),
              classButton(
                2,
                'Sacerdote',
                'interface/charactermake/button/priest_oracle.tga',
              ),
              classButton(
                3,
                'Ranger',
                'interface/charactermake/button/ranger_assassin.tga',
              ),
              classButton(
                4,
                'Arquero',
                'interface/charactermake/button/archer_hunter.tga',
              ),
              classButton(
                5,
                'Mago',
                'interface/charactermake/button/mage_pagan.tga',
              ),
            ],
          ),
          const SizedBox(height: 11),
          _sectionTitle('Género'),
          Row(
            children: <Widget>[
              _genderButton(0, 'Masculino', Icons.male),
              const SizedBox(width: 7),
              _genderButton(1, 'Femenino', Icons.female),
            ],
          ),
        ],
      );

  Widget _appearanceChoice(String title, bool face) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle(title),
          Row(
            children: List<Widget>.generate(5, (int i) {
              final selected = (face ? faceIndex : hairIndex) == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 4 ? 0 : 7),
                  child: GestureDetector(
                    onTap: () => face ? onFace(i) : onHair(i),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: DreynoxGameStyle.panelDecoration(
                        selected: selected,
                        opacity: .78,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? DreynoxGameStyle.accentSoft
                              : DreynoxGameStyle.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      );

  Widget _appearanceContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _appearanceChoice('Rostro', true),
          const SizedBox(height: 24),
          _appearanceChoice('Cabello', false),
          const Spacer(),
          const Text(
            'Las variantes se aplican directamente sobre las piezas MLT del '
            'arquetipo activo; Panda y demás cuerpos usan sus propios recursos '
            'cuando existen en DATA.',
            style: TextStyle(
              fontSize: 9,
              color: DreynoxGameStyle.textMuted,
              height: 1.45,
            ),
          ),
        ],
      );

  Widget _modeCard(int index, String title, String description) {
    final selected = modeIndex == index;
    return GestureDetector(
      onTap: () => onMode(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: DreynoxGameStyle.panelDecoration(
          selected: selected,
          opacity: selected ? .95 : .72,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              index == 0 ? Icons.shield_outlined : Icons.bolt,
              color: selected
                  ? DreynoxGameStyle.accent
                  : DreynoxGameStyle.textMuted,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: selected
                          ? DreynoxGameStyle.text
                          : DreynoxGameStyle.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      color: DreynoxGameStyle.textMuted,
                      fontSize: 8.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeContent() => Column(
        children: <Widget>[
          _modeCard(
            0,
            'Modo Básico',
            'Progresión estándar y segura para comenzar.',
          ),
          const SizedBox(height: 10),
          _modeCard(
            1,
            'Modo Máximo',
            'Más puntos y progresión avanzada para personajes experimentados.',
          ),
          const Spacer(),
        ],
      );

  Widget _leftPanel() => Positioned(
        left: 12,
        top: 26,
        width: 360,
        height: 690,
        child: _glass(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _tabButton(0, 'Creación'),
                  const SizedBox(width: 6),
                  _tabButton(1, 'Apariencia'),
                  const SizedBox(width: 6),
                  _tabButton(2, 'Modo'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: switch (tabIndex) {
                  1 => _appearanceContent(),
                  2 => _modeContent(),
                  _ => SingleChildScrollView(child: _baseInfoContent()),
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  shaiyaRedButton(
                    'Volver',
                    onBack,
                    width: 118,
                    height: 35,
                    fontSize: 10,
                  ),
                  const Spacer(),
                  shaiyaRedButton(
                    'Crear',
                    onCreate,
                    width: 118,
                    height: 35,
                    fontSize: 10,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _weapon(String icon, String text) => SizedBox(
        width: 62,
        height: 76,
        child: Column(
          children: <Widget>[
            Expanded(
              child: image(
                'interface/charactermake/classinfo/$icon',
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(
              width: 61,
              height: 16,
              child: image(
                'interface/charactermake/classinfo/text/$text',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      );

  Widget _statLine(double value) => Container(
        height: 7,
        decoration: BoxDecoration(
          color: const Color(0x99061020),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  DreynoxGameStyle.accent,
                  DreynoxGameStyle.accentSoft,
                ],
              ),
            ),
          ),
        ),
      );

  Widget _classInfoPanel() => Positioned(
        right: 14,
        top: 34,
        width: 292,
        height: 430,
        child: _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _sectionTitle('Equipo compatible'),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: <Widget>[
                  _weapon(
                    'icon_onehandedsword.tga',
                    'icon_onehandedsword_spn.tga',
                  ),
                  _weapon(
                    'icon_twohandedsword.tga',
                    'icon_twohandedsword_spn.tga',
                  ),
                  _weapon(
                    'icon_dualwieldsword.tga',
                    'icon_dualwieldsword_spn.tga',
                  ),
                  _weapon('icon_spear.tga', 'icon_spear_spn.tga'),
                  _weapon(
                    'icon_onehandedblunt.tga',
                    'icon_onehandedblunt_spn.tga',
                  ),
                  _weapon(
                    'icon_twohandedblunt.tga',
                    'icon_twohandedblunt_spn.tga',
                  ),
                  _weapon('icon_shield.tga', 'icon_shield_spn.tga'),
                ],
              ),
              const Spacer(),
              _sectionTitle('Perfil de clase'),
              const Text(
                'Ataque físico',
                style: TextStyle(
                  fontSize: 8,
                  color: DreynoxGameStyle.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              _statLine(.82),
              const SizedBox(height: 10),
              const Text(
                'Defensa',
                style: TextStyle(
                  fontSize: 8,
                  color: DreynoxGameStyle.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              _statLine(.66),
              const SizedBox(height: 10),
              const Text(
                'Movilidad',
                style: TextStyle(
                  fontSize: 8,
                  color: DreynoxGameStyle.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              _statLine(.79),
            ],
          ),
        ),
      );

  Widget _cameraControls() => Positioned(
        left: 690,
        bottom: 34,
        child: _glass(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Acercar',
                onPressed: onZoomIn,
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: 'Alejar',
                onPressed: onZoomOut,
                icon: const Icon(Icons.zoom_out),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Pausar animación',
                onPressed: onPause,
                icon: const Icon(Icons.pause),
              ),
              IconButton(
                tooltip: 'Reiniciar animación',
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          _leftPanel(),
          _classInfoPanel(),
          _cameraControls(),
        ],
      );
}
