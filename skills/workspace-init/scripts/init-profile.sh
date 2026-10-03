#!/usr/bin/env bash
# workspace-init profile manager v3
# 支援: 多 agent (claude-code / opencode / other)、多 project、Git 整合、Tone 設定、Profile 匯出/匯入、Skill 推薦
#
# Agent 解析優先級:
#   1. --agent <name> CLI flag
#   2. HKINIT_AGENT environment variable
#   3. heuristic (只有 opencode 裝咗 → opencode，否則 claude-code)

set -euo pipefail

# --- Agent 定義 ---
# 每個 agent 有自己嘅 config dir（global profile + multi-project profiles）
# 同 local dir（project profile，跟 repo 走）。未知 agent 用 neutral 路徑。
SUPPORTED_AGENTS=(claude-code opencode)

agent_config_dir() {
  case "${1:-claude-code}" in
    claude-code) echo "$HOME/.config/claude" ;;
    opencode)    echo "$HOME/.config/opencode" ;;
    *)           echo "$HOME/.config/workspace-init" ;;
  esac
}

agent_local_dir() {
  case "${1:-claude-code}" in
    claude-code) echo ".claude" ;;
    opencode)    echo ".opencode" ;;
    *)           echo ".workspace-init" ;;
  esac
}

# Skill 自己所在目錄（由 script 位置推斷，任何 agent 安裝路徑都 work）
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Active agent ---
ACTIVE_AGENT=""

resolve_agent() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return
  fi
  if [[ -n "${HKINIT_AGENT:-}" ]]; then
    echo "$HKINIT_AGENT"
    return
  fi
  # heuristic: 只裝咗 opencode → opencode；否則預設 claude-code（兼容舊版本用戶）
  if [[ -d "$HOME/.config/opencode" && ! -d "$HOME/.claude" ]]; then
    echo "opencode"
  else
    echo "claude-code"
  fi
}

# 讀取順序：active agent 優先，其次所有 known agents（dedupe）
ordered_agents() {
  local a
  printf '%s\n' "$ACTIVE_AGENT"
  for a in "${SUPPORTED_AGENTS[@]}"; do
    if [[ "$a" != "$ACTIVE_AGENT" ]]; then
      printf '%s\n' "$a"
    fi
  done
}

# --- Profile paths（per agent）---
global_profile_path() {
  echo "$(agent_config_dir "${1:-claude-code}")/workspace-init-profile.json"
}

multi_profile_dir() {
  echo "$(agent_config_dir "${1:-claude-code}")/workspace-profiles"
}

local_project_profile_path() {
  echo "${1:-$(pwd)}/$(agent_local_dir "${2:-claude-code}")/project-profile.json"
}

# 16 位 hash（macOS 冇 md5sum，用 md5；Linux 用 md5sum）
portable_md5_16() {
  local s="$1"
  if command -v md5sum >/dev/null 2>&1; then
    echo "$s" | md5sum | head -c 16
  elif command -v md5 >/dev/null 2>&1; then
    echo "$s" | md5 | head -c 16
  else
    echo "nohash"
  fi
}

project_profile_path() {
  local dir="${1:-$(pwd)}" agent="${2:-claude-code}" key
  key=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")
  key=$(portable_md5_16 "$key")
  echo "$(multi_profile_dir "$agent")/$key.json"
}

# --- Profile lookup（讀取時 union 所有 agent 位置，active 優先；切換 agent 唔會丢 profile）---
find_project_profile() {
  local dir="${1:-$(pwd)}" a p
  # 1. local project profile（跟 repo 走）
  while IFS= read -r a; do
    p=$(local_project_profile_path "$dir" "$a")
    if [[ -f "$p" ]]; then
      cat "$p"
      return 0
    fi
  done < <(ordered_agents)
  # 2. multi-project profile（git root hash）
  while IFS= read -r a; do
    p=$(project_profile_path "$dir" "$a")
    if [[ -f "$p" ]]; then
      cat "$p"
      return 0
    fi
  done < <(ordered_agents)
  return 1
}

get_profile() {
  local a p
  while IFS= read -r a; do
    p=$(global_profile_path "$a")
    if [[ -f "$p" ]]; then
      cat "$p"
      return 0
    fi
  done < <(ordered_agents)
  return 1
}

