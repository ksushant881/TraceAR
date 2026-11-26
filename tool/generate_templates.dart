import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const int canvasSize = 2048;
const int thumbSize = 320;
const int strokeWidth = 14;

final black = img.ColorRgba8(0, 0, 0, 255);

img.Image blankCanvas([int size = canvasSize]) {
  return img.Image(width: size, height: size, numChannels: 4);
}

void drawThickLine(
  img.Image canvas,
  int x1,
  int y1,
  int x2,
  int y2, [
  int thickness = strokeWidth,
]) {
  img.drawLine(
    canvas,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    color: black,
    thickness: thickness,
  );
}

void drawThickCircle(
  img.Image canvas,
  int cx,
  int cy,
  int r, [
  int thickness = strokeWidth,
]) {
  const segments = 96;
  for (var i = 0; i < segments; i++) {
    final a1 = (i / segments) * 2 * math.pi;
    final a2 = ((i + 1) / segments) * 2 * math.pi;
    drawThickLine(
      canvas,
      cx + (r * math.cos(a1)).round(),
      cy + (r * math.sin(a1)).round(),
      cx + (r * math.cos(a2)).round(),
      cy + (r * math.sin(a2)).round(),
      thickness,
    );
  }
}

void drawThickEllipse(
  img.Image canvas,
  int cx,
  int cy,
  int rx,
  int ry, [
  int thickness = strokeWidth,
]) {
  const segments = 96;
  for (var i = 0; i < segments; i++) {
    final a1 = (i / segments) * 2 * math.pi;
    final a2 = ((i + 1) / segments) * 2 * math.pi;
    drawThickLine(
      canvas,
      cx + (rx * math.cos(a1)).round(),
      cy + (ry * math.sin(a1)).round(),
      cx + (rx * math.cos(a2)).round(),
      cy + (ry * math.sin(a2)).round(),
      thickness,
    );
  }
}

void drawArc(
  img.Image canvas,
  int cx,
  int cy,
  int rx,
  int ry,
  double startRad,
  double endRad, [
  int thickness = strokeWidth,
]) {
  const segments = 48;
  for (var i = 0; i < segments; i++) {
    final t1 = startRad + (endRad - startRad) * (i / segments);
    final t2 = startRad + (endRad - startRad) * ((i + 1) / segments);
    drawThickLine(
      canvas,
      cx + (rx * math.cos(t1)).round(),
      cy + (ry * math.sin(t1)).round(),
      cx + (rx * math.cos(t2)).round(),
      cy + (ry * math.sin(t2)).round(),
      thickness,
    );
  }
}

void drawPolygon(
  img.Image canvas,
  List<(int, int)> pts, {
  bool close = true,
  int thickness = strokeWidth,
}) {
  for (var i = 0; i < pts.length - 1; i++) {
    drawThickLine(
      canvas,
      pts[i].$1,
      pts[i].$2,
      pts[i + 1].$1,
      pts[i + 1].$2,
      thickness,
    );
  }
  if (close && pts.length > 2) {
    drawThickLine(
      canvas,
      pts.last.$1,
      pts.last.$2,
      pts.first.$1,
      pts.first.$2,
      thickness,
    );
  }
}

typedef StepBuilder = List<void Function(img.Image)>;

