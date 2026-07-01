# TestFlight build 2.1.29 build 20

Date: 2026-07-01

## Scope

- Improved vehicle-level income discoverability and the Add income UI.
- Fixed iOS vehicle long-press Edit so it opens the same Vehicle Details editor as the normal Edit button.
- Verified iOS long-press Duplicate/Delete behavior and Sold quick-sale form behavior.
- Improved empty-photo handling: the empty photo area no longer looks like a dead Add Photos button in view mode, and the edit-mode Add Photos target opens the system picker.
- Matched Android vehicle detail discoverability for vehicle income and empty-photo Add Photos behavior.

## Local QA

- iOS iPhone 17 Pro simulator build/run passed.
- iOS Vehicle income flow passed:
  - opened vehicle details
  - added a temporary income entry
  - verified total and income row rendering
  - deleted the temporary income entry
- iOS photo flow passed:
  - view mode shows an informational no-photo state
  - edit mode Add Photos opens the system photo picker
  - Manage is not shown as a disabled dead action when there are no photos
- iOS context-menu flow passed:
  - long-press Edit opens Vehicle Details in edit mode with Done
  - Duplicate creates a separate vehicle without copying VIN or inventory ID
  - Delete shows confirmation and removes the duplicated test vehicle
  - Sold opens the quick-sale sheet; saving was not performed on the live demo vehicle
- Android `./gradlew assembleDebug` passed.
- Android emulator UI smoke was not run because no Android device was attached and no AVDs were listed on this machine.
- `git diff --check` passed.

## TestFlight

- App Store Connect app: `Car Dealer Tracker`
- App Store app id: `6755675367`
- Bundle ID: `com.ezcar24.business`
- Version: `2.1.29`
- Build: `20`
- Build ID / Delivery UUID: `46cd3141-a6fa-4465-9409-34d9eff172e7`
- App Store version ID: `c9205f63-ec1d-40f6-a742-3e569d6f718d`
- Processing state: `VALID`
- Audience type: `APP_STORE_ELIGIBLE`
- Export compliance: `usesNonExemptEncryption=false`
- Internal TestFlight group: `ezcar24 business test`
- Internal group access: `hasAccessToAllBuilds=true`
- App Review submitted.
- Review submission ID: `68be8fcb-7899-4dfd-baf4-f446f727a1af`
- Review submission state: `WAITING_FOR_REVIEW`
- App Store state after submit: `WAITING_FOR_REVIEW`
- What's New updated for `en-US`, `ru`, `ja`, `ar-SA`, `pt-BR`, and `id`.

## What's New

- `en-US`: Added vehicle-level income tracking, improved vehicle detail editing and photo controls, and refined long-press vehicle actions for clearer inventory management.
- `ru`: Добавили учет доходов по автомобилю, улучшили редактирование карточки и управление фотографиями, а также доработали действия по долгому нажатию для более понятной работы со складом.
- `ja`: 車両ごとの収入管理を追加し、車両詳細の編集画面と写真操作を改善しました。長押しで使う車両アクションも、在庫管理がより分かりやすくなるよう調整しました。
- `ar-SA`: أضفنا تتبع الدخل لكل مركبة، وحسّنا تعديل تفاصيل المركبة وإدارة الصور، كما جعلنا إجراءات الضغط المطوّل على المركبات أوضح لإدارة المخزون.
- `pt-BR`: Adicionamos controle de receitas por veículo, melhoramos a edição dos detalhes e os controles de fotos, e refinamos as ações de toque longo para deixar a gestão do estoque mais clara.
- `id`: Kami menambahkan pelacakan pendapatan per kendaraan, menyempurnakan pengeditan detail dan kontrol foto, serta merapikan aksi tekan lama agar pengelolaan inventaris lebih jelas.

## Artifacts

- Archive: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044.xcarchive`
- Archive log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044.archive.log`
- Export log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044.export.log`
- IPA: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044-ipa/Ezcar24Business.ipa`
- SHA-256: `403d904a4a0a86059c4992218ef0a373bb6a5b62d28c6d69d17708a10f6c506a`
- altool validation log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044.altool-validate.log`
- altool upload log: `iOS Car Dealer Tracker/build/archives/Ezcar24Business-2.1.29-build20-20260701-222044.altool-upload.log`
- Export options: `iOS Car Dealer Tracker/build/archives/ExportOptions-AppStoreConnect-2.1.29-build20.plist`
- What's New JSON: `iOS Car Dealer Tracker/build/archives/whats-new-2.1.29-build20.json`
