// Web 集成测试需要一个主机端 driver，用来收集浏览器内的测试结果。
import 'package:integration_test/integration_test_driver.dart';

// 把 Chrome 中的 integration_test 结果传回 `flutter drive` 进程。
Future<void> main() => integrationDriver();
