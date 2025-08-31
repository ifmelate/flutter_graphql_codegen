# Scripts

## prepare_publish.sh

Script to prepare and validate the package before publishing to pub.dev.

### Usage

```bash
./scripts/prepare_publish.sh
```

### What it does

- ✅ Installs dependencies
- ✅ Formats code
- ✅ Runs static analysis
- ✅ Executes tests
- ✅ Validates CHANGELOG.md
- ✅ Performs dry-run publish check
- ✅ Provides instructions for publishing

### Requirements

- Dart SDK 3.0.0 or higher
- All tests must pass
- Code must be properly formatted
- No static analysis errors

### Output

The script will guide you through the publishing process and provide specific commands to create release tags.