void main() async {
  final templates =
      <({String id, String title, String difficulty, StepBuilder steps})>[
        (
          id: 'cat',
          title: 'Cat',
          difficulty: 'easy',
          steps: [
            (c) => drawThickCircle(c, 1024, 1120, 460),
            (c) {
              drawPolygon(c, [
                (660, 820),
                (580, 420),
                (880, 680),
              ], close: false);
              drawPolygon(c, [
                (1388, 820),
                (1468, 420),
                (1168, 680),
              ], close: false);
            },
            (c) {
              drawThickCircle(c, 840, 1060, 55);
              drawThickCircle(c, 1208, 1060, 55);
              drawPolygon(c, [(974, 1190), (1074, 1190), (1024, 1260)]);
            },
            (c) {
              drawArc(c, 964, 1290, 60, 50, 0.1, math.pi - 0.1);
              drawArc(c, 1084, 1290, 60, 50, 0.1, math.pi - 0.1);
              drawThickLine(c, 740, 1200, 440, 1150);
              drawThickLine(c, 740, 1260, 430, 1280);
              drawThickLine(c, 1308, 1200, 1608, 1150);
              drawThickLine(c, 1308, 1260, 1618, 1280);
            },
          ],
        ),
        (
          id: 'dog',
          title: 'Dog',
          difficulty: 'easy',
          steps: [
            (c) => drawThickEllipse(c, 1024, 1080, 440, 480),
            (c) {
              drawThickEllipse(c, 580, 1040, 140, 320);
              drawThickEllipse(c, 1468, 1040, 140, 320);
            },
            (c) {
              drawThickCircle(c, 850, 960, 50);
              drawThickCircle(c, 1198, 960, 50);
              drawThickEllipse(c, 1024, 1180, 95, 65);
            },
            (c) {
              drawThickLine(c, 1024, 1245, 1024, 1340);
              drawArc(c, 944, 1340, 80, 60, 0, math.pi);
              drawArc(c, 1104, 1340, 80, 60, 0, math.pi);
              drawArc(c, 1024, 1420, 70, 110, 0, math.pi);
            },
          ],
        ),
        (
          id: 'owl',
          title: 'Owl',
          difficulty: 'medium',
          steps: [
            (c) => drawThickEllipse(c, 1024, 1140, 420, 540),
            (c) {
              drawThickCircle(c, 840, 920, 150);
              drawThickCircle(c, 1208, 920, 150);
              drawPolygon(c, [
                (680, 720),
                (600, 560),
                (780, 650),
              ], close: false);
              drawPolygon(c, [
                (1368, 720),
                (1448, 560),
                (1268, 650),
              ], close: false);
            },
            (c) {
              drawThickCircle(c, 840, 920, 55);
              drawThickCircle(c, 1208, 920, 55);
              drawPolygon(c, [(964, 1020), (1084, 1020), (1024, 1140)]);
            },
            (c) {
              drawArc(c, 630, 1220, 120, 260, math.pi * 0.4, math.pi * 1.6);
              drawArc(c, 1418, 1220, 120, 260, -math.pi * 0.6, math.pi * 0.6);
              drawThickLine(c, 500, 1680, 1548, 1680);
            },
          ],
        ),
        (
          id: 'fish',
          title: 'Fish',
          difficulty: 'easy',
          steps: [
            (c) => drawThickEllipse(c, 940, 1024, 520, 320),
            (c) => drawPolygon(c, [
              (1440, 1024),
              (1740, 760),
              (1680, 1024),
              (1740, 1288),
            ]),
            (c) {
              drawThickCircle(c, 620, 950, 50);
              drawArc(c, 740, 1024, 120, 200, -1.0, 1.0);
            },
            (c) {
              drawPolygon(c, [
                (820, 710),
                (960, 500),
                (1140, 715),
              ], close: false);
              drawPolygon(c, [
                (900, 1340),
                (1020, 1500),
                (1120, 1335),
              ], close: false);
              drawThickCircle(c, 320, 860, 35);
              drawThickCircle(c, 260, 720, 48);
            },
          ],
        ),
        (
          id: 'butterfly',
          title: 'Butterfly',
          difficulty: 'medium',
          steps: [
            (c) {
              drawThickEllipse(c, 1024, 1060, 55, 360);
              drawThickCircle(c, 1024, 640, 75);
            },
            (c) {
              drawThickEllipse(c, 680, 820, 320, 240);
              drawThickEllipse(c, 1368, 820, 320, 240);
            },
            (c) {
              drawThickEllipse(c, 740, 1240, 240, 200);
              drawThickEllipse(c, 1308, 1240, 240, 200);
            },
            (c) {
              drawArc(c, 920, 520, 80, 160, math.pi, math.pi * 1.6);
              drawArc(c, 1128, 520, 80, 160, -math.pi * 0.6, 0);
              drawThickCircle(c, 640, 800, 70);
              drawThickCircle(c, 1408, 800, 70);
            },
          ],
        ),
        (
          id: 'bird',
          title: 'Bird',
          difficulty: 'easy',
          steps: [
            (c) => drawThickEllipse(c, 1060, 1120, 420, 260),
            (c) => drawThickCircle(c, 740, 860, 180),
            (c) {
              drawPolygon(c, [
                (560, 840),
                (380, 880),
                (565, 920),
              ], close: false);
              drawThickCircle(c, 690, 820, 35);
              drawPolygon(c, [
                (1460, 1060),
                (1760, 920),
                (1700, 1120),
              ], close: false);
            },
            (c) {
              drawArc(c, 1080, 1100, 220, 140, 0, math.pi);
              drawThickLine(c, 980, 1380, 960, 1620);
              drawThickLine(c, 1120, 1380, 1140, 1620);
            },
          ],
        ),
        (
          id: 'tulip',
          title: 'Tulip',
          difficulty: 'easy',
          steps: [
            (c) => drawArc(c, 1024, 760, 280, 340, 0, math.pi),
            (c) {
              drawPolygon(c, [
                (744, 760),
                (860, 440),
                (1024, 620),
                (1188, 440),
                (1304, 760),
              ], close: false);
            },
            (c) => drawThickLine(c, 1024, 1100, 1024, 1740),
            (c) {
              drawThickEllipse(c, 820, 1440, 180, 80);
              drawThickEllipse(c, 1228, 1440, 180, 80);
            },
          ],
        ),
        (
          id: 'sunflower',
          title: 'Sunflower',
          difficulty: 'medium',
          steps: [
            (c) => drawThickCircle(c, 1024, 840, 220),
            (c) {
              for (var i = 0; i < 12; i++) {
                final angle = (i / 12) * 2 * math.pi;
                final px = 1024 + (380 * math.cos(angle)).round();
                final py = 840 + (380 * math.sin(angle)).round();
                drawThickCircle(c, px, py, 110);
              }
            },
            (c) => drawThickLine(c, 1024, 1260, 1024, 1780),
            (c) {
              drawThickEllipse(c, 830, 1540, 170, 70);
              drawThickEllipse(c, 1218, 1540, 170, 70);
            },
          ],
        ),
        (
          id: 'rose',
          title: 'Rose',
          difficulty: 'medium',
          steps: [
            (c) => drawThickCircle(c, 1024, 780, 280),
            (c) {
              drawArc(c, 1024, 780, 180, 180, 0, math.pi * 1.5);
              drawArc(c, 1024, 780, 95, 95, math.pi * 0.5, math.pi * 2.0);
            },
            (c) {
              drawArc(c, 1024, 860, 340, 260, 0.2, math.pi - 0.2);
              drawThickLine(c, 1024, 1120, 1024, 1760);
            },
            (c) {
              drawThickEllipse(c, 820, 1420, 160, 70);
              drawPolygon(c, [
                (1024, 1300),
                (1120, 1260),
                (1024, 1340),
              ], close: false);
            },
          ],
        ),
        (
          id: 'tree',
          title: 'Tree',
          difficulty: 'easy',
          steps: [
            (c) {
              drawThickLine(c, 940, 1160, 910, 1720);
              drawThickLine(c, 1108, 1160, 1138, 1720);
              drawThickLine(c, 840, 1720, 1208, 1720);
            },
            (c) => drawThickCircle(c, 1024, 820, 420),
            (c) {
              drawThickCircle(c, 740, 940, 220);
              drawThickCircle(c, 1308, 940, 220);
            },
            (c) {
              drawThickLine(c, 1024, 1240, 1024, 920);
              drawThickLine(c, 1024, 1080, 880, 960);
              drawThickLine(c, 1024, 1020, 1168, 900);
            },
          ],
        ),
        (
          id: 'house',
          title: 'House',
          difficulty: 'easy',
          steps: [
            (c) => drawPolygon(c, [
              (540, 920),
              (1508, 920),
              (1508, 1660),
              (540, 1660),
            ]),
            (c) => drawPolygon(c, [
              (440, 920),
              (1024, 440),
              (1608, 920),
            ], close: false),
            (c) {
              drawPolygon(c, [
                (920, 1240),
                (1128, 1240),
                (1128, 1660),
                (920, 1660),
              ]);
              drawPolygon(c, [
                (640, 1080),
                (840, 1080),
                (840, 1280),
                (640, 1280),
              ]);
              drawPolygon(c, [
                (1208, 1080),
                (1408, 1080),
                (1408, 1280),
                (1208, 1280),
              ]);
            },
            (c) {
              drawPolygon(c, [
                (1280, 650),
                (1280, 460),
                (1420, 460),
                (1420, 766),
              ], close: false);
              drawThickLine(c, 740, 1080, 740, 1280);
              drawThickLine(c, 640, 1180, 840, 1180);
            },
          ],
        ),
        (
          id: 'car',
          title: 'Car',
          difficulty: 'medium',
          steps: [
            (c) => drawPolygon(c, [
              (320, 1060),
              (1728, 1060),
              (1728, 1340),
              (320, 1340),
            ]),
            (c) => drawPolygon(c, [
              (560, 1060),
              (740, 740),
              (1320, 740),
              (1500, 1060),
            ], close: false),
            (c) {
              drawThickCircle(c, 620, 1360, 150);
              drawThickCircle(c, 1428, 1360, 150);
              drawThickCircle(c, 620, 1360, 65);
              drawThickCircle(c, 1428, 1360, 65);
            },
            (c) {
              drawThickLine(c, 1024, 740, 1024, 1060);
              drawThickLine(c, 1660, 1140, 1728, 1140);
              drawThickLine(c, 320, 1140, 390, 1140);
            },
          ],
        ),
        (
          id: 'rocket',
          title: 'Rocket',
          difficulty: 'easy',
          steps: [
            (c) => drawThickEllipse(c, 1024, 960, 240, 560),
            (c) {
              drawPolygon(c, [
                (800, 1240),
                (580, 1520),
                (840, 1460),
              ], close: false);
              drawPolygon(c, [
                (1248, 1240),
                (1468, 1520),
                (1208, 1460),
              ], close: false);
            },
            (c) {
              drawThickCircle(c, 1024, 840, 110);
              drawThickLine(c, 840, 640, 1208, 640);
            },
            (c) {
              drawPolygon(c, [
                (920, 1520),
                (1024, 1820),
                (1128, 1520),
              ], close: false);
            },
          ],
        ),
        (
          id: 'sailboat',
          title: 'Sailboat',
          difficulty: 'easy',
          steps: [
            (c) => drawPolygon(c, [
              (420, 1320),
              (1628, 1320),
              (1440, 1620),
              (608, 1620),
            ]),
            (c) => drawThickLine(c, 1024, 1320, 1024, 420),
            (c) {
              drawPolygon(c, [(1024, 460), (540, 1220), (1024, 1220)]);
              drawPolygon(c, [(1060, 560), (1480, 1220), (1060, 1220)]);
            },
            (c) {
              drawArc(c, 520, 1700, 160, 40, 0, math.pi);
              drawArc(c, 840, 1700, 160, 40, 0, math.pi);
              drawArc(c, 1160, 1700, 160, 40, 0, math.pi);
              drawArc(c, 1480, 1700, 160, 40, 0, math.pi);
            },
          ],
        ),
        (
          id: 'apple',
          title: 'Apple',
          difficulty: 'easy',
          steps: [
            (c) => drawThickCircle(c, 920, 1120, 420),
            (c) => drawThickCircle(c, 1128, 1120, 420),
            (c) => drawThickLine(c, 1024, 720, 1080, 460),
            (c) => drawThickEllipse(c, 1220, 560, 160, 70),
          ],
        ),
        (
          id: 'cup',
          title: 'Coffee Cup',
          difficulty: 'easy',
          steps: [
            (c) => drawThickEllipse(c, 980, 820, 380, 100),
            (c) {
              drawThickLine(c, 600, 820, 680, 1480);
              drawThickLine(c, 1360, 820, 1280, 1480);
              drawArc(c, 980, 1480, 300, 80, 0, math.pi);
            },
            (c) =>
                drawArc(c, 1340, 1120, 180, 200, -math.pi * 0.5, math.pi * 0.5),
            (c) {
              drawThickEllipse(c, 980, 1580, 520, 120);
              drawArc(c, 860, 540, 40, 120, -1.2, 1.2);
              drawArc(c, 1080, 520, 40, 120, -1.2, 1.2);
            },
          ],
        ),
        (
          id: 'face',
          title: 'Portrait',
          difficulty: 'hard',
          steps: [
            (c) => drawThickEllipse(c, 1024, 1000, 380, 500),
            (c) {
              drawThickLine(c, 644, 1000, 1404, 1000, 6);
              drawThickLine(c, 1024, 500, 1024, 1500, 6);
            },
            (c) {
              drawThickEllipse(c, 860, 960, 75, 40);
              drawThickEllipse(c, 1188, 960, 75, 40);
              drawPolygon(c, [
                (1024, 960),
                (980, 1180),
                (1060, 1190),
              ], close: false);
            },
            (c) {
              drawArc(c, 1024, 1280, 120, 60, 0.1, math.pi - 0.1);
              drawArc(c, 1024, 840, 440, 420, math.pi, math.pi * 2);
            },
          ],
        ),
        (
          id: 'star',
          title: 'Star',
          difficulty: 'easy',
          steps: [
            (c) => drawThickCircle(c, 1024, 1024, 640, 6),
            (c) => drawPolygon(c, [
              (1024, 384),
              (1180, 820),
              (1640, 820),
              (1268, 1090),
              (1408, 1540),
            ], close: false),
            (c) => drawPolygon(c, [
              (1408, 1540),
              (1024, 1260),
              (640, 1540),
              (780, 1090),
              (408, 820),
              (868, 820),
              (1024, 384),
            ], close: false),
          ],
        ),
        (
          id: 'heart',
          title: 'Heart',
          difficulty: 'easy',
          steps: [
            (c) {
              drawThickCircle(c, 780, 820, 300);
              drawThickCircle(c, 1268, 820, 300);
            },
            (c) {
              drawThickLine(c, 500, 960, 1024, 1640);
              drawThickLine(c, 1548, 960, 1024, 1640);
            },
            (c) => drawArc(c, 780, 820, 200, 200, math.pi * 1.1, math.pi * 1.5),
          ],
        ),
        (
          id: 'letter_a',
          title: 'Letter A',
          difficulty: 'easy',
          steps: [
            (c) {
              drawThickLine(c, 1024, 380, 520, 1660);
              drawThickLine(c, 1024, 380, 1528, 1660);
            },
            (c) {
              drawThickLine(c, 1024, 680, 740, 1660);
              drawThickLine(c, 1024, 680, 1308, 1660);
            },
            (c) {
              drawThickLine(c, 680, 1240, 1368, 1240);
              drawThickLine(c, 520, 1660, 740, 1660);
              drawThickLine(c, 1308, 1660, 1528, 1660);
            },
          ],
        ),
      ];

  final indexList = <Map<String, dynamic>>[];

  for (final t in templates) {
    final dir = Directory('assets/templates/${t.id}');
    await dir.create(recursive: true);

    final full = blankCanvas();
    for (var i = 0; i < t.steps.length; i++) {
      final stepImg = blankCanvas();
      t.steps[i](stepImg);
      t.steps[i](full);
      await File('${dir.path}/step_${i + 1}.png')
          .writeAsBytes(img.encodePng(stepImg));
    }
    await File('${dir.path}/full.png').writeAsBytes(img.encodePng(full));

    final thumb = img.copyResize(
      full,
      width: thumbSize,
      height: thumbSize,
      interpolation: img.Interpolation.average,
    );
    await File('${dir.path}/thumb.png').writeAsBytes(img.encodePng(thumb));

    indexList.add({
      'id': t.id,
      'title': t.title,
      'steps': t.steps.length,
      'difficulty': t.difficulty,
    });
  }

  await File('assets/templates/index.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(indexList));

  // Also generate 3 sample fixture images in test/fixtures/ for invariant tests
  final fixturesDir = Directory('test/fixtures');
  await fixturesDir.create(recursive: true);
  for (var f = 0; f < 3; f++) {
    final fx = img.Image(width: 240, height: 240, numChannels: 4);
    img.fill(fx, color: img.ColorRgba8(245, 245, 245, 255));
    // Draw varied high-contrast shapes
    drawThickCircle(fx, 120, 120, 60 + f * 12, 4);
    drawThickLine(fx, 30, 40 + f * 20, 210, 200 - f * 15, 3);
    drawPolygon(fx, [(60, 180), (120, 50), (180, 180)], thickness: 3);
    await File('${fixturesDir.path}/sample_${f + 1}.png')
        .writeAsBytes(img.encodePng(fx));
  }

  stdout.writeln(
    'Generated ${templates.length} templates and 3 test fixtures.',
  );
}
