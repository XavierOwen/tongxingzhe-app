import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';

final class FixedClock implements AppClock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class MutableClock implements AppClock {
  MutableClock(this.value);

  DateTime value;

  void advance(Duration duration) {
    value = value.add(duration);
  }

  @override
  DateTime now() => value;
}

final class SequenceIdGenerator implements IdGenerator {
  SequenceIdGenerator(List<String> values) : _values = [...values];

  final List<String> _values;
  var _index = 0;

  @override
  String next() => _values[_index++];
}

final class CountingIdGenerator implements IdGenerator {
  CountingIdGenerator([this.prefix = 'test-']);

  final String prefix;
  var _next = 0;

  @override
  String next() => '$prefix${_next++}';
}

final class FixedTimeZoneProvider implements DeviceTimeZoneProvider {
  const FixedTimeZoneProvider(this.value);

  final String value;

  @override
  Future<String> currentIanaTimeZone() async => value;
}

final class SingleDatabaseFactory implements LocalDatabaseFactory {
  SingleDatabaseFactory(this.database);

  final LocalDatabase database;

  @override
  LocalDatabase open() => database;
}
