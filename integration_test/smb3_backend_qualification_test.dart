// On-device/simulator run of the live SMB3 backend qualification.
// Pass configuration with --dart-define; see the test file it wraps.
import 'package:integration_test/integration_test.dart';

import '../test/smb3_backend_qualification_test.dart' as qualification;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  qualification.main();
}
