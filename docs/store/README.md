# App Store listing assets

English metadata is in `en-US`. The five iPhone 6.9-inch and five iPad 13-inch
screenshots under `screenshots/` are native simulator JPEG captures of the actual
production UI, using an isolated library of generated audio. They contain no
private accounts or copyrighted audiobook assets. Nothing is composited over the
screens, and JPEG capture avoids screenshot transparency restrictions.

Reproduce with a dedicated booted iOS simulator:

```sh
python3 scripts/capture_store_screenshots.py --device SIMULATOR_UUID --device-class iphone-6.9
# Use --device-class ipad-13 with a dedicated iPad simulator.
```

The loopback receiver asks `simctl` to capture each screen after the integration
fixture renders it. It accepts only the five expected screen names; the sample
library and its database are temporary. Do not use a simulator holding personal
data. Native `flutter test` uninstalls its test app after completion.

`scripts/prepare_appstore.py` and `scripts/upload_store_screenshots.py` default to
read-only preparation checks; `--write` updates only the editable iOS draft.
They use the existing ASC environment variables described in `docs/IOS_BUILD.md`.
Neither script submits review or releases the app publicly.
