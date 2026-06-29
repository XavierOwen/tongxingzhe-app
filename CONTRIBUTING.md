# Contributing

Thank you for helping improve 同行者 / Outreach Companion.

## Privacy rule

Do not commit real collected data.

That includes:

- Real names, phone numbers, WeChat IDs, emails, addresses, or precise meeting notes
- Database exports, screenshots containing personal data, or analytics from small real groups
- Production `.env` files, API keys, service-role keys, certificates, or private keys

Use synthetic examples only. If a bug needs a fixture, make the data fake and clearly mark it as synthetic.

## Checks

Before opening a pull request, run:

```bash
flutter analyze
flutter test
```

If the project lives in a non-ASCII path and `flutter analyze` crashes, run `dart analyze` or analyze a temporary ASCII-path copy until the Flutter analyzer issue is fixed.
