#!/bin/sh
# Version bump script — single source of truth for all vyakarana
# version references.
#
# Usage:
#   sh scripts/version-bump.sh 1.0.4          # bump VERSION + regenerate everything
#   sh scripts/version-bump.sh "$(cat VERSION)" # regenerate without bumping
#
# Why this exists: through 1.0.3 the `vyk --version` literal lived
# as a hardcoded `var VYK_VERSION = "vyk X.Y.Z"` in src/main.cyr.
# The 1.0.2 -> 1.0.3 cut nearly shipped with `vyk --version` still
# reporting 1.0.2 because the CLI literal was a fourth file outside
# the documented sync checklist (VERSION / cyrius.cyml [package] /
# CHANGELOG header). This script regenerates src/version_str.cyr
# unconditionally so the literal can never drift again. Same pattern
# cyrius (cc5 --version) and cyim use.

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Current: $(cat VERSION)"
    exit 1
fi

NEW="$1"
OLD=$(cat VERSION | tr -d '[:space:]')

# 1. Regenerate src/version_str.cyr unconditionally — including
#    same-version invocations. This file is the single source of
#    truth for the `vyk --version` string; if it drifts vs VERSION,
#    `vyk --version` reports stale data. Same-version
#    `version-bump.sh "$(cat VERSION)"` is the documented
#    "regenerate without bumping" path.
cat > src/version_str.cyr <<EOF
# src/version_str.cyr — AUTO-GENERATED from \`VERSION\` by
# \`scripts/version-bump.sh\`. Do NOT edit by hand; the next bump
# will overwrite. To regenerate without bumping, run:
#
#   sh scripts/version-bump.sh "\$(cat VERSION)"
#
# Why this file exists: through 1.0.3 the \`vyk --version\` literal
# lived as \`var VYK_VERSION = "vyk X.Y.Z"\` in \`src/main.cyr\`. The
# 1.0.2 → 1.0.3 cut nearly shipped with \`vyk --version\` still
# saying 1.0.2 because the CLI literal was a fourth file outside
# the version-sync checklist (VERSION / cyrius.cyml package /
# CHANGELOG header). Centralising the string here means
# version-bump.sh writes ONE file every time and \`src/main.cyr\`
# just references the var. No regex hunting; no drift; no
# fourth-file gotcha. cyrius and cyim use the same pattern.

var VYK_VERSION = "vyk $NEW";
EOF

if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD (regenerated src/version_str.cyr)"
    exit 0
fi

# 2. VERSION file (source of truth). cyrius.cyml resolves
#    \${file:VERSION} for the package version, so it doesn't need
#    its own touch.
echo "$NEW" > VERSION

# 3. CHANGELOG.md — insert new version header after [Unreleased].
#    Anchored regex matches ONLY the literal "## [Unreleased]"
#    header line.
if ! grep -q "## \[$NEW\]" CHANGELOG.md 2>/dev/null; then
    sed -i "/^## \[Unreleased\]$/a\\
\\
## [$NEW] — $(date +%Y-%m-%d)" CHANGELOG.md 2>/dev/null || true
fi

echo "$OLD -> $NEW"
echo ""
echo "Updated:"
echo "  VERSION"
echo "  src/version_str.cyr (regenerated)"
echo "  CHANGELOG.md (new header inserted)"
echo ""
echo "Still manual:"
echo "  - CHANGELOG.md body (Added / Changed / Fixed / Security)"
echo "  - docs/development/state.md current-status block if state shifted"
echo "  - cyrius toolchain pin in cyrius.cyml [package].cyrius"
echo "    (separate from vyakarana's own version)"
echo "  - dist/vyakarana.cyr — run \`cyrius distlib\` to regenerate"
