---
name: workspace-init
description: "每次對話開始時注入 workspace 背景、用戶偏好、語言設定、project context，提高 cache hit rate 同個人化體驗。第一次用會問你嘅名同公司，然後記住。支援 Claude Code、OpenCode 同其他 agent。"
---

# workspace-init

每次對話開始時自動注入 workspace 背景資訊，或者手動用 `/init`（或者「init workspace」）呼叫。

**重要：所有 storage 操作都要經 `init-profile.sh`，唔好直接 read/write JSON files。**

## Agent 識別（重要）

呢個 skill 支援多個 agent。**每次 call script，先確認你自己係邊個 agent，然後加 `--agent`：**

| 你嘅 agent | `--agent` 值 | skill 目錄 | local profile 位置 |
|-----------|--------------|-----------|-------------------|
| Claude Code | `claude-code` | `~/.claude/skills/workspace-init` | `.claude/` |
| OpenCode | `opencode` | `~/.config/opencode/skills/workspace-init` | `.opencode/` |
| 其他（Codex/Aider/Gemini CLI 等） | `other` | （任意位置） | `.workspace-init/` |

> 唔加 `--agent` 都會自動偵測（預設 claude-code；如果只裝咗 OpenCode 會推斷 opencode），但**首次使用時要同用戶確認**佢用緊邊個 agent。
> 亦可以用 `HKINIT_AGENT=opencode bash ...` env var 代替 `--agent`。

呼叫格式：

```bash
bash <skill_dir>/scripts/init-profile.sh --agent <agent> <flag>
```

## 用法

| 指令 | 執行 | 功能 |
|------|------|------|
| `/init` | `--ctx [pwd]` | 重新注入 workspace context（自動 detect Git + 推薦 skills） |
| `/init --full` | 同上 | 完整版（含 quota check + memory 狀態） |
| `/init --reset` | `--reset` | 重置 active agent 所有已儲存嘅資料 |
| `/init --lang <lang>` | `--set language <lang>` | 直接切換語言，唔使重置 |
| `/init --tone <tone>` | `--set tone <tone>` | 設定 tone（casual/formal/technical/friendly/minimal） |
| `/init --export [file]` | `--export [file]` | 匯出 profile 做 JSON |
| `/init --import <file>` | `--import <file>` | 匯入 profile |
| `/init --list-projects` | `--list-projects` | 列出所有已儲存嘅 project profiles |
| `/init --save-project <dir> <json>` | `--save-project <dir> '<json>'` | 儲存 project-specific profile（config dir） |
| `/init --save-local|--sl <dir> <json>` | `--save-local <dir> '<json>'` | 儲存 local project profile（跟 repo，自動 merge global） |
| `/init --save <name> <company> <lang> <form> <tone>` | 同上 | 建立 global profile（只儲 basic info） |
| `/init --agent-list` | `--agent-list` | 列出支援嘅 agents |
| `/init --update` | `--update` | 自動更新 workspace-init 到最新版 |

## 首次使用流程

當 `--ctx` output `"status": "no_profile"` 時（首次使用），問用戶：

0. **你用緊邊個 agent？**（Claude Code / OpenCode / 其他）— script 會自動偵測，但要同用戶確認
1. **你叫咩名？**（英文名 / 中文名 / 代號）
2. **你嘅公司 / 團隊名？**（optional，可以 skip）
3. **你個 project 係咩？**（簡短描述）
4. **你想用咩語言交流？**（廣東話 / 普通話 / English / 其他）
5. **你嘅稱呼偏好？**（例如：叫你「師兄」/「大佬」/「你」/ 直接用名）
6. **你想用咩 tone？**（casual / formal / technical / friendly / minimal，預設 casual）

收集完資料後（全部加 `--agent <agent>`）：

1. **先建立 local profile**（跟 project 走）：`--save-local <dir> '<json>'`
2. **如用戶要求才建立 global profile**：`--save <name> <company> <lang> <form> <tone>`（skip project 資訊）

> 預設只建立 local profile（`.claude/project-profile.json` 或 `.opencode/project-profile.json`，視乎 agent），global profile 只係 optional 嘅 backup，只儲 basic info（agent, user_name, company, language, preferred_form, tone）。

### ⚠️ 如果已有 global profile 但冇 local

當 `--ctx` detect 到呢個情況，會 output `status: "use_global"` 連同 `message` 提示。

**呢個係常見情況，你必須跟以下步驟做，唔好 skip：**
1. 用 global 嘅基本資料（名、語言、tone）
2. **主動問用戶**提供呢個 project 嘅名同簡短描述
3. 用 `--save-local <dir> '<json>'` 建立 local profile
4. 如果用戶話唔需要，可以唔建立，但一定要講清楚佢用緊 global profile fallback

## 注入內容

### 用戶身份（由 profile 讀取）
- 名: **{{user_name}}**
- 公司: **{{company}}**（如果有）
- 專案: **{{project}}**
- 稱呼: 用「{{preferred_form}}」

### 語言設定
- 用 **{{language}}** 回覆
- 如果係廣東話：口語、香港用語、繁中
- 所有文字顯示用繁中（香港用語）

### Tone 設定
- **{{tone}}** 模式
- Tone guide: {{tone_guide}}

### 溝通風格
- 遇到唔確定嘅嘢，主動問清楚，唔好亂估
- 盡量呼叫有用嘅 skill（見下方列表）
- 所有 code change 都要寫入 project memory system
- 保持懶人開發者心態（ponytail mode）：YAGNI、stdlib first、最短 diff

