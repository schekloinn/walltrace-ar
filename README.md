# WallTrace AR — iPhone 7 / iOS 15.8.7

Мінімальний iOS-застосунок на Swift, UIKit, ARKit і SceneKit. Deployment target **iOS 15.0**, лише iPhone, орієнтація портретна. Зовнішніх runtime-залежностей немає. Вихідний проєкт задано через `project.yml` для XcodeGen; workflow генерує справжній `WallTraceAR.xcodeproj` і збирає device arm64.

**Цей ZIP містить вихідний код, не готову IPA.** IPA створюється після успішного запуску вашого GitHub Actions workflow. Збірку на macOS і запуск на фізичному iPhone тут не виконано: розробка та локальна перевірка відбувалися на Windows. Деталі перевірки — у `VALIDATION.md`.

## Отримати IPA без Mac

Потрібні Windows, GitHub-акаунт і інтернет; для встановлення IPA — iPhone з уже встановленим TrollStore. Платний Apple Developer account, сертифікат, provisioning profile та GitHub secrets для цього workflow не потрібні.

1. Розпакуйте `WallTraceAR-source.zip`. Усередині є папка `WallTraceAR`.
2. На GitHub створіть **новий публічний репозиторій** (наприклад, `walltrace-ar`). Для найпростішого завантаження залиште його порожнім, без автоматичного README.
3. Завантажте **вміст** папки `WallTraceAR` у корінь репозиторію. `project.yml` і `README.md` мають бути прямо в корені, а workflow — саме за шляхом `.github/workflows/build-ipa.yml`. Не завантажуйте лише ZIP і не додавайте зайвий рівень папки `WallTraceAR/`.
4. Найнадійніший варіант на Windows — Git. У PowerShell відкрийте папку з `project.yml`, потім виконайте команди нижче, замінивши `YOUR_LOGIN` і назву repo. Вони завантажать також приховану `.github`. Увійдіть у свій GitHub-акаунт, коли Git попросить.

   ```powershell
   git init -b main
   git add .
   git commit -m "Add WallTrace AR"
   git remote add origin https://github.com/YOUR_LOGIN/walltrace-ar.git
   git push -u origin main
   ```

   Альтернатива: **Add file → Upload files** у браузері. У Провіднику ввімкніть показ прихованих елементів, перетягніть усі файли й папки, включно з `.github`. Після commit перевірте, що workflow справді присутній за потрібним шляхом. За потреби створіть його через **Add file → Create new file**, указавши повний шлях `.github/workflows/build-ipa.yml` та скопіювавши включений файл без змін.
