import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_controller.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/device/device_time_zone.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_revision/contact_revision_screen.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/contact_region_resolver.dart';
import 'package:tongxingzhe_app/services/location_service.dart';

void main() {
  testWidgets('本人可查看历史、带原因更正并带原因作废', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = LocalDatabase(NativeDatabase.memory());
    final clock = _FixedClock(DateTime.utc(2030, 1, 10, 18));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'contact-1',
        'revision-1',
        'command-1',
        'revision-2',
        'command-2',
        'revision-3',
        'command-3',
      ]),
    );
    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: _context.appUserId,
        workspaceId: _context.workspace.id,
        projectId: _context.project.id,
        questionnaireVersionId: _context.questionnaireVersion.id,
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
      ),
    );
    final controller = AppController(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ContactRevisionScreen(
          controller: controller,
          context: _context,
          contactId: 'contact-1',
          contactJournal: journal,
          deviceId: 'device-1',
          locationCapture: const _NoLocationCapture(),
          timeZoneProvider: const _TimeZoneProvider(),
          regionResolver: const _NoopRegionResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('contact-revision-1')), findsOneWidget);
    expect(find.text('初次提交'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('correct-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reason')),
      '修正触达人数',
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-correction-reach')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-contact-correction')));
    await tester.pumpAndSettle();

    expect(find.textContaining('更正已保存'), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-revision-2')), findsOneWidget);
    expect(find.textContaining('修正触达人数'), findsOneWidget);
    expect(find.textContaining('触达人数：3'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('void-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-void-reason')),
      '重复录入',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-void-contact')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('contact-revision-3')), findsOneWidget);
    expect(find.textContaining('重复录入'), findsOneWidget);
    expect(find.byKey(const ValueKey('correct-contact')), findsNothing);

    final summary = await journal.summarizePersonalContacts(
      appUserId: _context.appUserId,
      workspaceId: _context.workspace.id,
      projectId: _context.project.id,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    expect(summary.contactSessionCount, 0);
  });
}

const _context = TrustedSessionContext(
  appUserId: 'app-user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '推广项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-v1',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}

final class _NoLocationCapture implements ContactLocationCapture {
  const _NoLocationCapture();

  @override
  Future<LocationSnapshot> captureCurrentPosition() async =>
      const LocationSnapshot(error: 'location_unavailable');
}

final class _TimeZoneProvider implements DeviceTimeZoneProvider {
  const _TimeZoneProvider();

  @override
  Future<String> currentIanaTimeZone() async => 'America/Chicago';
}

final class _NoopRegionResolver implements ContactRegionResolver {
  const _NoopRegionResolver();

  @override
  Future<void> close() async {}

  @override
  Future<ContactLocation> resolve(PendingContactLocation location) async =>
      location;
}
