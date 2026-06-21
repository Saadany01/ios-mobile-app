import 'package:flutter/material.dart';

class HomeController extends ChangeNotifier {
  final PageController pageController = PageController();

  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void onPageChanged(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }

  void onTabTapped(int index) {
    pageController.jumpToPage(index);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}
