import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../../render/studio_scene.dart';
import '../shaiya_widgets.dart';
import '../ui_asset.dart';

class WorldHud extends StatelessWidget {
  final StudioScene scene;
  final Catalog catalog;
  final String characterName;
  final UiAssetCache ui;
  final List<String> messages;
  final bool questOpen;
  final int questId;
  final VoidCallback onAcceptQuest;
  final VoidCallback onCancelQuest;

  const WorldHud({
    super.key,
    required this.scene,
    required this.catalog,
    required this.characterName,
    required this.ui,
    required this.messages,
    required this.questOpen,
    required this.questId,
    required this.onAcceptQuest,
    required this.onCancelQuest,
  });

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned(left: 8, top: 7, width: 216, height: 79, child: _playerHud()),
          Positioned(left: 318, top: 8, width: 420, height: 48, child: _topHotbar()),
          Positioned(right: 8, top: 8, width: 188, height: 232, child: _minimap()),
          Positioned(left: 4, top: 389, width: 360, height: 290, child: _chat()),
          Positioned(left: 0, right: 0, bottom: 0, height: 43, child: _bottomHud()),
          if (questOpen)
            Positioned(
              left: 566,
              top: 145,
              width: 247,
              height: 505,
              child: _questWindow(),
            ),
        ],
      );

  Widget _playerHud() => Stack(
        children: [
          Positioned.fill(
            child: DataImage(
              cache: ui,
              path: 'interface/main_stats_bar_bg.tga',
              fit: BoxFit.fill,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x6615110d),
              border: Border.all(color: const Color(0xff87785d)),
            ),
            child: Row(
              children: [
                Container(
                  width: 49,
                  height: 65,
                  decoration: BoxDecoration(
                    color: const Color(0xff571b17),
                    border: Border.all(color: const Color(0xffc2a162)),
                  ),
                  child: const Icon(
                    Icons.local_fire_department,
                    color: Color(0xffffad3b),
                    size: 34,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('1', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              characterName,
                              style: const TextStyle(
                                color: Color(0xffffe742),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      shaiyaBar(const Color(0xffd71919), 1),
                      const SizedBox(height: 2),
                      shaiyaBar(const Color(0xff2865ff), 1),
                      const SizedBox(height: 2),
                      shaiyaBar(const Color(0xffffc40d), 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _topHotbar() => Row(
        children: List.generate(
          10,
          (i) => Container(
            width: 39,
            height: 39,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: const Color(0xcc282218),
              border: Border.all(color: const Color(0xff75694f)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    i < 2
                        ? (i == 0 ? Icons.auto_fix_high : Icons.healing)
                        : Icons.circle_outlined,
                    color: i < 2
                        ? const Color(0xffffde82)
                        : const Color(0xff8b8374),
                    size: 23,
                  ),
                ),
                Positioned(
                  top: 1,
                  left: 2,
                  child: Text(
                    ((i + 1) % 10).toString(),
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _minimap() => Stack(
        children: [
          Positioned.fill(
            child: DataImage(
              cache: ui,
              path: 'interface/main_map.tga',
              fit: BoxFit.fill,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x33201b15),
              border: Border.all(color: const Color(0xff8f8264)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _MiniMapPainter(scene),
                    child: const SizedBox.expand(),
                  ),
                ),
                Row(
                  children: [
                    const Text(
                      '+  −',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      scene.originX.round().toString() +
                          ' ' +
                          scene.originZ.round().toString(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget _chat() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 75,
            height: 31,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xaa1d1812),
              border: Border.all(color: const Color(0xff897556)),
            ),
            child: const Text('World', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(4),
              children: messages
                  .take(12)
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        m,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      );

  Widget _bottomHud() => Stack(
        children: [
          Positioned.fill(
            child: DataImage(
              cache: ui,
              path: 'interface/main_bottom.tga',
              fit: BoxFit.fill,
            ),
          ),
          Column(
            children: [
              Container(
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0x662b241a),
                  border: Border.all(color: const Color(0xff8e7c5d)),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Text(
                        '0,0%',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: .03,
                      child: Container(color: const Color(0xffd6ad65)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final icon in [
                        Icons.menu_book,
                        Icons.inventory_2,
                        Icons.backpack,
                        Icons.description,
                        Icons.pan_tool,
                        Icons.emoji_events,
                        Icons.chat,
                        Icons.sports_martial_arts,
                        Icons.settings,
                        Icons.card_giftcard,
                      ])
                        Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x886b4b33),
                            border: Border.all(
                              color: const Color(0xffc2985c),
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: 16,
                            color: const Color(0xffffdfa2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _questWindow() {
    final text = catalog.spanishText?.quest(questId);
    final title = text != null && text.name.isNotEmpty
        ? text.name
        : 'Operación básica de la interfaz';
    final body = text != null && text.initialDescription.isNotEmpty
        ? text.initialDescription
        : 'Aprende a moverte, reconocer la interfaz y hablar con los habitantes de la zona.';

    return Stack(
      children: [
        Positioned.fill(
          child: DataImage(
            cache: ui,
            path: 'interface/quest/quest.tga',
            fit: BoxFit.fill,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xff251710),
              width: 2,
            ),
            color: const Color(0x339a7047),
            boxShadow: const [
              BoxShadow(color: Colors.black87, blurRadius: 8),
            ],
          ),
          child: Column(
            children: [
              Container(
                height: 34,
                color: const Color(0x9943251a),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.priority_high,
                      color: Color(0xffffff42),
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffffdc63),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            body,
                            style: const TextStyle(
                              color: Color(0xff2d190f),
                              fontSize: 10,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Color(0xff5d3c24)),
                      const Text(
                        'Objeto de recompensa',
                        style: TextStyle(
                          color: Color(0xff2d190f),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xffd9cfb6),
                          border: Border.all(
                            color: const Color(0xff47311e),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Color(0xff6e5ac8),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    shaiyaRedButton(
                      'Aceptar',
                      onAcceptQuest,
                      width: 64,
                      height: 29,
                      fontSize: 10,
                    ),
                    const SizedBox(width: 26),
                    shaiyaRedButton(
                      'Cancelar',
                      onCancelQuest,
                      width: 64,
                      height: 29,
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final StudioScene scene;
  _MiniMapPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x5535452b),
    );

    final road = Paint()
      ..color = const Color(0x9988744a)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .05, size.height * .86)
      ..cubicTo(
        size.width * .34,
        size.height * .60,
        size.width * .46,
        size.height * .70,
        size.width * .9,
        size.height * .14,
      );
    canvas.drawPath(path, road);

    for (final a in scene.gameActors) {
      final x = (a.root.position.x / 120 + .5).clamp(0.0, 1.0);
      final y = (a.root.position.z / 120 + .5).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        2.2,
        Paint()..color = const Color(0xffff3f27),
      );
    }

    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      4,
      Paint()..color = const Color(0xffffdf2f),
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}
