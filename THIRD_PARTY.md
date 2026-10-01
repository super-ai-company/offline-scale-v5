# Third-party components / 第三方组件

- Flutter and Dart: see their upstream licenses.
- `vendor/presentation_displays`: vendored display plugin; license retained at `vendor/presentation_displays/LICENSE`.
- `android/app/libs/autoreplyprint.aar`: existing upstream USB printing SDK, namespace `com.caysn.autoreplyprint`.
- `android/app/libs/serialport-1.1.0.aar`: existing upstream scale serial SDK, namespace `com.weight.serialport`.
- SUNMI `printerlibrary:1.0.24`: built-in printer API adapter.
- Google MediaPipe `tasks-vision:0.10.35` and `mobilenet_v3_small.tflite`: experimental on-device image embedding.
- Other Dart dependencies: exact versions recorded in `pubspec.lock`.

The original repository did not provide a top-level license. This migration preserves existing source and component attribution and does not apply a new blanket license to third-party SDKs or assets. Public availability alone does not grant additional redistribution rights.

原仓库没有顶层许可文件。本次迁移保留来源与第三方组件归属，不把第三方 SDK、模型或素材统一重新授权。
