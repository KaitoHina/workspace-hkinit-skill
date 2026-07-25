#!/usr/bin/env bash
# workspace-init profile manager v2
# 支援: 多 project、Git 整合、Tone 設定、Profile 匯出/匯入、Skill 推薦

set -euo pipefail

CONFIG_DIR="$HOME/.config/claude"
SKILL_DIR="$HOME/.claude/skills/workspace-init"
GLOBAL_PROFILE="$CONFIG_DIR/workspace-init-profile.json"
MULTI_PROFILE_DIR="$CONFIG_DIR/workspace-profiles"

# --- Git detection ---
detect_git_context() {
  local dir="${1:-$(pwd)}"
  local git_root branch language file_count
  git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || { echo '{"in_git":false}'; return; }
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  file_count=$(git -C "$dir" ls-files 2>/dev/null | wc -l | tr -d ' ')
  language=$(detect_project_lang "$git_root")
  cat <<JSON
{
  "in_git": true,
  "root": "$git_root",
  "branch": "$branch",
  "language": "$language",
  "files": $file_count
}
JSON
}

detect_project_lang() {
  local root="$1"
  [[ -f "$root/package.json" ]] && echo "JavaScript/TypeScript" && return
  [[ -f "$root/Cargo.toml" ]] && echo "Rust" && return
  [[ -f "$root/go.mod" ]] && echo "Go" && return
  [[ -f "$root/pyproject.toml" || -f "$root/requirements.txt" ]] && echo "Python" && return
  [[ -f "$root/Gemfile" ]] && echo "Ruby" && return
  [[ -f "$root/CMakeLists.txt" ]] && echo "C/C++" && return
  [[ -f "$root/Package.swift" ]] && echo "Swift" && return
  [[ -f "$root/composer.json" ]] && echo "PHP" && return
  [[ -f "$root/Makefile" ]] && echo "Makefile" && return
  echo "unknown"
}

# --- Profile paths ---
local_project_profile_path() { echo "${1:-$(pwd)}/.claude/project-profile.json"; }

project_profile_path() {
  local dir="${1:-$(pwd)}"
  local key
  key=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")
  key=$(echo "$key" | md5sum 2>/dev/null | head -c 16 || echo "default")
  echo "$MULTI_PROFILE_DIR/$key.json"
}

# --- Profile lookup (priority: local > multi-project > global) ---
find_project_profile() {
  local dir="${1:-$(pwd)}" profile_path
  profile_path=$(local_project_profile_path "$dir")
  [[ -f "$profile_path" ]] && cat "$profile_path" && return 0
  profile_path=$(project_profile_path "$dir")
  [[ -f "$profile_path" ]] && cat "$profile_path" && return 0
  return 1
}

