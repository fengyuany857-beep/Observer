#!/bin/bash
set -euo pipefail
if command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen already installed: $(xcodegen --version)"
else
  brew install xcodegen
  echo "xcodegen installed: $(xcodegen --version)"
fi
xcodegen generate --spec project.yml
