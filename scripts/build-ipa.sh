#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'IPA 编译需要 macOS 和 Xcode；Linux 无法编译 Apple iOS SDK。' >&2
  exit 1
fi
command -v xcodegen >/dev/null || { echo '请先运行 brew install xcodegen' >&2; exit 1; }
xcodegen generate
xcodebuild -project ConversationTranslator.xcodeproj -scheme ConversationTranslator \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
mkdir -p dist
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
app = Path('build/Build/Products/Release-iphoneos/ConversationTranslator.app')
if not app.is_dir():
    raise SystemExit('未找到构建后的 .app')
with ZipFile('dist/ConversationTranslator-unsigned.ipa', 'w', ZIP_DEFLATED) as out:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            out.write(path, Path('Payload') / app.name / path.relative_to(app))
print('生成 dist/ConversationTranslator-unsigned.ipa；用于兼容的 TrollStore 或进一步签名。')
PY