# --- Save local profile (auto-merge global) ---
save_local_project_profile() {
  local dir="$1" json="$2" target_path
  target_path=$(local_project_profile_path "$dir")
  if [[ -f "$GLOBAL_PROFILE" ]]; then
    json=$(jq -n \
      --argjson given "$json" \
      --argjson global "$(cat "$GLOBAL_PROFILE")" \
      '{
        user_name: ($given.user_name // $global.user_name // ""),
        company: ($given.company // $global.company // ""),
        project: ($given.project // ""),
        language: ($given.language // $global.language // ""),
        preferred_form: ($given.preferred_form // $global.preferred_form // ""),
        tone: ($given.tone // $global.tone // "casual"),
        project_details: ($given.project_details // $given.project // ""),
        extra_skills: ($given.extra_skills // $global.extra_skills // {})
      }')
  fi
  mkdir -p "$(dirname "$target_path")"
  echo "$json" | jq '.' > "$target_path"
  chmod 600 "$target_path"
  echo "✓ Project profile saved: $target_path"
}

# --- Tone ---
get_tone_guide() {
  local tone="${1//$'\r'/}"
  case "$tone" in
    casual) echo "用輕鬆自然嘅語氣，可以加下 slang，唔使太 formal" ;;
    formal) echo "用正式書面語，避免 slang，structure 清晰" ;;
    technical) echo "用技術性語言，精準、直接，可以多啲 spec 同數據" ;;
    friendly) echo "用 friendly 嘅語氣，好似同朋友傾偈咁，可以 emoji" ;;
    minimal) echo "只講重點，最短回覆，唔廢話" ;;
    *) echo "$tone" ;;
  esac
}

# --- Skill recommendations ---
recommend_skills() {
  local lang="${1:-unknown}" branch="${2:-unknown}" result=""
  case "$lang" in
    "JavaScript/TypeScript")
      result="  - ponytail (懶人開發模式，少 code)\n"
      result+="  - impeccable (UI 設計檢測)\n"
      result+="  - engineering-advanced-skills:dependency-auditor (依賴審計)\n"
      result+="  - engineering-advanced-skills:performance-profiler (效能分析)\n"
      ;;
    "Rust")
      result+="  - engineering-advanced-skills:ci-cd-pipeline-builder (CI/CD)\n"
      result+="  - engineering-advanced-skills:dependency-auditor (依賴審計)\n"
      result+="  - ponytail (懶人模式)\n"
      ;;
    "Python")
      result+="  - engineering-advanced-skills:rag-architect (RAG 架構)\n"
      result+="  - engineering-advanced-skills:database-designer (數據庫設計)\n"
      result+="  - ponytail (懶人模式)\n"
      ;;
    "Go")
      result+="  - engineering-advanced-skills:performance-profiler (效能)\n"
      result+="  - engineering-advanced-skills:ci-cd-pipeline-builder (CI/CD)\n"
      ;;
    *)
      result+="  - ponytail (懶人模式，通用)\n"
      result+="  - graphify (codebase 架構理解)\n"
      result+="  - review (code review)\n"
      ;;
  esac
  case "$branch" in
    main|master) result+="  - engineering-advanced-skills:changelog-generator (release notes)\n" ;;
    feat/*|feature/*) result+="  - engineering-advanced-skills:pr-review-expert (PR review)\n" ;;
    fix/*|hotfix/*) result+="  - engineering-advanced-skills:focused-fix (集中修 bug)\n" ;;
  esac
  echo -e "$result"
}

# --- Export ---
export_profile() {
  local out_file="${1:-workspace-init-profile-export.json}"
  [[ ! -f "$GLOBAL_PROFILE" ]] && echo "❌ 冇 profile 可以匯出" && return 1
  local export_obj
  export_obj=$(cat "$GLOBAL_PROFILE")
  if [[ -d "$MULTI_PROFILE_DIR" ]]; then
    local projects_json="{}"
    for f in "$MULTI_PROFILE_DIR"/*.json; do
      [[ -f "$f" ]] || continue
      local key content
      key=$(basename "$f" .json)
      content=$(cat "$f")
      projects_json=$(echo "$projects_json" | jq --arg k "$key" --argjson v "$content" '. + {($k): $v}')
    done
    export_obj=$(echo "$export_obj" | jq --argjson p "$projects_json" '. + {projects: $p}')
  fi
  echo "$export_obj" > "$out_file"
  echo "✓ Profile 已匯出到: $out_file"
}

# --- Import ---
import_profile() {
  local in_file="${1:-}"
  [[ -z "$in_file" || ! -f "$in_file" ]] && echo "❌ 檔案唔存在: $in_file" && return 1
  local data
  data=$(cat "$in_file")
  echo "$data" | jq 'del(.projects)' > "$GLOBAL_PROFILE" 2>/dev/null || { echo "❌ 無效嘅 JSON 格式"; return 1; }
  chmod 600 "$GLOBAL_PROFILE"
  local projects
  projects=$(echo "$data" | jq -r '.projects // empty' 2>/dev/null)
  [[ -n "$projects" && "$projects" != "null" ]] && {
    mkdir -p "$MULTI_PROFILE_DIR"
    echo "$projects" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key json_str; do
      echo "$json_str" > "$MULTI_PROFILE_DIR/$key.json"
      chmod 600 "$MULTI_PROFILE_DIR/$key.json"
    done
    echo "✓ 已匯入 $(echo "$projects" | jq 'length') 個 project profiles"
  }
  echo "✓ Profile 已匯入"
}

# --- Get profile ---
get_profile() {
  [[ -f "$GLOBAL_PROFILE" ]] && cat "$GLOBAL_PROFILE" || return 1
}

# --- Save profile (priority: local > multi-project > global) ---
save_profile() {
  local name="$1" company="$2" project="$3" lang="$4" form="$5" details="$6" tone="${7:-casual}" dir="${8:-$(pwd)}"
  local target_path
  target_path=$(local_project_profile_path "$dir")
  [[ ! -f "$target_path" ]] && target_path=$(project_profile_path "$dir")

  if [[ "$target_path" = "$GLOBAL_PROFILE" || ! -f "$target_path" ]]; then
    # Save to global: skip project fields
    target_path="$GLOBAL_PROFILE"
    mkdir -p "$(dirname "$target_path")"
    jq -n \
      --arg name "$name" \
      --arg company "$company" \
      --arg lang "$lang" \
      --arg form "$form" \
      --arg tone "$tone" \
      '{
        user_name: $name,
        company: $company,
        language: $lang,
        preferred_form: $form,
        tone: $tone
      }' > "$target_path"
  else
    # Save to local: include project fields
    mkdir -p "$(dirname "$target_path")"
    jq -n \
      --arg name "$name" \
      --arg company "$company" \
      --arg project "$project" \
      --arg lang "$lang" \
      --arg form "$form" \
      --arg details "$details" \
      --arg tone "$tone" \
      '{
        user_name: $name,
        company: $company,
        project: $project,
        language: $lang,
        preferred_form: $form,
        tone: $tone,
        project_details: $details
      }' > "$target_path"
  fi
  chmod 600 "$target_path"
  echo "✓ Profile saved: $target_path"
}

# --- Reset ---
reset_profile() { rm -f "$GLOBAL_PROFILE"; echo "✓ Profile reset"; }

# --- Init context ---
init_context() {
  local dir="${1:-$(pwd)}" profile_data="null" project_profile
  project_profile=$(find_project_profile "$dir") && profile_data="$project_profile"

  # Case: no local profile but global exists → suggest creating local
  if [[ "$profile_data" = "null" && -f "$GLOBAL_PROFILE" ]]; then
    profile_data=$(cat "$GLOBAL_PROFILE")
    cat <<JSON
{
  "status": "use_global",
  "message": "已用 global profile 嘅基本資料。請提供呢個 project 嘅名同描述，用 --save-local 建立 local profile。",
  "profile": $profile_data,
  "git": $(detect_git_context "$dir"),
  "tone_guide": "$(get_tone_guide "$(echo "$profile_data" | jq -r '.tone // "casual"')")"
}
JSON
    return 0
  fi

  [[ "$profile_data" = "null" ]] && echo '{"status":"no_profile"}' && return 0
  local git_data tone tone_guide
  git_data=$(detect_git_context "$dir")
  tone=$(echo "$profile_data" | jq -r '.tone // "casual"')
  tone_guide=$(get_tone_guide "$tone")
  cat <<CTX
{
  "status": "ok",
  "profile": $profile_data,
  "git": $git_data,
  "project_profile": $project_profile,
  "tone_guide": "$tone_guide"
}
CTX
}

# --- Main ---
main() {
  local cmd="${1:-}"
  mkdir -p "$CONFIG_DIR"
  case "$cmd" in
    --get) get_profile ;;
    --save) save_profile "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-casual}" "${9:-}" ;;
    --reset) reset_profile ;;
    --check) [[ -f "$(local_project_profile_path "${2:-$(pwd)}")" ]] && echo "EXISTS" || echo "NOT_FOUND" ;;
    --ctx) init_context "${2:-$(pwd)}" ;;
    --git) detect_git_context "${2:-$(pwd)}" ;;
    --tone) get_tone_guide "${2:-casual}" ;;
    --recommend) recommend_skills "${2:-unknown}" "${3:-unknown}" ;;
    --export) export_profile "${2:-}" ;;
    --import) import_profile "${2:-}" ;;
    --list-projects)
      echo "已儲存嘅 projects:"
      [[ ! -d "$MULTI_PROFILE_DIR" ]] && echo "  （冇）" && return
      for f in "$MULTI_PROFILE_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        echo "  • $(jq -r '.project // "unknown"' "$f" 2>/dev/null || echo "unknown") ($(basename "$f" .json))"
      done
      ;;
    --update) bash "$SKILL_DIR/scripts/update.sh" ;;
    --save-project)
      local dir="${2:-$(pwd)}" json="${3:-}"
      [[ -z "$json" ]] && { echo "❌ 需要 JSON data"; exit 1; }
      mkdir -p "$MULTI_PROFILE_DIR"
      echo "$json" > "$(project_profile_path "$dir")"
      chmod 600 "$(project_profile_path "$dir")"
      echo "✓ Project profile saved"
      ;;
    --save-local|--sl)
      local dir="${2:-$(pwd)}" json="${3:-}"
      [[ -z "$json" ]] && { echo "❌ 需要 JSON data"; exit 1; }
      save_local_project_profile "$dir" "$json"
      ;;
    *)
      echo "workspace-init profile manager v2"
      echo "用法:"
      echo "  --get                       讀取 profile"
      echo "  --save <name> <company> <project> <lang> <form> <details> [tone]  儲存"
      echo "  --reset                     重置"
      echo "  --check                     檢查是否存在"
      echo "  --ctx [dir]                 完整 context（含 git + multi-project）"
      echo "  --git [dir]                 Git 偵測"
      echo "  --tone [tone]               Tone 指南（casual/formal/technical/friendly/minimal）"
      echo "  --recommend <lang> <branch> Skill 推薦"
      echo "  --export [file]             匯出 profile"
      echo "  --import <file>             匯入 profile"
      echo "  --list-projects             列出所有 project profiles"
      echo "  --save-project <dir> <json> 儲存 project-specific profile（~/.config/claude/）"
      echo "  --save-local|--sl <dir> <json> 儲存 project profile 喺 .claude/ 入面（自動 merge global profile）"
      echo "  --update                    自動更新 workspace-init 到最新版"
      ;;
  esac
}

main "$@"