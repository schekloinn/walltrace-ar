# Puffline 1.0 — готовий IPA

Дата: 3 листопада 2026 року.

## Результат

- Файл: Puffline-1.0.ipa, 499 497 байтів.
- SHA-256: `dfa48ca3172611ab24a8fed9f8ecb9a5de311e6991415aca2714328f9a825c92`.
- Застосунок: `local.puffline.app`; віджет: `local.puffline.app.widget`.
- Обидва виконувані файли: Release, arm64, iPhone, мінімальна iOS 15.0.
- Підпис: ad-hoc, обидва компоненти мають однакову групу `group.local.puffline.shared`.
- IPA призначений для TrollStore, який перепідписує його під час встановлення.
- Демонстраційні дані DEBUG у Release не включено.

## Перевірки

36 host-перевірок пройшли: адаптивні ліміти, пауза, пропущені дні, DST,
зміна дати, округлення відсотка, серіалізація, реальне збереження/читання файлу,
захист попередньої історії від некоректного перезапису та відхилення пошкоджених копій.

На Mac пройшли повна Release-збірка, codesign --verify --deep --strict,
перевірки Mach-O, deployment target, entitlements, URL-схеми, WidgetKit extension і ZIP.
Після завантаження IPA локально повторено структурну перевірку й звірено SHA-256.

Інтерфейс попередньо переглянуто на симуляторі iPhone SE (3rd generation), iOS 18.6.
Це не перевірка встановлення або роботи на фізичному iPhone з iOS 15.8.7.
Встановлення через TrollStore, віджет, сповіщення й швидка дія іконки на такому телефоні ще не перевірені.

## Відтворення збірки

- GitHub Actions: https://github.com/schekloinn/walltrace-ar/actions/runs/41642055848
- Коміт коду: `34c68c6fe7a60f17340e278c7c52a63e9eb70485`.
- Гілка: `puffline-ios15`; основну гілку WallTrace не змінено.
- Xcode 16.4 (16F6), iPhoneOS SDK 18.5, XcodeGen 2.46.0.
- Команда: `bash scripts/build-ipa.sh`.
