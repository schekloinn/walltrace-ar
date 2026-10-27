# WallTrace AR — звіт готової IPA

- Дата збірки: 27 жовтня 2026 року.
- Репозиторій: https://github.com/schekloinn/walltrace-ar
- Успішна збірка: https://github.com/schekloinn/walltrace-ar/actions/runs/40581896148
- Коміт коду: `eaa21754d97c4c8ae2268a36bbd6f6423afc9ccf`.
- Xcode 16.4 (16F6), iPhoneOS SDK 18.5, XcodeGen 2.46.0; стандартний `macos-15-intel` runner.
- Вихідний файл: `WallTraceAR.ipa`, 56449 байтів.
- SHA-256: `4174711e8f4ec2bd43d7130d3958812b5490f56de4c796f7e44e70e5c7b6cdf7`.
- Bundle identifier: `local.walltrace.ar`; версія 1.0 (1).
- Архітектура arm64; мінімальна iOS 15.0; лише iPhone (`UIDeviceFamily=[1]`).
- Apple Swift compile/link, ad-hoc codesign verification, пакування й ZIP CRC пройшли.
- SHA-256 завантаженої IPA та зовнішнього artifact збігаються з результатом CI.

Для встановлення передайте **саме IPA** на iPhone і відкрийте через працездатний TrollStore. Платний Apple signing/profile не використовується. IPA не потрібно розпаковувати; розпаковують лише зовнішній ZIP artifact.

На фізичному iPhone файл ще не запускався. Реальний AR-трекінг та інсталяція TrollStore залишаються неперевіреними. Докладний перелік перевірок і сценаріїв — у `VALIDATION.md`.
