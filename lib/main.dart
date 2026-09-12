import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Registers license notices for the on-device model assets so the in-app
/// "Open source licenses" page (`showLicensePage`) lists them alongside
/// package licenses (design system §52).
///
/// All three models ship locally with the APK under Apache-2.0:
/// * MobileNetV2 feature extractor & int8 classifier — ONNX Model Zoo.
/// * all-MiniLM-L6-v2 tokenizer/text model (Hugging Face / savasy).
void _registerModelLicenses() {
  const apache2 = '''
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
''';

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'MobileNetV2 (ONNX Model Zoo)',
      'similar-image & video classifiers',
    ], apache2);
    yield LicenseEntryWithLineBreaks([
      'sentence-transformers/all-MiniLM-L6-v2',
      'on-device semantic search',
    ], apache2);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerModelLicenses();
  runApp(const ProviderScope(child: VoraFindApp()));
}
