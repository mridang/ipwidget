#!/bin/bash
#
# build.sh <version> — builds the Release app and packages it for distribution.
#
# Produces two artifacts in the repo root:
#   • IPWidget.pkg — a double-click installer that drops the app into
#     /Applications and launches the headless agent (see installer/scripts).
#   • IPWidget.zip — the raw .app, for anyone who prefers a drag install.
#
# The app is built with the project's ad-hoc signing (CODE_SIGN_IDENTITY = "-")
# rather than unsigned: a valid signature is required for the widget extension to
# register with the system. It is NOT notarized (no Developer ID on CI), so the
# installer is from an "unidentified developer" — right-click → Open to run it.
#
set -euo pipefail

VERSION="${1:?usage: build.sh <version>}"
APP=".build/Build/Products/Release/IPWidget.app"

xcodebuild \
    -project IPWidget.xcodeproj \
    -scheme IPWidget \
    -configuration Release \
    -derivedDataPath .build \
    build

# Raw app, zipped with ditto so the signature/metadata survive.
ditto -c -k --keepParent "$APP" IPWidget.zip

# Installer package. --component reads the app bundle directly (no copy, so the
# signature stays intact) and installs it to /Applications, running postinstall.
pkgbuild \
    --component "$APP" \
    --install-location /Applications \
    --scripts installer/scripts \
    --identifier ng.mrida.IPWidget \
    --version "$VERSION" \
    IPWidget.pkg

echo "Built IPWidget.pkg and IPWidget.zip for $VERSION"
