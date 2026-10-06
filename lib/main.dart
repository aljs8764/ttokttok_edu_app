import 'app/flavor.dart';
import 'bootstrap.dart';

/// 기본 진입점 (flutter run) = 교사앱. 학부모앱은 -t lib/main_parent.dart
void main() => bootstrap(Flavor.teacher);