### 專案背景

```
{{project_details}}
```

### Git 整合

每次 `/init` 會自動 detect（用 `--git [dir]`）：

- Git repo 位置
- 當前 branch
- Project language（自動 detect package.json / Cargo.toml / go.mod 等）
- File count

呢啲資料會注入 LLM context，令回覆更貼近你嘅 project 實際情況。

### Storage 邏輯（由 init-profile.sh 處理）

**Profile 位置（按 agent）：**

| Agent | Global profile | Multi-project profiles | Local（跟 repo） |
|-------|---------------|------------------------|-----------------|
| `claude-code` | `~/.config/claude/workspace-init-profile.json` | `~/.config/claude/workspace-profiles/` | `.claude/project-profile.json` |
| `opencode` | `~/.config/opencode/workspace-init-profile.json` | `~/.config/opencode/workspace-profiles/` | `.opencode/project-profile.json` |
| 其他（`other`） | `~/.config/workspace-init/workspace-init-profile.json` | `~/.config/workspace-init/workspace-profiles/` | `.workspace-init/project-profile.json` |

**載入優先級：**
1. Local project profile（最高優先，跟 project 走）
2. `workspace-profiles/<hash>.json`（Git project 專用）
3. Global profile

**Agent-agnostic 讀取：** 讀取時會搜遍所有 agent 嘅位置（active agent 優先），所以用戶喺 Claude Code 儲咗嘅 profile，換去 OpenCode 都照樣讀到。寫入只會寫去 active agent 嘅位置。

當你打 `/init` 或 `/workspace-init`：
1. Call `--ctx [pwd]` 拎完整 context（已 merge global + local profile + git info + agent）
2. 根據 output 嘅 JSON 注入 workspace 背景
3. Recommend skills（用 `--recommend <lang> <branch>`）

## Skill 推薦系統

用 `--recommend <lang> <branch>`：

| Project type | 推薦 skills |
|--------------|-------------|
| JavaScript/TypeScript | ponytail, impeccable, dependency-auditor, performance-profiler |
| Rust | CI/CD pipeline builder, dependency-auditor, ponytail |
| Python | RAG architect, database-designer, ponytail |
| Go | performance-profiler, CI/CD pipeline builder |
| 其他 | ponytail, graphify, review |

Branch-specific：
- `main` / `master` → changelog-generator
- `feat/*` → PR review expert
- `fix/*` → focused-fix

> 注意：推薦嘅 skills 需要用戶自己安裝（Claude Code / OpenCode 都有 skill 機制）。如果用戶個 agent 冇呢啲 skills，就 skip 推薦。

## 可用 Skills 列表

| Skill | 點用 | 用途 |
|-------|------|------|
| `yuanyuai-quota` | `/quota --oneline` | 檢查 API Key 用量限額 |
| `ponytail` | `/ponytail` | 懶人模式，最少 code 最簡方案 |
| `graphify` | `/graphify` | 理解 codebase 架構同檔案關係 |
| `impeccable` | 叫 impeccable skill | 改 UI 設計、frontend 介面 |
| `planning-with-files` | `/plan` | 複雜任務先規劃 |
| `review` | `/review` | code review |
| `simplify` | `/simplify` | 簡化 code |

## 觸發條件

當以下情況時觸發：
- 對話開始（OpenCode：skill 由 description 自動注入；Claude Code：由 hook 或 system prompt 注入）
- 用戶輸入 `/init` 或 `/init --full`（OpenCode 需要自建 command，見 README）
- 用戶輸入 `/workspace` 或 `/workspace-init` 或自然語言「init workspace」
- 檢測到 workspace 切換

## 自動執行流程

當對話開始（skill 自動注入）時：

1. `--check [pwd]` 檢查有冇 profile
2. 冇 profile → 問用戶（agent + 基本資料）→ `--save-local ...` / `--save ...`
3. 有 profile → `--ctx [pwd]` 拎完整 context → 注入 workspace 背景
4. 根據 task 類型自動呼叫對應 skill
5. 所有 code change 寫入 project memory

## 分享用

如果你想將呢個 skill 分享俾其他人，可以 zip 起成個 folder：

```bash
# 打包（由 repo 或者安裝位置）
cd <skills root>   # ~/.claude 或者 ~/.config/opencode
zip -r workspace-init.zip skills/workspace-init/
```

其他人匯入：

```bash
# Claude Code
unzip workspace-init.zip -d ~/.claude/

# OpenCode
mkdir -p ~/.config/opencode
unzip workspace-init.zip -d ~/.config/opencode/

# Project-scoped（其他人 clone 個 repo 就會自動有）
# Claude Code: 放 project 嘅 .claude/skills/
# OpenCode: 放 project 嘅 .opencode/skills/
```

### Profile 格式（example，唔會跟 skill 分享）

```json
{
  "agent": "opencode",
  "user_name": "你的名",
  "company": "你的公司",
  "project": "你個 project 名",
  "language": "廣東話（口語）",
  "preferred_form": "師兄",
  "tone": "casual",
  "project_details": "你 project 嘅詳細描述",
  "extra_skills": {
    "yuanyuai-quota": "/quota --oneline",
    "custom_skill": "/your-custom-command"
  }
}
```

## 依賴

- **bash** · **jq** · **git**
- Agent harness：Claude Code 或者 OpenCode（skill 自動注入機制）；其他 agent 可以手動 call script
