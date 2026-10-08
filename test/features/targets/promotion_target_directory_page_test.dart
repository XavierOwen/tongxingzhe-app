import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_selector/file_selector.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/targets/promotion_target_directory_page.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery_contract.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/personal_pii_export_gateway.dart';
import 'package:tongxingzhe_app/targets/personal_target_csv_import.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../../support/fake_identity_session.dart';
import '../../support/fake_session_context_gateway.dart';

void main() {
  testWidgets(
    'anonymous contact remains available when the directory is empty',
    (tester) async {
      await tester.pumpWidget(_app(_MemoryGateway()));
      await tester.pumpAndSettle();

      expect(find.text('尚未建立推广对象'), findsOneWidget);
      expect(find.text('不建立对象不会影响记录接触。'), findsOneWidget);
    },
  );

  testWidgets('creation requires an explicit purpose confirmation', (
    tester,
  ) async {
    final gateway = _MemoryGateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-promotion-target')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('promotion-target-name')),
      '王小明',
    );

    var confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('promotion-target-purpose-confirmed')),
    );
    await tester.pump();
    confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirm-promotion-target')),
    );
    expect(confirm.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('confirm-promotion-target')));
    await tester.pumpAndSettle();

    expect(gateway.createdName, '王小明');
    expect(gateway.requestId, 'request-1');
    expect(find.text('王小明'), findsOneWidget);
  });

  testWidgets(
    'personal PII export requires password reauthentication and fresh context',
    (tester) async {
      final harness = await _ExportHarness.start();
      final exporter = _MemoryPersonalPiiExportGateway();
      addTearDown(harness.close);
      await tester.pumpWidget(
        _app(
          _MemoryGateway(),
          identitySession: harness.identity,
          appSession: harness.appSession,
          exportGateway: exporter,
          canExport: true,
          scopeKey: harness.scopeKey,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('姓名和联系方式'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('cancel-personal-pii-export')),
      );
      await tester.pumpAndSettle();
      expect(exporter.calls, 0);

      harness.identity.rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.invalidCredentials,
      );
      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.byKey(const ValueKey('personal-pii-export-password')),
        'wrong-password',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('confirm-personal-pii-export')),
      );
      await tester.pumpAndSettle();
      expect(exporter.calls, 0);
      expect(find.textContaining('密码验证未完成'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.byKey(const ValueKey('personal-pii-export-password')),
        'correct-private-password',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('confirm-personal-pii-export')),
      );
      await tester.pumpAndSettle();

      expect(exporter.calls, 1);
      expect(harness.contextGateway.receivedTokens, hasLength(2));
      expect(
        find.byKey(const ValueKey('personal-pii-export-artifact')),
        findsOneWidget,
      );
      expect(find.text('correct-private-password'), findsNothing);
      expect(find.textContaining('不据此判断浏览器已保存、打开或分享'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('personal-pii-export-artifact')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('cancel-personal-pii-export')),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing email or revoked capability stops before the export GET',
    (tester) async {
      final harness = await _ExportHarness.start();
      final exporter = _MemoryPersonalPiiExportGateway();
      addTearDown(harness.close);
      await tester.pumpWidget(
        _app(
          _MemoryGateway(),
          identitySession: harness.identity,
          appSession: harness.appSession,
          exportGateway: exporter,
          canExport: true,
          scopeKey: harness.scopeKey,
        ),
      );
      await tester.pumpAndSettle();

      harness.identity.emit(
        IdentitySnapshot(
          stage: IdentityStage.signedIn,
          principal: const IdentityPrincipal(
            externalSubject: 'test-subject',
            email: null,
          ),
          expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('personal-pii-export-password')),
        findsNothing,
      );
      expect(exporter.calls, 0);

      harness.identity.emit(_signedInSnapshot('test-subject'));
      await tester.pump();
      harness.contextGateway.context = _exportContextWithoutCapability;

      await tester.tap(
        find.byKey(const ValueKey('prepare-personal-pii-export')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(
        find.byKey(const ValueKey('personal-pii-export-password')),
        'private-password',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('confirm-personal-pii-export')),
      );
      await tester.pumpAndSettle();

      expect(exporter.calls, 0);
      expect(
        find.byKey(const ValueKey('personal-pii-export-artifact')),
        findsNothing,
      );
    },
  );

  testWidgets('offline cached context cannot start personal PII export', (
    tester,
  ) async {
    final harness = await _ExportHarness.startOffline();
    final exporter = _MemoryPersonalPiiExportGateway();
    addTearDown(harness.close);
    expect(harness.appSession.current.fromOfflineCache, isTrue);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prepare-personal-pii-export')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('personal-pii-export-password')),
      findsNothing,
    );
    expect(exporter.calls, 0);
  });

  testWidgets('account ABA invalidates a late export result', (tester) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway(pending: true);
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prepare-personal-pii-export')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
      find.byKey(const ValueKey('personal-pii-export-password')),
      'private-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-personal-pii-export')));
    await tester.pump();
    await tester.pump();
    expect(exporter.calls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('prepare-personal-pii-export')),
          )
          .onPressed,
      isNull,
    );

    harness.identity.emit(_signedInSnapshot('other-subject'));
    harness.identity.emit(_signedInSnapshot('test-subject'));
    await tester.pump();
    exporter.complete();
    await tester.pumpAndSettle();

    expect(exporter.calls, 1);
    expect(
      find.byKey(const ValueKey('personal-pii-export-artifact')),
      findsNothing,
    );
  });

  testWidgets('disposing the page drops a late export result', (tester) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway(pending: true);
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prepare-personal-pii-export')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
      find.byKey(const ValueKey('personal-pii-export-password')),
      'private-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-personal-pii-export')));
    await tester.pump();
    await tester.pump();
    expect(exporter.calls, 1);

    await tester.pumpWidget(const SizedBox());
    exporter.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal PII artifact is delivered only on explicit request', (
    tester,
  ) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery();
    final pending = delivery.deferNext();
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    expect(exporter.calls, 1);
    expect(delivery.requests, isEmpty);

    final downloadButton = find.byKey(
      const ValueKey('request-personal-pii-export-download'),
    );
    await tester.tap(downloadButton);
    await tester.tap(downloadButton);
    await tester.pump();
    expect(delivery.requests, hasLength(1));
    expect(identical(delivery.requests.single, exporter.artifact), isTrue);
    expect(delivery.requests.single.bytes, [123, 125]);
    expect(
      delivery.requests.single.fileName,
      'personal-promotion-target-pii-v1.json',
    );
    expect(
      delivery.requests.single.contentType,
      'application/json; charset=utf-8',
    );

    pending.complete(const ManagementReportDownloadFailed());
    await tester.pumpAndSettle();
    expect(find.text('浏览器未能接收下载请求。可使用同一份已验证文件重试。'), findsOneWidget);

    await tester.tap(downloadButton);
    await tester.pumpAndSettle();
    expect(delivery.requests, hasLength(2));
    expect(identical(delivery.requests[1], exporter.artifact), isTrue);
    expect(exporter.calls, 1);
    expect(find.text('已向浏览器请求下载。浏览器可能保存、询问或阻止；此状态不证明文件已保存。'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('late PII delivery after account ABA does not restore status', (
    tester,
  ) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery();
    final pending = delivery.deferNext();
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    await tester.tap(
      find.byKey(const ValueKey('request-personal-pii-export-download')),
    );
    await tester.pump();
    expect(delivery.requests, hasLength(1));

    harness.identity.emit(_signedInSnapshot('other-subject'));
    harness.identity.emit(_signedInSnapshot('test-subject'));
    await tester.pump();
    pending.complete(const ManagementReportDownloadRequested());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal-pii-export-artifact')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('personal-pii-export-download-status')),
      findsNothing,
    );
    expect(exporter.calls, 1);
  });

  testWidgets('late PII delivery after capability revocation stays cleared', (
    tester,
  ) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery();
    final pending = delivery.deferNext();
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    await tester.tap(
      find.byKey(const ValueKey('request-personal-pii-export-download')),
    );
    await tester.pump();
    expect(delivery.requests, hasLength(1));

    harness.contextGateway.context = _exportContextWithoutCapability;
    await harness.appSession.refreshContext();
    await tester.pumpAndSettle();
    pending.complete(const ManagementReportDownloadRequested());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal-pii-export-artifact')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('personal-pii-export-download-status')),
      findsNothing,
    );
    expect(exporter.calls, 1);
  });

  testWidgets('late PII delivery after page disposal does not throw', (
    tester,
  ) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery();
    final pending = delivery.deferNext();
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    await tester.tap(
      find.byKey(const ValueKey('request-personal-pii-export-download')),
    );
    await tester.pump();
    expect(delivery.requests, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    pending.complete(const ManagementReportDownloadRequested());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable PII delivery keeps the prepared artifact', (
    tester,
  ) async {
    final harness = await _ExportHarness.start();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery(isAvailable: false);
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    final button = find.byKey(
      const ValueKey('request-personal-pii-export-download'),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('当前平台不提供 Web 浏览器下载。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('personal-pii-export-artifact')),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('当前平台不提供 Web 浏览器下载。'), findsOneWidget);
    expect(delivery.requests, isEmpty);
    expect(exporter.calls, 1);
  });

  testWidgets('English PII delivery status fits compact large-text view', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _ExportHarness.start();
    final gateway = _MemoryGateway();
    final exporter = _MemoryPersonalPiiExportGateway();
    final delivery = _MemoryExportDelivery();
    addTearDown(harness.close);
    await tester.pumpWidget(
      _app(
        gateway,
        text: const AppStrings('en'),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();

    await _preparePersonalPiiExport(tester);
    final button = find.byKey(
      const ValueKey('request-personal-pii-export-download'),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    final status = find.byKey(
      const ValueKey('personal-pii-export-download-status'),
    );
    await tester.ensureVisible(status);
    await tester.pumpAndSettle();
    _compactView(tester);
    await tester.pumpWidget(
      _app(
        gateway,
        text: const AppStrings('en'),
        textScaler: TextScaler.linear(2),
        identitySession: harness.identity,
        appSession: harness.appSession,
        exportGateway: exporter,
        exportDelivery: delivery,
        canExport: true,
        scopeKey: harness.scopeKey,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(status, 160);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSemantics(status)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      find.text(
        'The download was requested from the browser. The browser may save, ask, or block it; this does not prove that the file was saved.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'current assignee can revise relationship stage and shared note',
    (tester) async {
      final gateway = _MemoryGateway()..targets.add(_targetWithRelationship());
      await tester.pumpWidget(_app(gateway));
      await tester.pumpAndSettle();

      expect(find.textContaining('关系阶段: 明确推进 (6)'), findsOneWidget);
      expect(find.textContaining('共享跟进备注: 下周联系'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('promotion-target-target-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('target-relationship-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 · 达成项目目标关系').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('target-follow-up-note')),
        '已约定下次会面',
      );
      await tester.tap(find.byKey(const ValueKey('save-target-relationship')));
      await tester.pumpAndSettle();

      expect(gateway.updatedStage, 4);
      expect(gateway.updatedNote, '已约定下次会面');
      expect(gateway.expectedRevision, 2);
      expect(find.textContaining('关系阶段: 达成项目目标关系 (8)'), findsOneWidget);
    },
  );

  testWidgets('CSV import stays hidden without capability and cancels safely', (
    tester,
  ) async {
    final importer = _MemoryCsvImportGateway();
    await tester.pumpWidget(
      _app(_MemoryGateway(), importGateway: importer, canImport: false),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prepare-personal-pii-export')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('import-promotion-target-csv')),
      findsNothing,
    );

    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async => null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-promotion-target-csv')));
    await tester.pumpAndSettle();
    expect(importer.previewCalls, 0);
    expect(importer.confirmCalls, 0);
  });

  testWidgets('CSV preview requires explicit actions and confirmation', (
    tester,
  ) async {
    final directory = _MemoryGateway();
    final importer = _MemoryCsvImportGateway();
    await tester.pumpWidget(
      _app(
        directory,
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1, 2]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-promotion-target-csv')));
    await tester.pumpAndSettle();

    expect(importer.previewCalls, 1);
    expect(find.text('规范姓名'), findsOneWidget);
    expect(find.textContaining('possible duplicate · 可能是重复'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('promotion-target-csv-action-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立对象').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('promotion-target-csv-action-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(importer.confirmCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-csv-import-dialog')));
    await tester.pumpAndSettle();
    expect(importer.confirmCalls, 1);
    expect(importer.confirmations.single.requestId, 'request-1');
    expect(importer.confirmations.single.actions, [
      PersonalTargetCsvImportAction.create,
      PersonalTargetCsvImportAction.skip,
    ]);
    expect(directory.loadCalls, greaterThan(1));
    expect(find.text('规范姓名'), findsNothing);
  });

  testWidgets('hinted CSV rows require create separately or skip', (
    tester,
  ) async {
    final directory = _MemoryGateway();
    final importer = _MemoryCsvImportGateway(hintedOnly: true);
    await tester.pumpWidget(
      _app(
        directory,
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-promotion-target-csv')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('promotion-target-csv-action-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('建立对象'), findsNothing);
    expect(find.text('建立为独立对象'), findsOneWidget);
    await tester.tap(find.text('建立为独立对象').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.pumpWidget(
      _app(
        directory,
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('规范姓名'), findsOneWidget);
    await tester.pumpWidget(
      _app(
        directory,
        importGateway: importer,
        canImport: true,
        scopeKey: 'workspace-1/project-2',
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('规范姓名'), findsNothing);
  });

  testWidgets('invalid rows show only value-free issues', (tester) async {
    final importer = _MemoryCsvImportGateway(
      previewRejected: const PersonalTargetCsvImportRejected(
        PersonalTargetCsvImportFailureCode.invalidRows,
        issues: [
          PersonalTargetCsvImportIssue(
            rowNumber: 3,
            field: 'display_name',
            code: 'required',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-promotion-target-csv')));
    await tester.pumpAndSettle();

    expect(find.textContaining('#3: display_name (required)'), findsOneWidget);
    expect(find.text('不应显示的原始姓名'), findsNothing);
    expect(
      find.byKey(const ValueKey('promotion-target-csv-preview')),
      findsNothing,
    );
  });

  testWidgets(
    'unknown confirm outcome locks actions and retries same request',
    (tester) async {
      final importer = _MemoryCsvImportGateway(
        confirmResults: [
          const PersonalTargetCsvImportRejected(
            PersonalTargetCsvImportFailureCode.malformedResponse,
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          _MemoryGateway(),
          importGateway: importer,
          canImport: true,
          pickCsvFile: () async =>
              XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('import-promotion-target-csv')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('promotion-target-csv-action-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('建立对象').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('promotion-target-csv-action-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过').last);
      await tester.pumpAndSettle();

      Future<void> confirmOnce() async {
        await tester.tap(
          find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('confirm-csv-import-dialog')),
        );
        await tester.pumpAndSettle();
      }

      await confirmOnce();
      final action = tester.widget<DropdownButtonFormField>(
        find.byKey(const ValueKey('promotion-target-csv-action-1')),
      );
      expect(action.onChanged, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('import-promotion-target-csv')),
            )
            .onPressed,
        isNull,
      );
      await confirmOnce();
      expect(importer.confirmations, hasLength(2));
      expect(importer.confirmations.map((c) => c.requestId).toSet(), {
        'request-1',
      });
      expect(
        importer.confirmations[0].actions,
        importer.confirmations[1].actions,
      );
    },
  );

  testWidgets('stale confirmation clears preview and requires a new preview', (
    tester,
  ) async {
    final importer = _MemoryCsvImportGateway(
      confirmResults: [
        PersonalTargetCsvImportStale(
          PersonalTargetCsvImportConfirmReceipt(
            previewId: 'preview-id',
            requestId: 'request-1',
            stale: true,
            rowCount: 1,
            hintCount: 0,
            createdCount: 0,
            createdTargets: const [],
            completedAtUtc: DateTime.utc(2026, 8, 6),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        _MemoryGateway(),
        importGateway: importer,
        canImport: true,
        pickCsvFile: () async =>
            XFile.fromData(Uint8List.fromList([1]), name: 'targets.csv'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-promotion-target-csv')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('promotion-target-csv-action-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立对象').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('promotion-target-csv-action-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-promotion-target-csv-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-csv-import-dialog')));
    await tester.pumpAndSettle();

    expect(find.text('规范姓名'), findsNothing);
    expect(find.textContaining('预览已过期'), findsOneWidget);
    expect(importer.previewCalls, 1);
  });

  testWidgets('same-field conflict keeps proposal until assignee resolves it', (
    tester,
  ) async {
    final gateway = _MemoryGateway()..targets.add(_targetWithRelationship());
    gateway.conflictOnce = PromotionTargetConflict(
      current: _relationship(stage: 2, revision: 3, note: '服务器备注'),
      conflictId: 'conflict-1',
      conflictingFields: const ['stage', 'follow_up_note'],
      proposed: const PromotionTargetRelationshipProposal(
        expectedRevision: 2,
        stage: 4,
        displayStage: 8,
        lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
        followUpNote: '我的备注',
        reason: PromotionTargetRelationshipReason.progressUpdate,
        reasonDetail: null,
      ),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('promotion-target-target-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('target-relationship-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 · 达成项目目标关系').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('target-follow-up-note')),
      '我的备注',
    );
    await tester.tap(find.byKey(const ValueKey('save-target-relationship')));
    await tester.pumpAndSettle();

    expect(find.text('需要选择关系版本'), findsOneWidget);
    expect(find.textContaining('服务器备注'), findsWidgets);
    expect(find.textContaining('我的备注'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('apply-proposed-relationship')));
    await tester.pumpAndSettle();

    expect(gateway.resolvedConflictId, 'conflict-1');
    expect(gateway.updatedStage, 4);
    expect(find.textContaining('共享跟进备注: 我的备注'), findsOneWidget);
  });

  testWidgets(
    'assigned user creates and ends an explicit institution relation',
    (tester) async {
      final gateway = _MemoryGateway()
        ..targets.addAll([
          _plainTarget(
            id: 'person-1',
            type: PromotionTargetType.person,
            name: '王小明',
          ),
          _plainTarget(
            id: 'institution-1',
            type: PromotionTargetType.institution,
            name: '社区中心',
          ),
        ]);
      await tester.pumpWidget(_app(gateway));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('create-target-institution-relationship')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('institution-relationship-role')),
        '项目协调员',
      );
      await tester.tap(
        find.byKey(const ValueKey('save-target-institution-relationship')),
      );
      await tester.pumpAndSettle();

      expect(
        gateway.createdInstitutionKind,
        TargetInstitutionRelationshipKind.employmentRepresentative,
      );
      expect(find.text('王小明 ↔ 社区中心'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('end-target-institution-institution-relation-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('confirm-end-target-institution-relationship'),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.endedInstitutionRelationshipId, 'institution-relation-1');
      expect(find.textContaining('结束: 2026-08-07'), findsOneWidget);
    },
  );

  testWidgets('offline PII snapshot is labeled and remains read-only', (
    tester,
  ) async {
    final gateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-1',
          type: PromotionTargetType.person,
          name: '王小明',
        ),
      )
      ..fromOfflineCache = true
      ..authorizedAtUtc = DateTime.utc(2026, 8, 6, 12)
      ..expiresAtUtc = DateTime.utc(2026, 8, 9, 12);

    await tester.pumpWidget(
      _app(
        gateway,
        clock: _FixedClock(DateTime.utc(2026, 8, 9, 11, 59)),
        canImport: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('离线加密快照'), findsOneWidget);
    expect(find.textContaining('2026-08-06T12:00:00.000Z'), findsOneWidget);
    final createButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('create-promotion-target')),
    );
    expect(createButton.onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('import-promotion-target-csv')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('offline PII is removed from an open page at expiry', (
    tester,
  ) async {
    final gateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-1',
          type: PromotionTargetType.person,
          name: '到期前可见对象',
        ),
      )
      ..fromOfflineCache = true
      ..authorizedAtUtc = DateTime.utc(2026, 8, 6, 12)
      ..expiresAtUtc = DateTime.utc(2026, 8, 9, 12);

    await tester.pumpWidget(
      _app(gateway, clock: _FixedClock(DateTime.utc(2026, 8, 9, 11, 59))),
    );
    await tester.pumpAndSettle();
    expect(find.text('到期前可见对象'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));

    expect(find.text('到期前可见对象'), findsNothing);
    expect(find.textContaining('没有可用的未过期加密快照'), findsOneWidget);
  });

  testWidgets('a rejected refresh removes target PII already on screen', (
    tester,
  ) async {
    final gateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-1',
          type: PromotionTargetType.person,
          name: '撤权前可见对象',
        ),
      );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    expect(find.text('撤权前可见对象'), findsOneWidget);

    gateway.listFailure = PromotionTargetFailureCode.forbidden;
    await tester.tap(find.byKey(const ValueKey('refresh-promotion-targets')));
    await tester.pumpAndSettle();

    expect(find.text('撤权前可见对象'), findsNothing);
    expect(find.textContaining('没有可用的未过期加密快照'), findsOneWidget);
  });

  testWidgets('changing project scope removes the previous target list', (
    tester,
  ) async {
    final firstGateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-old',
          type: PromotionTargetType.person,
          name: '上一项目对象',
        ),
      );
    await tester.pumpWidget(
      _app(firstGateway, scopeKey: 'workspace-1/project-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('上一项目对象'), findsOneWidget);

    final secondGateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-new',
          type: PromotionTargetType.person,
          name: '当前项目对象',
        ),
      );
    await tester.pumpWidget(
      _app(secondGateway, scopeKey: 'workspace-1/project-2'),
    );
    await tester.pumpAndSettle();

    expect(find.text('上一项目对象'), findsNothing);
    expect(find.text('当前项目对象'), findsOneWidget);
  });

  testWidgets('retention review notice is generic and renewal is explicit', (
    tester,
  ) async {
    final gateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-review',
          type: PromotionTargetType.person,
          name: '不应出现在复核通知中的姓名',
        ),
      )
      ..retentionTasks.add(
        PromotionTargetRetentionTask(
          targetId: 'person-review',
          reviewDueAtUtc: DateTime.utc(2026, 8, 20),
        ),
      );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final notice = find.byKey(
      const ValueKey('promotion-target-retention-review'),
    );
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('不应出现在复核通知中的姓名'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('promotion-target-retention-person-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认继续保留').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-target-retention-renewal')),
    );
    await tester.pumpAndSettle();

    expect(gateway.retentionAction, PromotionTargetRetentionAction.renew);
    expect(
      gateway.retentionReason,
      PromotionTargetRetentionReason.purposeConfirmed,
    );
  });

  testWidgets('confirmed withdrawal removes target details from the page', (
    tester,
  ) async {
    final gateway = _MemoryGateway()
      ..targets.add(
        _plainTarget(
          id: 'person-withdrawal',
          type: PromotionTargetType.person,
          name: '准备撤回的对象',
        ),
      );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('promotion-target-retention-person-withdrawal'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('对方撤回资料').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-target-anonymization')),
    );
    await tester.pumpAndSettle();

    expect(gateway.retentionAction, PromotionTargetRetentionAction.anonymize);
    expect(gateway.retentionReason, PromotionTargetRetentionReason.withdrawal);
    expect(find.text('准备撤回的对象'), findsNothing);
  });
}

Future<void> _preparePersonalPiiExport(WidgetTester tester) async {
  final prepare = find.byKey(const ValueKey('prepare-personal-pii-export'));
  await tester.scrollUntilVisible(prepare, 160);
  await tester.tap(prepare);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(
    find.byKey(const ValueKey('personal-pii-export-password')),
    'private-password',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('confirm-personal-pii-export')));
  await tester.pumpAndSettle();
}

Widget _app(
  PromotionTargetGateway gateway, {
  AppStrings text = const AppStrings('zh'),
  TextScaler textScaler = TextScaler.noScaling,
  AppClock? clock,
  IdentitySession? identitySession,
  AppSession? appSession,
  PersonalPiiExportGateway? exportGateway,
  ManagementReportExportDelivery? exportDelivery,
  PersonalTargetCsvImportGateway? importGateway,
  bool canImport = false,
  bool canExport = false,
  Future<XFile?> Function()? pickCsvFile,
  String scopeKey = 'workspace-1/project-1',
}) {
  final identity = identitySession ?? const UnavailableIdentitySession();
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(
      body: PromotionTargetDirectoryPage(
        text: text,
        gateway: gateway,
        identitySession: identity,
        appSession:
            appSession ??
            AppSession(
              identitySession: identity,
              contextGateway: const UnavailableSessionContextGateway(),
            ),
        exportGateway:
            exportGateway ?? const DeferredPersonalPiiExportGateway(),
        exportDelivery:
            exportDelivery ?? const UnsupportedManagementReportExportDelivery(),
        idGenerator: _FixedIds(),
        clock: clock ?? _FixedClock(DateTime.utc(2026, 8, 6, 13)),
        scopeKey: scopeKey,
        importGateway:
            importGateway ?? const DeferredPersonalTargetCsvImportGateway(),
        canImport: canImport,
        canExport: canExport,
        pickCsvFile: pickCsvFile,
        canCreate: true,
        canConfigureStageAliases: true,
        canManageRelationship: true,
        canManageInstitutionRelationships: true,
      ),
    ),
  );
}

void _compactView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

final class _ExportHarness {
  _ExportHarness(this.identity, this.contextGateway, this.appSession);

  final FakeIdentitySession identity;
  final FakeSessionContextGateway contextGateway;
  final AppSession appSession;

  String get scopeKey =>
      '${_exportContext.appUserId}/${_exportContext.workspace.id}/'
      '${_exportContext.project.id}';

  static Future<_ExportHarness> start() async {
    final identity = FakeIdentitySession(
      initial: _signedInSnapshot('test-subject'),
      externalSubject: 'test-subject',
    );
    final contextGateway = FakeSessionContextGateway(
      context: _exportContext,
      availableContexts: const [_exportContext],
    );
    final appSession = AppSession(
      identitySession: identity,
      contextGateway: contextGateway,
    );
    await appSession.start();
    return _ExportHarness(identity, contextGateway, appSession);
  }

  static Future<_ExportHarness> startOffline() async {
    final identity = FakeIdentitySession(
      initial: _signedInSnapshot('test-subject'),
      externalSubject: 'test-subject',
    );
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'test-subject',
      context: _exportContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2030, 1, 2, 12),
    );
    final contextGateway = FakeSessionContextGateway(
      context: _exportContext,
      availableContexts: const [_exportContext],
      rejectWith: SessionContextFailureCode.networkUnavailable,
    );
    final appSession = AppSession(
      identitySession: identity,
      contextGateway: contextGateway,
      offlinePiiVault: vault,
    );
    await appSession.start();
    return _ExportHarness(identity, contextGateway, appSession);
  }

  Future<void> close() async {
    await appSession.close();
    await identity.close();
  }
}

final class _MemoryPersonalPiiExportGateway
    implements PersonalPiiExportGateway {
  _MemoryPersonalPiiExportGateway({bool pending = false})
    : _pending = pending ? Completer<PersonalPiiExportResult>() : null;

  final Completer<PersonalPiiExportResult>? _pending;
  var calls = 0;
  final artifact = PersonalPiiExportArtifact(bytes: const [123, 125]);

  PersonalPiiExportResult get _ready => PersonalPiiExportReady(artifact);

  @override
  Future<PersonalPiiExportResult> export({
    required bool Function() requestIsCurrent,
  }) {
    calls++;
    return _pending?.future ?? Future.value(_ready);
  }

  void complete() => _pending!.complete(_ready);

  @override
  Future<void> close() async {}
}

final class _MemoryExportDelivery implements ManagementReportExportDelivery {
  _MemoryExportDelivery({this.isAvailable = true});

  @override
  final bool isAvailable;
  final requests = <ExportDownloadArtifact>[];
  final _pending = <Completer<ManagementReportExportDeliveryResult>>[];

  Completer<ManagementReportExportDeliveryResult> deferNext() {
    final completer = Completer<ManagementReportExportDeliveryResult>();
    _pending.add(completer);
    return completer;
  }

  @override
  Future<ManagementReportExportDeliveryResult> requestDownload(
    ExportDownloadArtifact artifact,
  ) {
    requests.add(artifact);
    if (_pending.isNotEmpty) return _pending.removeAt(0).future;
    return Future.value(const ManagementReportDownloadRequested());
  }
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _MemoryOfflinePiiLockStore implements OfflinePiiLockStore {
  final locks = <String, OfflinePiiLock>{};

  @override
  Future<void> clear(String scopeKey) async => locks.remove(scopeKey);

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => locks[scopeKey];

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async =>
      locks[scopeKey] = lock;
}

IdentitySnapshot _signedInSnapshot(String subject) => IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(
    externalSubject: subject,
    email: 'owner@example.test',
  ),
  expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
);

const _exportContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: '当前项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: {'export_target_pii', 'view_assigned_target_pii'},
);

const _exportContextWithoutCapability = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: '当前项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: {'view_assigned_target_pii'},
);

final class _FixedIds implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'request-${++_next}';
}

final class _MemoryGateway
    implements PromotionTargetGateway, PromotionTargetRetentionGateway {
  var loadCalls = 0;
  final targets = <PromotionTargetProfile>[];
  String? createdName;
  String? requestId;
  int? updatedStage;
  int? expectedRevision;
  String? updatedNote;
  String? resolvedConflictId;
  PromotionTargetConflict<PromotionTargetRelationship>? conflictOnce;
  final institutionRelationships = <TargetInstitutionRelationship>[];
  TargetInstitutionRelationshipKind? createdInstitutionKind;
  String? endedInstitutionRelationshipId;
  bool fromOfflineCache = false;
  DateTime? authorizedAtUtc;
  DateTime? expiresAtUtc;
  PromotionTargetFailureCode? listFailure;
  final retentionTasks = <PromotionTargetRetentionTask>[];
  PromotionTargetRetentionAction? retentionAction;
  PromotionTargetRetentionReason? retentionReason;

  @override
  Future<PromotionTargetResult<List<PromotionTargetRetentionTask>>>
  loadRetentionTasks() async => PromotionTargetSuccess(List.of(retentionTasks));

  @override
  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  }) async {
    retentionAction = action;
    retentionReason = reason;
    if (action == PromotionTargetRetentionAction.anonymize) {
      targets.removeWhere((target) => target.id == targetId);
      retentionTasks.removeWhere((task) => task.targetId == targetId);
    } else {
      retentionTasks.removeWhere((task) => task.targetId == targetId);
    }
    return PromotionTargetSuccess(
      PromotionTargetRetentionOutcome(
        targetId: targetId,
        status: action == PromotionTargetRetentionAction.anonymize
            ? PromotionTargetRetentionStatus.anonymized
            : PromotionTargetRetentionStatus.active,
        duplicate: false,
        reviewDueAtUtc: action == PromotionTargetRetentionAction.renew
            ? DateTime.utc(2027, 8, 6)
            : null,
      ),
    );
  }

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async {
    loadCalls++;
    final failure = listFailure;
    if (failure != null) return PromotionTargetRejected(failure);
    return PromotionTargetSuccess(
      List.of(targets),
      authorizedAtUtc: authorizedAtUtc,
      expiresAtUtc: expiresAtUtc,
      fromOfflineCache: fromOfflineCache,
    );
  }

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) async {
    createdName = displayName;
    this.requestId = requestId;
    final target = PromotionTargetProfile(
      id: 'target-1',
      type: type,
      displayName: displayName,
      phone: phone,
      email: email,
      createdAtUtc: DateTime.utc(2026, 8, 6),
    );
    targets.add(target);
    return PromotionTargetSuccess(target);
  }

  @override
  Future<PromotionTargetResult<PromotionTargetRelationship>>
  updateRelationship({
    required String targetId,
    required int expectedRevision,
    required int stage,
    required PromotionTargetRelationshipLifecycle lifecycleStatus,
    required String? followUpNote,
    required PromotionTargetRelationshipReason reason,
    required String? reasonDetail,
    required String mutationId,
    required String? resolvedConflictId,
  }) async {
    final pendingConflict = conflictOnce;
    if (pendingConflict != null && resolvedConflictId == null) {
      conflictOnce = null;
      return pendingConflict;
    }
    updatedStage = stage;
    this.expectedRevision = expectedRevision;
    updatedNote = followUpNote;
    this.resolvedConflictId = resolvedConflictId;
    final old = targets.single.projectRelationship!;
    final updated = PromotionTargetRelationship(
      targetId: targetId,
      projectId: old.projectId,
      stage: stage,
      displayStage: stage * 2,
      lifecycleStatus: lifecycleStatus,
      followUpNote: followUpNote,
      revisionNumber: expectedRevision + 1,
      updatedAtUtc: DateTime.utc(2026, 8, 6, 13),
      stageAliases: old.stageAliases,
      history: old.history,
    );
    targets[0] = PromotionTargetProfile(
      id: targets.single.id,
      type: targets.single.type,
      displayName: targets.single.displayName,
      phone: targets.single.phone,
      email: targets.single.email,
      createdAtUtc: targets.single.createdAtUtc,
      hasCurrentProjectRelationship: true,
      projectRelationship: updated,
    );
    return PromotionTargetSuccess(updated);
  }

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({
    required List<PromotionTargetStageAlias> aliases,
  }) async => PromotionTargetSuccess(aliases);

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() async =>
      PromotionTargetSuccess(List.of(institutionRelationships));

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) async {
    createdInstitutionKind = kind;
    final relationship = TargetInstitutionRelationship(
      id: 'institution-relation-1',
      personTargetId: personTargetId,
      institutionTargetId: institutionTargetId,
      kind: kind,
      roleDescription: roleDescription,
      startedAtUtc: DateTime.utc(2026, 8, 6),
      endedAtUtc: null,
      status: TargetInstitutionRelationshipStatus.active,
      revisionNumber: 1,
      history: [
        TargetInstitutionRelationshipRevision(
          revisionNumber: 1,
          event: TargetInstitutionRelationshipEvent.created,
          oldStatus: null,
          newStatus: TargetInstitutionRelationshipStatus.active,
          endedAtUtc: null,
          changedByAppUserId: 'user-1',
          changedAtUtc: DateTime.utc(2026, 8, 6),
        ),
      ],
    );
    institutionRelationships.insert(0, relationship);
    return PromotionTargetSuccess(relationship);
  }

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) async {
    endedInstitutionRelationshipId = relationshipId;
    final current = institutionRelationships.single;
    final ended = TargetInstitutionRelationship(
      id: current.id,
      personTargetId: current.personTargetId,
      institutionTargetId: current.institutionTargetId,
      kind: current.kind,
      roleDescription: current.roleDescription,
      startedAtUtc: current.startedAtUtc,
      endedAtUtc: DateTime.utc(2026, 8, 7),
      status: TargetInstitutionRelationshipStatus.ended,
      revisionNumber: expectedRevision + 1,
      history: current.history,
    );
    institutionRelationships[0] = ended;
    return PromotionTargetSuccess(ended);
  }

  @override
  Future<void> close() async {}
}

final class _MemoryCsvImportGateway implements PersonalTargetCsvImportGateway {
  _MemoryCsvImportGateway({
    this.hintedOnly = false,
    this.previewRejected,
    List<PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>>?
    confirmResults,
  }) : confirmResults = confirmResults ?? [];

  final bool hintedOnly;
  final PersonalTargetCsvImportRejected<PersonalTargetCsvImportPreview>?
  previewRejected;
  final List<
    PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>
  >
  confirmResults;
  var previewCalls = 0;
  var confirmCalls = 0;
  final confirmations = <PersonalTargetCsvImportConfirmation>[];

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportPreview>>
  preview({required List<int> csvBytes}) async {
    previewCalls++;
    final rejection = previewRejected;
    if (rejection != null) return rejection;
    final rows = [
      PersonalTargetCsvImportPreviewRow(
        rowNumber: 1,
        type: PromotionTargetType.person,
        displayName: '规范姓名',
        phone: '555-0101',
        email: null,
        hinted: hintedOnly,
      ),
      if (!hintedOnly)
        const PersonalTargetCsvImportPreviewRow(
          rowNumber: 2,
          type: PromotionTargetType.institution,
          displayName: 'possible duplicate · 可能是重复',
          phone: null,
          email: 'office@example.test',
          hinted: true,
        ),
    ];
    return PersonalTargetCsvImportSuccess(
      PersonalTargetCsvImportPreview(
        receipt: PersonalTargetCsvImportPreviewReceipt(
          previewId: 'preview-id',
          rowCount: rows.length,
          hintedRows: [
            for (final row in rows)
              if (row.hinted) row.rowNumber,
          ],
          previewedAtUtc: DateTime.utc(2026, 8, 6),
          expiresAtUtc: DateTime.utc(2026, 8, 6, 1),
        ),
        rows: rows,
      ),
    );
  }

  @override
  Future<PersonalTargetCsvImportResult<PersonalTargetCsvImportConfirmReceipt>>
  confirm({required PersonalTargetCsvImportConfirmation confirmation}) async {
    confirmCalls++;
    confirmations.add(confirmation);
    if (confirmResults.isNotEmpty) return confirmResults.removeAt(0);
    return PersonalTargetCsvImportSuccess(
      PersonalTargetCsvImportConfirmReceipt(
        previewId: confirmation.previewId,
        requestId: confirmation.requestId,
        stale: false,
        rowCount: confirmation.rows.length,
        hintCount: 1,
        createdCount: 1,
        createdTargets: const [],
        completedAtUtc: DateTime.utc(2026, 8, 6),
      ),
    );
  }

  @override
  Future<void> close() async {}
}

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

PromotionTargetProfile _plainTarget({
  required String id,
  required PromotionTargetType type,
  required String name,
}) => PromotionTargetProfile(
  id: id,
  type: type,
  displayName: name,
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2026, 8, 6),
);

PromotionTargetProfile _targetWithRelationship() => PromotionTargetProfile(
  id: 'target-1',
  type: PromotionTargetType.person,
  displayName: '王小明',
  phone: null,
  email: null,
  createdAtUtc: DateTime.utc(2026, 8, 6),
  hasCurrentProjectRelationship: true,
  projectRelationship: _relationship(stage: 3, revision: 2, note: '下周联系'),
);

PromotionTargetRelationship _relationship({
  required int stage,
  required int revision,
  required String? note,
}) => PromotionTargetRelationship(
  targetId: 'target-1',
  projectId: 'project-1',
  stage: stage,
  displayStage: stage * 2,
  lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
  followUpNote: note,
  revisionNumber: revision,
  updatedAtUtc: DateTime.utc(2026, 8, 6, 12),
  stageAliases: [
    for (var value = 0; value <= 4; value++)
      PromotionTargetStageAlias(
        stage: value,
        displayStage: value * 2,
        displayName: null,
      ),
  ],
  history: [
    PromotionTargetRelationshipRevision(
      revisionNumber: revision,
      oldStage: stage == 0 ? null : stage - 1,
      newStage: stage,
      oldLifecycleStatus: stage == 0
          ? null
          : PromotionTargetRelationshipLifecycle.active,
      newLifecycleStatus: PromotionTargetRelationshipLifecycle.active,
      followUpNote: note,
      changedFields: const ['stage', 'follow_up_note'],
      reasonCode: 'progress_update',
      reasonDetail: null,
      changedByAppUserId: 'user-1',
      changedAtUtc: DateTime.utc(2026, 8, 6, 12),
    ),
  ],
);
