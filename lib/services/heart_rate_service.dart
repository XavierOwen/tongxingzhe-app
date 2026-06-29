class HeartRateSnapshot {
  const HeartRateSnapshot({this.value, required this.statusKey});

  final double? value;
  final String statusKey;
}

class HeartRateService {
  Future<HeartRateSnapshot> readAverageHeartRate() async {
    // This demo does not connect to HealthKit or Google Fit yet. Keeping the
    // service boundary here lets the UI stay the same when a real health-data
    // plugin is added later.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return const HeartRateSnapshot(statusKey: 'heartRateNoDevice');
  }
}