# --- Save local profile（auto-merge global）---
save_local_project_profile() {
  local dir="$1" json="$2" target_path global
  target_path=$(local_project_profile_path "$dir" "$ACTIVE_AGENT")
  if global=$(get_profile); then
    json=$(jq -n \
      --argjson given "$json" \
      --argjson global "$global" \
      --arg a "$ACTIVE_AGENT" \
      '{
        agent: ($given.agent // $global.agent // $a),
        user_name: ($given.user_name // $global.user_name // ""),
        company: ($given.company // $global.company // ""),
        project: ($given.project // ""),
        language: ($given.language // $global.language // ""),
        preferred_form: ($given.preferred_form // $global.preferred_form // ""),
        tone: ($given.tone // $global.tone // "casual"),
        project_details: ($given.project_details // $given.project // ""),
        extra_skills: ($given.extra_skills // $global.extra_skills // {})
      }')
  else
    json=$(echo "$json" | jq --arg a "$ACTIVE_AGENT" '.agent = (.agent // $a)')
  fi
  mkdir -p "$(dirname "$target_path")"
  echo "$json" | jq '.' > "$target_path"
  chmod 600 "$target_path"
  echo "✓ Project profile saved: $target_path (agent: $ACTIVE_AGENT)"
}

# --- Save global profile（只儲 basic info，跟 agent 位置）---
save_profile() {
  local name="$1" company="$2" lang="$3" form="$4" tone="${5:-casual}" dir="${6:-$(pwd)}"
  local target_path
  target_path=$(global_profile_path "$ACTIVE_AGENT")
  mkdir -p "$(dirname "$target_path")"
  jq -n \
    --arg a "$ACTIVE_AGENT" \
    --arg name "$name" \
    --arg company "$company" \
    --arg lang "$lang" \
    --arg form "$form" \
    --arg tone "$tone" \
    '{
      agent: $a,
      user_name: $name,
      company: $company,
      language: $lang,
      preferred_form: $form,
      tone: $tone
    }' > "$target_path"
  chmod 600 "$target_path"
  echo "✓ Global profile saved: $target_path (agent: $ACTIVE_AGENT)"
}

# --- Set 單一欄位（更新到現有 profile：local > multi > global；冇就建立 global）---
set_profile_field() {
  local key="$1" value="$2" dir="${3:-$(pwd)}" a p
  local existing="" path=""
  while IFS= read -r a; do
    p=$(local_project_profile_path "$dir" "$a")
    if [[ -f "$p" ]]; then existing=$(cat "$p"); path="$p"; break; fi
  done < <(ordered_agents)
  if [[ -z "$path" ]]; then
    while IFS= read -r a; do
      p=$(project_profile_path "$dir" "$a")
      if [[ -f "$p" ]]; then existing=$(cat "$p"); path="$p"; break; fi
    done < <(ordered_agents)
  fi
  if [[ -z "$path" ]]; then
    while IFS= read -r a; do
      p=$(global_profile_path "$a")
      if [[ -f "$p" ]]; then existing=$(cat "$p"); path="$p"; break; fi
    done < <(ordered_agents)
  fi
  if [[ -z "$path" ]]; then
    path=$(global_profile_path "$ACTIVE_AGENT")
    existing="{}"
  fi
  mkdir -p "$(dirname "$path")"
  echo "$existing" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}' > "$path"
  chmod 600 "$path"
  echo "✓ $key = $value (saved to $path, agent: $ACTIVE_AGENT)"
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

# --- Export（active agent 嘅 global + 所有 agents 嘅 multi-project profiles）---
export_profile() {
  local out_file="${1:-workspace-init-profile-export.json}" a f k
  local export_obj main_profile
  if main_profile=$(get_profile); then
    export_obj="$main_profile"
  else
    echo "❌ 冇 profile 可以匯出" && return 1
  fi
  local projects_json="{}" seen=""
  while IFS= read -r a; do
    local d; d=$(multi_profile_dir "$a")
    if [[ -d "$d" ]]; then
      for f in "$d"/*.json; do
        if [[ ! -f "$f" ]]; then continue; fi
        k=$(basename "$f" .json)
        if [[ "$seen" == *" $k "* ]]; then continue; fi
        seen="$seen $k "
        projects_json=$(echo "$projects_json" | jq --arg k "$k" --argjson v "$(cat "$f")" '. + {($k): $v}')
      done
    fi
  done < <(ordered_agents)
  export_obj=$(echo "$export_obj" | jq --argjson p "$projects_json" '. + {projects: $p}')
  echo "$export_obj" | jq '.' > "$out_file"
  echo "✓ Profile 已匯出到: $out_file (agent: $ACTIVE_AGENT)"
}

# --- Import（匯入去 active agent 位置）---
import_profile() {
  local in_file="${1:-}"
  if [[ -z "$in_file" || ! -f "$in_file" ]]; then
    echo "❌ 檔案唔存在: $in_file"
    return 1
  fi
  local data global_path
  data=$(cat "$in_file")
  global_path=$(global_profile_path "$ACTIVE_AGENT")
  mkdir -p "$(dirname "$global_path")"
  if ! echo "$data" | jq 'del(.projects)' > "$global_path" 2>/dev/null; then
    echo "❌ 無效嘅 JSON 格式"
    return 1
  fi
  chmod 600 "$global_path"
  local projects
  projects=$(echo "$data" | jq -r '.projects // empty' 2>/dev/null || true)
  if [[ -n "$projects" && "$projects" != "null" ]]; then
    mkdir -p "$(multi_profile_dir "$ACTIVE_AGENT")"
    echo "$projects" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | while IFS=$'\t' read -r key json_str; do
      echo "$json_str" | jq '.' > "$(multi_profile_dir "$ACTIVE_AGENT")/$key.json"
      chmod 600 "$(multi_profile_dir "$ACTIVE_AGENT")/$key.json"
    done
    echo "✓ 已匯入 $(echo "$projects" | jq 'length') 個 project profiles"
  fi
  echo "✓ Profile 已匯入 (agent: $ACTIVE_AGENT)"
}

# --- Reset（只清 active agent 嘅 config 位置；local profile 跟 repo 走，唔删）---
reset_profile() {
  rm -f "$(global_profile_path "$ACTIVE_AGENT")"
  rm -rf "$(multi_profile_dir "$ACTIVE_AGENT")"
  echo "✓ Profile reset (agent: $ACTIVE_AGENT)"
  echo "  備註: local project profiles（.claude/ .opencode/ 等）未刪除"
}

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

# --- Init context ---
init_context() {
  local dir="${1:-$(pwd)}" profile_data="null" project_profile="null"
  project_profile=$(find_project_profile "$dir") && profile_data="$project_profile"

  local git_data tone tone_guide
  git_data=$(detect_git_context "$dir")

  if [[ "$profile_data" = "null" ]]; then
    # 無 project profile → 試 global（union）
    if profile_data=$(get_profile); then
      tone=$(echo "$profile_data" | jq -r '.tone // "casual"')
      tone_guide=$(get_tone_guide "$tone")
      cat <<JSON
{
  "status": "use_global",
  "agent": "$ACTIVE_AGENT",
  "message": "已用 global profile 嘅基本資料。請提供呢個 project 嘅名同描述，用 --save-local 建立 local profile。",
  "profile": $profile_data,
  "git": $git_data,
  "tone_guide": "$tone_guide"
}
JSON
      return 0
    fi
    # 完全冇 profile → 首次使用
    cat <<JSON
{
  "status": "no_profile",
  "agent": "$ACTIVE_AGENT",
  "message": "首次使用。請同用戶確認佢用緊邊個 agent（claude-code / opencode / other，目前偵測到 $ACTIVE_AGENT），然後跟首次使用流程收集資料，用 --agent <agent> 儲存。"
}
JSON
    return 0
  fi

  tone=$(echo "$profile_data" | jq -r '.tone // "casual"')
  tone_guide=$(get_tone_guide "$tone")
  cat <<CTX
{
  "status": "ok",
  "agent": "$ACTIVE_AGENT",
  "profile": $profile_data,
  "git": $git_data,
  "project_profile": $project_profile,
  "tone_guide": "$tone_guide"
}
CTX
}

# --- Main ---
main() {
  local agent_arg="" a
  local args=()

  # 抽出 --agent（可以放喺任何位置）
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        if [[ $# -lt 2 ]]; then
          echo "❌ --agent 需要 value（claude-code / opencode / other）"
          exit 1
        fi
        agent_arg="$2"
        shift 2
        ;;
      --agent=*)
        agent_arg="${1#*=}"
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  ACTIVE_AGENT=$(resolve_agent "$agent_arg")
  mkdir -p "$(agent_config_dir "$ACTIVE_AGENT")"

  local cmd="${args[0]:-}"
  case "$cmd" in
    --get) get_profile ;;
    --save) save_profile "${args[1]:-}" "${args[2]:-}" "${args[3]:-}" "${args[4]:-}" "${args[5]:-casual}" "${args[6]:-}" ;;
    --set) set_profile_field "${args[1]:-}" "${args[2]:-}" "${args[3]:-}" ;;
    --reset) reset_profile ;;
    --check)
      if find_project_profile "${args[1]:-$(pwd)}" >/dev/null 2>&1 || get_profile >/dev/null 2>&1; then
        echo "EXISTS"
      else
        echo "NOT_FOUND"
      fi
      ;;
    --ctx) init_context "${args[1]:-$(pwd)}" ;;
    --git) detect_git_context "${args[1]:-$(pwd)}" ;;
    --tone) get_tone_guide "${args[1]:-casual}" ;;
    --recommend) recommend_skills "${args[1]:-unknown}" "${args[2]:-unknown}" ;;
    --export) export_profile "${args[1]:-}" ;;
    --import) import_profile "${args[1]:-}" ;;
    --list-projects)
      local found_any=0 f k
      local d seen=""
      echo "已儲存嘅 projects:"
      while IFS= read -r a; do
        d=$(multi_profile_dir "$a")
        if [[ -d "$d" ]]; then
          for f in "$d"/*.json; do
            if [[ ! -f "$f" ]]; then continue; fi
            k=$(basename "$f" .json)
            if [[ "$seen" == *" $k "* ]]; then continue; fi
            seen="$seen $k "
            found_any=1
            echo "  • $(jq -r '.project // "unknown"' "$f" 2>/dev/null || echo "unknown") ($(basename "$f" .json)) [agent: $a]"
          done
        fi
      done < <(ordered_agents)
      if [[ "$found_any" == "0" ]]; then
        echo "  （冇）"
      fi
      ;;
    --agent-list)
      echo "支援嘅 agents:"
      echo "  claude-code  → ~/.config/claude/ + .claude/"
      echo "  opencode     → ~/.config/opencode/ + .opencode/"
      echo "  (其他)       → ~/.config/workspace-init/ + .workspace-init/ (neutral)"
      echo "目前 active: $ACTIVE_AGENT"
      ;;
    --update) bash "$SKILL_DIR/scripts/update.sh" ;;
    --save-project)
      local dir="${args[1]:-$(pwd)}" json="${args[2]:-}"
      if [[ -z "$json" ]]; then
        echo "❌ 需要 JSON data"
        exit 1
      fi
      local target
      target=$(project_profile_path "$dir" "$ACTIVE_AGENT")
      mkdir -p "$(dirname "$target")"
      echo "$json" | jq --arg a "$ACTIVE_AGENT" '.agent = (.agent // $a)' | jq '.' > "$target"
      chmod 600 "$target"
      echo "✓ Project profile saved: $target (agent: $ACTIVE_AGENT)"
      ;;
    --save-local|--sl)
      local dir="${args[1]:-$(pwd)}" json="${args[2]:-}"
      if [[ -z "$json" ]]; then
        echo "❌ 需要 JSON data"
        exit 1
      fi
      save_local_project_profile "$dir" "$json"
      ;;
    *)
      echo "workspace-init profile manager v3"
      echo "用法: init-profile.sh [--agent <agent>] <command> [args...]"
      echo ""
      echo "Agents: claude-code / opencode / 其他（neutral 路徑）"
      echo "亦可用 HKINIT_AGENT env var 代替 --agent"
      echo ""
      echo "Commands:"
      echo "  --get                       讀取 global profile"
      echo "  --save <name> <company> <lang> <form> <tone> [dir]  儲存 global profile（basic info）"
      echo "  --set <key> <value> [dir]   設定單一欄位（local > multi > global）"
      echo "  --reset                     重置 active agent 嘅 profile"
      echo "  --check [dir]               檢查有冇 profile"
      echo "  --ctx [dir]                 完整 context（含 git + multi-project + agent）"
      echo "  --git [dir]                 Git 偵測"
      echo "  --tone [tone]               Tone 指南（casual/formal/technical/friendly/minimal）"
      echo "  --recommend <lang> <branch> Skill 推薦"
      echo "  --export [file]             匯出 profile"
      echo "  --import <file>             匯入 profile"
      echo "  --list-projects             列出所有 project profiles"
      echo "  --save-project <dir> <json> 儲存 project-specific profile（config dir）"
      echo "  --save-local|--sl <dir> <json> 儲存 local project profile（跟 repo，自動 merge global）"
      echo "  --agent-list                列出支援嘅 agents"
      echo "  --update                    自動更新 workspace-init 到最新版"
      ;;
  esac
}

main "$@"
