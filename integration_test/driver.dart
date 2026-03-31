import 'package:integration_test/integration_test_driver.dart';

/// Integration test driver for EthioGrade.
///
/// Run with:
///   flutter drive --driver integration_test/driver.dart \
///     --target integration_test/app_flow_test.dart
Future<void> main() => integrationDriver();