5. У репозиторії відкрийте **Actions** і дозвольте Actions, якщо GitHub пропонує це для нового repo. Оберіть **Build WallTrace AR IPA → Run workflow → main → Run workflow**. Для ручного запуску `workflow_dispatch` файл має бути в default branch. [Документація GitHub](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
6. Дочекайтеся зеленого результату. Відкрийте run → **Artifacts → WallTraceAR-IPA**. Для завантаження artifact потрібно бути авторизованим у GitHub. Збережіть ZIP artifact і **розпакуйте його**: усередині буде `WallTraceAR.ipa`, SHA-256 та опис фактичного toolchain. IPA повторно розпаковувати не треба: саме її відкриває TrollStore.
7. Передайте `WallTraceAR.ipa` на iPhone у «Файли» зручним для вас способом. Відкрийте її через меню **Поширити → TrollStore** або **TrollStore → + → Install IPA** та підтвердьте встановлення. Запустіть WallTrace AR і дозвольте камеру.

Workflow використовує `xcodebuild ... -sdk iphoneos -destination generic/platform=iOS ARCHS=arm64`, вимикає звичайне підписання, потім підписує bundle локально через `codesign --sign -`. Це **локальний ad-hoc підпис**, а не Apple Ad Hoc distribution із профілем. Пакування створює `Payload/WallTrace AR.app` усередині IPA. Підпис без профілю сам по собі не дозволяє звичайне встановлення на iOS: ця IPA призначена для TrollStore, який обробляє підпис під час встановлення. [Офіційний TrollStore](https://github.com/opa334/TrollStore).

## Безкоштовні умови та toolchain

Перевірено **27 жовтня 2026 року**. Час стандартних GitHub-hosted runners для **публічних repo** безкоштовний; `macos-15` входить до стандартних runner labels. Платні larger runners тут не використовуються. Для приватних repo діють квоти плану й можлива оплата понад них. [GitHub: runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Безкоштовність runner time не означає необмежене зберігання: у GitHub Free включено 500 MB artifact storage, спільного з GitHub Packages; є й інші ліміти сервісу. Тут artifact зберігаються **3 дні**, збірка обмежена 30 хвилинами. Видаляйте старі artifacts, якщо сховище заповнене. Акаунтні обмеження чи політики організації також можуть заборонити запуск. [Ліміти GitHub](https://docs.github.com/en/actions/reference/limits).

Обрано **`macos-15` + `/Applications/Xcode_16.4.app`**: Xcode 16.4 є в опублікованому списку цього arm64 runner image; workflow друкує реальні версії й зупиняється, якщо Xcode зник. Образи змінюються з часом. [Поточний inventory GitHub](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md). Apple розрізняє deployment target і підтримку підключеного пристрою: збірка generic device не потребує підключення iPhone 7 до нового Xcode. [Таблиця Xcode Apple](https://developer.apple.com/xcode/system-requirements).

XcodeGen встановлюється через Homebrew лише як інструмент збірки. Версія записується в `toolchain.txt`; застосунок його не містить. [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## TrollStore на iPhone 7 з iOS 15.8.7

iPhone 7 має A10 Fusion (arm64), а не arm64e. Базовий ARKit вимагає A9 або новіший; у коді також є перевірка `ARWorldTrackingConfiguration.isSupported`. [Apple: iPhone 7](https://support.apple.com/en-gb/111943), [Apple: ARKit та площини](https://developer.apple.com/documentation/arkit/tracking-and-visualizing-planes).

**Підтримка TrollStore і спосіб його першого встановлення — різні питання.** У README `opa334/TrollStore` заявлено підтримку iOS 14.0 beta 2–16.6.1, а отже 15.8.7 потрапляє в цей діапазон. Для конкретного поєднання A10 / 15.8.7 актуальна таблиця інсталяції спрямовує на **TrollRestore**. [Офіційний TrollStore](https://github.com/opa334/TrollStore), [таблиця, на яку посилається upstream](https://ios.cfw.guide/installing-trollstore/).

Якщо TrollStore вже встановлений, пропустіть підготовку й відкрийте IPA. Якщо ні, використовуйте [оригінальний JJTech0130/TrollRestore](https://github.com/JJTech0130/TrollRestore) та [інструкцію, на яку посилається його README](https://ios.cfw.guide/installing-trollstore-trollrestore/). Upstream вказує підтримку 15.2–16.7 RC і 17.0 та Windows 10+ з iTunes. Це дозволяє підготувати iPhone з Windows, без Mac. TrollRestore змінює вибраний видалюваний системний застосунок через механізм резервного відновлення; виконайте попереднє резервне копіювання й умови актуального guide, зокрема тимчасове вимкнення Find My. Після завершення guide поверніть Find My та встановіть persistence helper через налаштування TrollStore. Upstream окремо пояснює потребу в helper і відновлення заміненого системного застосунку через видалення та повторне встановлення.

**Не використовуйте TrollInstallerX для 15.8.7:** поточна таблиця для гілки iOS 15 обмежує цей шлях версією **15.8.6**. Узагальнений старий діапазон у README інсталятора не є підтвердженням для 15.8.7. [Таблиця інсталяції](https://ios.cfw.guide/installing-trollstore/), [репозиторій інсталятора](https://github.com/alfiecg24/TrollInstallerX). Сумісність конкретної процедури на вашому телефоні в межах цієї роботи не перевірялася.

## Користування

1. Підготуйте PNG у «Файлах». Можна почати з `Samples/test-wall.png`: він має прозорий фон і несиметричні позначки TOP/LEFT для перевірки орієнтації.
2. Відкрийте WallTrace AR, дозвольте камеру, натисніть **Імпорт PNG**. Підтримується один PNG до **32 МіБ**. Текстура зменшується до 2048 px по довшій стороні зі збереженням пропорцій та alpha. APNG читається як перший кадр. Фото-бібліотека та її дозвіл не використовуються.
3. Повільно рухайте телефон уздовж **добре освітленої текстурованої вертикальної стіни**. Спочатку ARKit має знайти її поверхню. Біла стіна без деталей, скло, відблиски, темрява та швидкий рух ускладнюють пошук. Лічильник «стін» показує вертикальні площини, а не архітектурно окремі стіни.
4. Наведіть центральний **+** на знайдену поверхню. Він стане зеленим, і кнопка **Розмістити на стіні** активується за нормального трекінгу. Натисніть її. Розміщення поза геометрією знайденої вертикальної площини не допускається.
5. **Ширина (масштаб)** задає ширину 5–200 см; висота змінюється пропорційно. **Непрозорість** 5–100% додається до власної прозорості PNG. Повзунки працюють до та після розміщення.
6. **Перемістити** прибирає поточний anchor і дозволяє нове розміщення на знайденій стіні. **Скинути AR** очищає anchors і починає пошук стін заново, зберігаючи вибраний PNG та значення повзунків у пам’яті. Новий успішно імпортований PNG також потребує розміщення; скасування чи помилка імпорту не замінює попередній PNG.

Зображення — площина SceneKit, дочірня до вузла **окремого ARAnchor зі світовою матрицею**, а не до камери. Воно орієнтоване вертикально за гравітацією, паралельно стіні, зі зсувом 5 мм до користувача. Після розміщення застосунок не переприв’язує його до кожного нового кадру. [Apple: ARAnchor](https://developer.apple.com/documentation/arkit/aranchor), [world tracking](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration).

## Межі точності та сесії

iPhone 7 **не має LiDAR**. Застосунок використовує камеру та інерційний трекінг; точність не гарантована, можливі дрейф, тремтіння й стрибки при уточненні карти. Це орієнтир для обведення, не вимірювальний інструмент і не фізичний проєктор. PNG видно лише на екрані телефона. Розмір у сантиметрах є оцінкою AR, а не каліброваним виміром.

Фіксація діє **лише в поточній AR-сесії**. ARWorldMap не зберігається. Після переходу застосунку у фон, блокування телефона, системного переривання, reset або нового запуску потрібні пошук стіни та повторне розміщення. PNG не зберігається між запусками. Коли tracking обмежений, картинка тимчасово приховується, а UI пояснює причину; при відновленні нормального трекінгу в межах сесії вона з’являється знову. [Apple: життєвий цикл і якість трекінгу](https://developer.apple.com/documentation/arkit/managing-session-life-cycle-and-tracking-quality).

Камера обробляється локально, PNG не завантажується застосунком на сервер. Завантаження файлу з iCloud у системному picker може потребувати інтернету. При відмові в дозволі камери є кнопка переходу в Параметри; після повернення застосунок повторно перевіряє дозвіл. Непідтримуваний AR має окреме повідомлення.

## Якщо щось не працює

- Немає **Run workflow**: перевірте default branch і точний шлях `.github/workflows/build-ipa.yml`.
- Workflow червоний: відкрийте невдалий step і artifact **WallTraceAR-build-diagnostics**. Відсутність artifact IPA означає, що готової збірки немає. `build.log` з’являється лише після початку xcodebuild, а generated project — після XcodeGen.
- Xcode 16.4 більше немає: звірте inventory runner і таблицю Apple, оберіть установлений Xcode з підтримкою deployment iOS 15, змініть `DEVELOPER_DIR` у workflow та повторіть збірку. Не підвищуйте deployment target для iPhone 7.
- Переповнене artifact storage: видаліть старі artifacts у власному GitHub-акаунті та запустіть збірку повторно.
- IPA не відкривається: розпакуйте зовнішній artifact ZIP; передайте саме `.ipa` в уже працездатний TrollStore. Якщо застосунки TrollStore перестали запускатися після оновлення кешу іконок, скористайтеся **Refresh App Registrations** у своєму persistence helper згідно з upstream TrollStore.
- Кнопка розміщення неактивна: потрібні PNG, нормальний tracking і перетин + з геометрією знайденої вертикальної площини. Додайте світла, повільно огляньте текстуру, за потреби скиньте AR.

## Файли та локальна збірка на Mac (необов’язково)

- `WallTraceAR/*.swift` — застосунок; `Info.plist` — дозвіл камери та iOS-конфігурація.
- `project.yml` — специфікація XcodeGen; `.github/workflows/build-ipa.yml` — ручна CI-збірка.
- `scripts/build-ipa.sh` — генерація, компіляція, перевірка arm64/мінімальної iOS, ad-hoc підпис, IPA.
- `VALIDATION.md` — фактичні локальні перевірки та що ще потрібно випробувати.

На Mac з Xcode 16.4: встановіть XcodeGen (`brew install xcodegen`), відкрийте Terminal у корені проєкту й запустіть `DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer bash scripts/build-ipa.sh`. Для повторного запуску використайте свіжу копію або перемістіть стару папку `build` в інше місце. Згенерований `.xcodeproj` можна відкрити в Xcode. Усі посилання та умови наведені станом на дату перевірки; вони можуть змінюватися.
