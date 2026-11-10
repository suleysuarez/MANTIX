import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mantix/widgets/tickets/drag_auto_scroller.dart';

Widget _list(ScrollController controller) => MaterialApp(
      home: Scaffold(body: ListView(controller: controller, children: [for (var i = 0; i < 100; i++) SizedBox(height: 50, child: Text('$i'))])),
    );

void main() {
  test('la velocidad es cero lejos de los bordes y crece al acercarse', () {
    final scroller = DragAutoScroller(controller: ScrollController(), edge: 100, step: 10);
    expect(scroller.speedFor(400, 100, 700), 0);
    expect(scroller.speedFor(650, 100, 700), greaterThan(0), reason: 'cerca del borde inferior baja');
    expect(scroller.speedFor(150, 100, 700), lessThan(0), reason: 'cerca del borde superior sube');
    expect(scroller.speedFor(699, 100, 700), greaterThan(scroller.speedFor(620, 100, 700)));
    expect(scroller.speedFor(900, 100, 700), 10, reason: 'nunca supera el paso máximo');
  });

  testWidgets('desplaza la lista hacia abajo cerca del borde y se detiene al soltar', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_list(controller));
    final scroller = DragAutoScroller(controller: controller, edge: 100, step: 20);

    scroller.update(590, 0, 600);
    await tester.pump(const Duration(milliseconds: 200));
    final moved = controller.offset;
    expect(moved, greaterThan(0));

    scroller.stop();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, moved, reason: 'al soltar ya no se desplaza');
  });

  testWidgets('en el centro no desplaza', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_list(controller));
    final scroller = DragAutoScroller(controller: controller, edge: 100, step: 20);

    scroller.update(300, 0, 600);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.offset, 0);
    scroller.stop();
  });
}
