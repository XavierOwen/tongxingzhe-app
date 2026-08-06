import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final version = QuestionnaireContract.parseVersion(fixture['questionnaire']);

  test('已发布问卷安装一次后可离线按项目和版本读取', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final online = QuestionnaireCatalog(
      database: database,
      remoteSource: _OneVersionRemote(version),
    );

    final first = await online.resolvePublishedVersion(
      projectId: version.projectId,
      versionId: version.id,
    );
    await online.close();
    final offline = QuestionnaireCatalog(database: database);
    final restored = await offline.resolvePublishedVersion(
      projectId: version.projectId,
      versionId: version.id,
    );

    expect(
      QuestionnaireContract.versionToJson(first!),
      fixture['questionnaire'],
    );
    expect(
      QuestionnaireContract.versionToJson(restored!),
      fixture['questionnaire'],
    );
  });

  test('相同版本 ID 不能跨项目读取或被静默改写', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final catalog = QuestionnaireCatalog(database: database);
    await catalog.installPublishedVersion(version);

    expect(
      await catalog.cachedVersion(
        projectId: '99999999-9999-4999-8999-999999999999',
        versionId: version.id,
      ),
      isNull,
    );
    final changed = QuestionnaireVersion(
      id: version.id,
      projectId: version.projectId,
      versionNumber: version.versionNumber,
      questions: [...version.questions.take(version.questions.length - 1)],
    );
    await expectLater(
      catalog.installPublishedVersion(changed),
      throwsA(
        isA<QuestionnaireCatalogException>().having(
          (error) => error.code,
          'code',
          'published_questionnaire_changed',
        ),
      ),
    );
  });
}

final class _OneVersionRemote implements QuestionnaireRemoteSource {
  _OneVersionRemote(this.version);

  final QuestionnaireVersion version;
  var closed = false;

  @override
  Future<QuestionnaireVersion?> fetchPublishedVersion(String versionId) async {
    return versionId == version.id ? version : null;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
