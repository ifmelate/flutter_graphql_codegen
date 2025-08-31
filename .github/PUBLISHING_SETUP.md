# Publishing Setup for flutter_graphql_codegen

This document describes how to set up automated publishing to pub.dev via GitHub Actions using the modern OIDC (OpenID Connect) approach.

## Prerequisites

1. **Package is already published manually** ✅ (you mentioned this is done)
2. **GitHub repository is configured** ✅
3. **Valid pub.dev account** ✅
4. **Authenticated with pub.dev locally** ✅ (just completed with `dart pub login`)

## Modern Setup Steps (2024 Approach)

### 1. Enable Automated Publishing on pub.dev

1. **Go to your package page on pub.dev:**
   - Visit https://pub.dev/packages/flutter_graphql_codegen
   - Click on the "Admin" tab (you must be a package owner)

2. **Configure Automated Publishing:**
   - In the "Automated publishing" section, click "Configure automated publishing"
   - Select "GitHub Actions" as the publisher
   - Enter your repository: `ifmelate/flutter_graphql_codegen`
   - Set tag pattern: `v{{version}}` (this will trigger on tags like v1.0.0)
   - Enable "Require GitHub Actions environment"
   - Save the configuration

### 2. No GitHub Secrets Required! 🎉

The modern approach uses **OIDC (OpenID Connect)** which eliminates the need for storing sensitive tokens as GitHub secrets. The workflow uses `id-token: write` permissions and the official Dart publishing workflow.

### 3. Publishing Workflow

The automated publishing is triggered by:

#### Option A: Tag-based Publishing (Recommended)
```bash
# Create and push a version tag matching your pubspec.yaml version
git tag v1.0.1
git push origin v1.0.1
```

#### Option B: Manual Trigger
- Go to GitHub Actions tab
- Select "Publish to pub.dev" workflow
- Click "Run workflow"

### 4. Version Management

Before publishing, make sure to:

1. **Update version in pubspec.yaml**:
   ```yaml
   version: 1.0.1  # Increment appropriately
   ```

2. **Update CHANGELOG.md** with new changes

3. **Create git tag matching the version**:
   ```bash
   git add .
   git commit -m "Release v1.0.1"
   git tag v1.0.1
   git push origin main
   git push origin v1.0.1
   ```

### 5. What Happens During Publishing

The workflow automatically:
- ✅ Checks out the repository
- ✅ Sets up Dart SDK
- ✅ Runs `dart pub get`
- ✅ Verifies code formatting
- ✅ Runs static analysis
- ✅ Executes all tests
- ✅ Performs dry-run publish check
- ✅ Publishes to pub.dev using OIDC authentication

## Workflow Features

### CI Workflow (ci.yml)
- ✅ Runs on every push/PR
- ✅ Tests multiple Dart versions (3.0.0, stable)
- ✅ Code formatting checks
- ✅ Static analysis
- ✅ Test coverage reporting
- ✅ Dry-run publish check

### Publish Workflow (publish.yml)
- ✅ Triggered by version tags (v*.*.*)
- ✅ Can be manually triggered
- ✅ Full quality checks before publishing
- ✅ Automated publishing to pub.dev

## Security Notes

- Credentials are stored as encrypted GitHub secrets
- Tokens are only accessible during workflow execution
- Publishing requires all tests to pass
- Dry-run validation prevents invalid packages

## Troubleshooting

### Invalid credentials
If you get authentication errors:
1. Regenerate credentials by running `dart pub token` locally
2. Update the GitHub secrets with new tokens

### Version conflicts
- Ensure version in pubspec.yaml is higher than the current published version
- Version must follow semantic versioning (major.minor.patch)

### Failed tests
- All tests must pass before publishing
- Check the CI workflow for specific failures
- Fix issues and push new commits before retrying

## Commands for Manual Testing

```bash
# Test the package locally
dart pub get
dart analyze
dart test
dart pub publish --dry-run

# Create and test a release
git tag v1.0.1
dart pub publish --dry-run
```

## Next Steps

1. Add the GitHub secrets as described above
2. Test with a patch version bump (e.g., v1.0.1)
3. Monitor the GitHub Actions workflow execution
4. Verify successful publication on pub.dev
