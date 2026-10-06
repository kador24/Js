# Jamal Phone Manager — Project Handoff

Prepared from the Jamal Phone Manager codebase for final validation and deployment.

Current app version: `1.1.1+4`.

## Prepared Android stack

- Flutter 3.47.6
- Dart 3.13+
- Java 17
- AGP 8.11.1
- Gradle 8.14.0
- Kotlin 2.2.20
- minSdk 23

## Main application layers

- `lib/database/` — SQLite schema and migrations
- `lib/models/` — domain models
- `lib/services/` — business logic, backup, Telegram, barcode and reports
- `lib/providers/` — application state
- `lib/screens/` — Android UI
- `lib/theme/` — Material 3 theme
- `.github/workflows/build-apk.yml` — CI build/test workflow

## Important implementation decisions

1. Stock is auditable through `stock_movements`.
2. Sale lines preserve historical cost.
3. Purchases update cost using weighted average.
4. Full returns restore stock and record refunds.
5. Expenses are voided instead of physically deleted.
6. Telegram credentials use Android secure storage.
7. Local backup is encrypted and includes product images.
8. WorkManager schedules weekly/monthly background backups.
9. The public storefront and private financial app remain separate.

## Final verification still required

The source archive has been statically audited and patched in this handoff. A full Flutter/Android build was not executed in this container because Flutter is not installed in the available runtime. GitHub Actions remains the authoritative build validation path.

A real Flutter runner should execute:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The current archive is prepared for that validation; this container did not run a full Android Flutter build.
