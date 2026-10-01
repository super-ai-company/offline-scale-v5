import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_trae/services/update_service.dart';

Map<String, dynamic> release({
  String tag = 'v1.2.2',
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'assets': [
    <String, dynamic>{
      'name': 'offline-scale-android-$tag.apk',
      'browser_download_url':
          'https://github.com/super-ai-company/offline-scale-v5/releases/download/$tag/offline-scale-android-$tag.apk',
      'digest': 'sha256:${'a' * 64}',
      'size': 101757956,
    },
  ],
};
void main() {
  test('stable newer official APK includes integrity metadata', () {
    final update = AppUpdate.fromRelease(release(), '1.2.1');
    expect(update!.version, '1.2.2');
    expect(update.sha256, 'a' * 64);
  });
  test('never offers old, same, draft or prerelease builds', () {
    expect(AppUpdate.fromRelease(release(), '1.2.2'), isNull);
    expect(AppUpdate.fromRelease(release(), '1.3.0'), isNull);
    expect(AppUpdate.fromRelease(release(draft: true), '1.2.1'), isNull);
    expect(AppUpdate.fromRelease(release(prerelease: true), '1.2.1'), isNull);
    expect(
      AppUpdate.fromRelease(release(tag: 'v1.10.0'), '1.9.9')!.version,
      '1.10.0',
    );
  });
  test('missing digest, wrong repository and oversized assets fail closed', () {
    for (final change in [
      {'digest': null},
      {'browser_download_url': 'https://example.com/app.apk'},
      {'size': 300 * 1024 * 1024},
      {'size': 0},
    ]) {
      final data = release();
      (data['assets'] as List).first.addAll(change);
      expect(() => AppUpdate.fromRelease(data, '1.2.1'), throwsFormatException);
    }
  });
  test('malformed tags and ambiguous assets rejected', () {
    expect(
      () => AppUpdate.fromRelease(release(tag: 'v1.2.3-beta'), '1.2.1'),
      throwsFormatException,
    );
    final data = release();
    (data['assets'] as List).add((data['assets'] as List).first);
    expect(() => AppUpdate.fromRelease(data, '1.2.1'), throwsFormatException);
  });
}
