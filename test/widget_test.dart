import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/controllers/home/home_controller.dart';

void main() {
  test('HomeController updates selected tab index', () {
    final controller = HomeController();

    expect(controller.currentIndex, 0);

    controller.onPageChanged(1);
    expect(controller.currentIndex, 1);

    controller.onPageChanged(2);
    expect(controller.currentIndex, 2);

    controller.dispose();
  });
}
