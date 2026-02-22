#!/bin/bash
set -euo pipefail

echo "bandlock installer"
echo "=================="
echo ""

# Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "Xcode Command Line Tools required. Installing..."
    xcode-select --install
    echo "Re-run this script after installation completes."
    exit 1
fi

# Build and install
cd "$(dirname "$0")"
make install

echo ""
echo "Next steps:"
echo "  1. Run: /Applications/bandlock.app/Contents/MacOS/bandlock setup"
echo "  2. Grant Location Services access when prompted"
echo "  3. Done — bandlock will auto-connect to 5GHz at login"
