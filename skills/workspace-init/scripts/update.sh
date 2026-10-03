#!/usr/bin/env bash
# workspace-init auto-updater
# Usage: curl -sL https://raw.githubusercontent.com/KaitoHina/workspace-hkinit-skill/main/skills/workspace-init/scripts/update.sh | bash
set -euo pipefail

REPO="https://github.com/KaitoHina/workspace-hkinit-skill"
TMP="/tmp/hkinit-update"

# 所有已知安裝位置（自動更新所有已安裝嘅 copy）
KNOWN_SKILL_DIRS=(
  "$HOME/.claude/skills/workspace-init"            # Claude Code
  "$HOME/.config/opencode/skills/workspace-init"   # OpenCode
)

echo "📦 workspace-init updater"
echo "   Source: $REPO"
echo ""

# 1. 搵出已安裝位置
INSTALLED=()
for d in "${KNOWN_SKILL_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    INSTALLED+=("$d")
  fi
done

if [[ ${#INSTALLED[@]} -eq 0 ]]; then
  echo "❌ workspace-init 未安裝。請先用 README 嘅安裝方法："
  echo "   Claude Code:"
  echo "     cp -r <repo>/skills/workspace-init ~/.claude/skills/"
  echo "   OpenCode:"
  echo "     mkdir -p ~/.config/opencode/skills"
  echo "     cp -r <repo>/skills/workspace-init ~/.config/opencode/skills/"
  exit 1
fi

for d in "${INSTALLED[@]}"; do
  echo "   Target: $d"
done

# 2. 記錄當前版本（如果有的話）
if [[ -f "${INSTALLED[0]}/version.txt" ]]; then
  OLD_VER=$(cat "${INSTALLED[0]}/version.txt")
  echo "   Current version: $OLD_VER"
else
  echo "   Current version: unknown (pre-v2.1)"
fi

# 3. Clone 最新版本
echo ""
echo "⬇️  Downloading latest..."
rm -rf "$TMP"
git clone --depth 1 "$REPO" "$TMP" 2>/dev/null || {
  # fallback: curl 如果 git 唔 work
  rm -rf "$TMP"
  mkdir -p "$TMP"
  curl -sL -o /tmp/hkinit-update.zip "$REPO/archive/refs/heads/main.zip"
  unzip -q /tmp/hkinit-update.zip -d "$TMP" 2>/dev/null
}

if [[ ! -d "$TMP/skills/workspace-init" ]]; then
  echo "❌ 下載失敗，搵唔到 skills/workspace-init"
  rm -rf "$TMP"
  exit 1
fi

# 4. 更新每個安裝位置
for d in "${INSTALLED[@]}"; do
  cp -r "$TMP/skills/workspace-init"/* "$d/"
  chmod +x "$d/scripts/init-profile.sh" 2>/dev/null || true
  chmod +x "$d/scripts/update.sh" 2>/dev/null || true
done

# 5. 記錄版本
if [[ -f "$TMP/skills/workspace-init/version.txt" ]]; then
  NEW_VER=$(cat "$TMP/skills/workspace-init/version.txt")
  for d in "${INSTALLED[@]}"; do
    echo "$NEW_VER" > "$d/version.txt"
  done
  echo "   New version: $NEW_VER"
fi

# 6. Cleanup
rm -rf "$TMP"

echo ""
echo "✅ workspace-init updated!"
echo "   Run /init in a new conversation to load the latest."
