import 'package:crisp_storage/crisp_storage.dart' show smbLicense;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['CrisperPlayer'],
      'Copyright © 2026 Christian Ströbele. Licensed under GNU AGPL version 3.\n\n'
      '${await rootBundle.loadString('assets/licenses/AGPL-3.0.txt')}',
    );
    yield const LicenseEntryWithLineBreaks(['libsmb2'], smbLicense);
    yield LicenseEntryWithLineBreaks([
      'Rust SMB backend (crisp_smb, smb2 and Rust crates)',
    ], await rootBundle.loadString('assets/licenses/RUST-SMB.txt'));
    yield LicenseEntryWithLineBreaks([
      'Filen / Internxt source notices',
    ], await rootBundle.loadString('assets/licenses/CLOUD-SDKS.txt'));
    yield LicenseEntryWithLineBreaks([
      'Mozilla Public License 2.0',
    ], await rootBundle.loadString('assets/licenses/MPL-2.0.txt'));
    yield LicenseEntryWithLineBreaks([
      'Native playback: Glint and miniaudio (Windows/Linux)',
    ], await rootBundle.loadString('assets/licenses/DESKTOP-AUDIO.txt'));
    yield LicenseEntryWithLineBreaks([
      'Portable speed processing: Bungee Basic, Signalsmith Stretch, WSOLA, Sonic',
      'Eigen and PFFFT',
    ], await rootBundle.loadString('assets/licenses/ANDROID-DSP.txt'));
    yield LicenseEntryWithLineBreaks([
      'Android NDK: packaged C++ runtime notices',
    ], await rootBundle.loadString('assets/licenses/ANDROID-NDK.txt'));
    for (final version in ['2.1', '3.0']) {
      yield LicenseEntryWithLineBreaks([
        'GNU LGPL $version',
      ], await rootBundle.loadString('assets/licenses/LGPL-$version.txt'));
    }
    yield LicenseEntryWithLineBreaks([
      'GNU GPL 3.0 (supplement to LGPL 3.0)',
    ], await rootBundle.loadString('assets/licenses/GPL-3.0.txt'));
    yield const LicenseEntryWithLineBreaks(
      ['SQLite'],
      'SQLite is in the public domain. Source and dedication: https://www.sqlite.org/copyright.html',
    );
  });
}
