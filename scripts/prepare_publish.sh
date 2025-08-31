#!/bin/bash

set -e

echo "🔍 Preparing flutter_graphql_codegen for publication..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found. Run this script from the package root."
    exit 1
fi

# Get current version from pubspec.yaml
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
print_status "Current version: $CURRENT_VERSION"

# Clean and get dependencies
print_status "Installing dependencies..."
dart pub get

# Format code
print_status "Formatting code..."
dart format .

# Analyze code
print_status "Analyzing code..."
if ! dart analyze --fatal-infos; then
    print_error "Static analysis failed. Fix the issues above."
    exit 1
fi

# Run tests
print_status "Running tests..."
if ! dart test; then
    print_error "Tests failed. Fix the failing tests."
    exit 1
fi

# Check if CHANGELOG.md is updated
if ! grep -q "$CURRENT_VERSION" CHANGELOG.md; then
    print_warning "CHANGELOG.md doesn't contain version $CURRENT_VERSION"
    print_warning "Please update CHANGELOG.md before publishing"
fi

# Dry run publish
print_status "Performing dry run publish check..."
if ! dart pub publish --dry-run; then
    print_error "Dry run publish failed. Fix the issues above."
    exit 1
fi

print_status "Package is ready for publication! 🚀"
echo ""
echo "To publish:"
echo "1. Ensure CHANGELOG.md is updated for version $CURRENT_VERSION"
echo "2. Commit all changes:"
echo "   git add ."
echo "   git commit -m \"Release v$CURRENT_VERSION\""
echo "3. Create and push a version tag:"
echo "   git tag v$CURRENT_VERSION"
echo "   git push origin main"
echo "   git push origin v$CURRENT_VERSION"
echo "4. GitHub Actions will automatically publish to pub.dev using OIDC"
echo ""
echo "Make sure automated publishing is configured on pub.dev:"
echo "   https://pub.dev/packages/flutter_graphql_codegen/admin"
echo ""
echo "Or publish manually (if needed):"
echo "   dart pub publish"
