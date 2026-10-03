# workspace-init — Multi-agent Workspace Personalisation Skill

![GitHub release](https://img.shields.io/badge/version-3.0.0-blue)
![Claude Code](https://img.shields.io/badge/Claude%20Code-✓-purple)
![OpenCode](https://img.shields.io/badge/OpenCode-✓-green)

**workspace-init** 係一個 multi-agent skill，每次對話開始時自動注入你嘅 workspace 背景、身份、語言偏好同 project context。支援 **Claude Code**、**OpenCode** 同其他 agent。

**目的：** 提高 LLM 嘅 cache hit rate、減少重複解釋、令每次對話更個人化。

---

## 功能

- ✅ **多 agent 支援** — Claude Code / OpenCode / 其他 agent，首次使用會問你用緊邊個
- ✅ 第一次用 `/init` 問你嘅名、公司、語言偏好、tone，然後記住
- ✅ 每次對話自動注入 context，唔使再重複講「我用廣東話」、「唔好亂估」
- ✅ 自動 call 其他 skills（ponytail、graphify、yuanyuai-quota 等）
- ✅ 支援多種語言（廣東話、普通話、English、其他）
- ✅ **Git 整合** — 自動 detect branch、project language
- ✅ **Tone 設定** — casual / formal / technical / friendly / minimal
- ✅ **Skill 推薦系統** — 根據 project language 同 branch 推薦相關 skills
- ✅ **Profile 匯出/匯入** — backup 或搬去第二部機
- ✅ **多 project 支援** — 唔同 folder 自動 detect 用唔同 profile
- ✅ **Agent-agnostic profile** — 同一個 profile 喺 Claude Code / OpenCode 切換都得
- ✅ 所有資料自己控制，唔會洩漏俾其他人

## 安裝

### Claude Code

**快速安裝（推薦）：**

```bash
curl -L -o /tmp/hkinit.zip https://github.com/KaitoHina/workspace-hkinit-skill/archive/refs/heads/main.zip
unzip /tmp/hkinit.zip -d /tmp/hkinit
cp -r /tmp/hkinit/workspace-hkinit-skill-main/skills/workspace-init ~/.claude/skills/
```

或者直接 clone：

```bash
git clone https://github.com/KaitoHina/workspace-hkinit-skill.git /tmp/hkinit
cp -r /tmp/hkinit/skills/workspace-init ~/.claude/skills/
```

Project-scoped（跟 repo 分享，其他人 clone 就有）：

```bash
mkdir -p .claude/skills
cp -r ~/.claude/skills/workspace-init .claude/skills/
git add .claude/skills/workspace-init
git commit -m "add workspace-init skill"
```

### OpenCode

```bash
curl -L -o /tmp/hkinit.zip https://github.com/KaitoHina/workspace-hkinit-skill/archive/refs/heads/main.zip
unzip /tmp/hkinit.zip -d /tmp/hkinit
mkdir -p ~/.config/opencode/skills
cp -r /tmp/hkinit/workspace-hkinit-skill-main/skills/workspace-init ~/.config/opencode/skills/
```

Project-scoped：放 `.opencode/skills/` 入面就得。

> **Optional：** OpenCode 冇 built-in `/init`，可以自建一個 command 方便呼叫：
>
> ```bash
> mkdir -p ~/.config/opencode/commands
> cat > ~/.config/opencode/commands/init.md <<'EOF'
> 用 workspace-init skill 重新注入 workspace context（call init-profile.sh --ctx），然後按 output 注入背景。
> EOF
> ```

### 其他 agent（Codex / Aider / Gemini CLI / Cursor 等）

skill 嘅 `init-profile.sh` script 係 agent-agnostic 嘅，任何 agent 都可以 call：

```bash
bash <skill_dir>/scripts/init-profile.sh --agent other --ctx
```

- Profile 會存去 neutral 位置：`~/.config/workspace-init/` + project 嘅 `.workspace-init/`
- 唔同 agent 嘅「自動注入」機制唔同（例如 AGENTS.md、.cursorrules），可以將 `SKILL.md` 嘅注入指引複製去該 agent 嘅 instruction file

## 首次使用

開一個新對話，然後輸入：

```
/init
```

Skill 會問你：

0. **你用緊邊個 agent？** — Claude Code / OpenCode / 其他（自動偵測，但會同你確認）
1. **你叫咩名？** — 英文名 / 中文名 / 代號都得
2. **你嘅公司 / 團隊名？** — optional，可以 skip
3. **你個 project 係咩？** — 簡短描述
4. **你想用咩語言交流？** — 廣東話 / 普通話 / English / 其他
5. **你嘅稱呼偏好？** — 例如「師兄」、「大佬」、「你」
6. **你想用咩 tone？** — casual / formal / technical / friendly / minimal

預設會建立 **local profile**（`.claude/project-profile.json` 或 `.opencode/project-profile.json`，視乎 agent），唔會儲存 global profile。

如果你需要 global profile（跨 project 共用），可以叫 LLM 幫你 save 埋一份。Global profile 只儲存基本資料（agent、user_name、company、language、preferred_form、tone），唔會包含 project 資訊。

**如果已有 global profile 但未建立 local profile**，LLM 會 detect 到並提示你補返 project 名同描述，然後自動建立 local profile。

## 用法

| 指令 | 功能 |
|------|------|
| `/init` | 重新注入 workspace context（自動 detect Git + 推薦 skills） |
| `/init --full` | 完整版（含 quota check + memory 狀態） |
| `/init --reset` | 重置所有已儲存嘅資料（active agent） |
| `/init --lang 廣東話` | 直接切換語言，唔使重置 |
| `/init --tone formal` | 設定 tone（casual/formal/technical/friendly/minimal） |
| `/init --export` | 匯出 profile 做 JSON |
| `/init --export my-backup.json` | 匯出到指定檔案 |
| `/init --import my-backup.json` | 匯入 profile |
| `/init --list-projects` | 列出所有已儲存嘅 project profiles |
| `/init --save-project <dir> <json>` | 儲存 project-specific profile（config dir） |
| `/init --save-local | --sl <dir> <json>` | 儲存 local project profile（跟 repo，自動 merge global） |
| `/init --agent-list` | 列出支援嘅 agents |
| `/init --update` | 自動更新 workspace-init 到最新版（更新所有安裝位置） |

## 更新

```bash
/init --update
# 或者手動：
curl -sL https://raw.githubusercontent.com/KaitoHina/workspace-hkinit-skill/main/skills/workspace-init/scripts/update.sh | bash
```

## 技術細節

### Agent 支援

| Agent | Skill 安裝位置 | Global profile | Multi-project profiles | Local profile（跟 repo） |
|-------|--------------|----------------|------------------------|--------------------------|
| `claude-code` | `~/.claude/skills/workspace-init` | `~/.config/claude/workspace-init-profile.json` | `~/.config/claude/workspace-profiles/` | `.claude/project-profile.json` |
| `opencode` | `~/.config/opencode/skills/workspace-init` | `~/.config/opencode/workspace-init-profile.json` | `~/.config/opencode/workspace-profiles/` | `.opencode/project-profile.json` |
| 其他（`other`） | （任意） | `~/.config/workspace-init/workspace-init-profile.json` | `~/.config/workspace-init/workspace-profiles/` | `.workspace-init/project-profile.json` |

- Agent 解析優先級：`--agent` flag > `HKINIT_AGENT` env var > 自動偵測
- **讀取** profile 時會搜遍所有 agent 位置（active 優先）→ 切換 agent 唔會丢 profile
- **寫入**只寫去 active agent 位置
- 權限：`chmod 600`（僅 owner 可讀寫），local profile 記得加入 `.gitignore`（除非你想跟 repo 分享）

### Git 整合

每次 `/init` 會自動 detect：
- Git repo 位置
- 當前 branch
- Project language（自動 detect `package.json` / `Cargo.toml` / `go.mod` 等）
- File count

呢啲資料會注入 LLM context，令回覆更貼近你嘅 project 實際情況。

### Tone 設定

| Tone | 效果 |
|------|------|
| `casual`（預設） | 輕鬆自然，可以加 slang |
| `formal` | 正式書面語，structure 清晰 |
| `technical` | 精準直接，多 spec 同數據 |
| `friendly` | 好似同朋友傾偈，可以 emoji |
| `minimal` | 只講重點，最短回覆 |

### Skill 推薦系統

根據 detect 到嘅 project language 同 branch 自動推薦：

- **JavaScript/TypeScript** → ponytail, impeccable, dependency-auditor, performance-profiler
- **Rust** → CI/CD pipeline builder, dependency-auditor, ponytail
- **Python** → RAG architect, database-designer, ponytail
- **Go** → performance-profiler, CI/CD pipeline builder
- **Branch `main`** → 推 changelog-generator
- **Branch `feat/*`** → 推 PR review expert
- **Branch `fix/*`** → 推 focused-fix

### Multi-project 支援

唔同 Git repo 會自動儲存獨立嘅 project profile（以 git root path 嘅 hash 做 key）：

```
~/.config/<agent>/workspace-profiles/
  ├── <repo1_hash>.json
  ├── <repo2_hash>.json
  └── ...
```

當你喺唔同 folder 開對話，會自動 load 對應嘅 project profile。

### Local Project Profile（跟 project 走）

非 Git project 或者你想 profile 跟 repo 一齊 share，可以用 `--save-local`（或 `--sl`）：

```bash
/init --save-local /path/to/project '{"project":"My App","project_details":"..."}'
# 或者短版
/init --sl /path/to/project '{"project":"My App","project_details":"..."}'
```

`--save-local` 會自動 merge global profile 嘅所有欄位（user_name、company、language、preferred_form、tone、extra_skills 等），所以你只需提供 project 相關嘅 field 就得。

**載入優先級：**
1. Local project profile（最高優先，跟 project 走；`.claude/` 或 `.opencode/` 視乎 agent）
2. `workspace-profiles/<hash>.json`（Git project 專用）
3. 冇 → 用 global profile 嘅預設值

### 依賴

- 你嘅 agent harness（Claude Code 或者 OpenCode 有 skill 自動注入）
- **`jq`** — JSON 處理（profile merge、context build、export/import）
  - **macOS:** `brew install jq`
  - **Linux:** `apt install jq` / `yum install jq`
  - **Windows (Git Bash):** `curl -sL -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe`
- **git** — Git 整合 detect
- **bash** — script 執行
- 其他 skills（optional）：ponytail、graphify、yuanyuai-quota 等，冇嘅話就 skip

---

## 解除安裝

```bash
# Claude Code
rm -rf ~/.claude/skills/workspace-init
rm -f ~/.config/claude/workspace-init-profile.json
rm -rf ~/.config/claude/workspace-profiles

# OpenCode
rm -rf ~/.config/opencode/skills/workspace-init
rm -f ~/.config/opencode/workspace-init-profile.json
rm -rf ~/.config/opencode/workspace-profiles
rm -f ~/.config/opencode/commands/init.md   # 如果有自建

# 其他 agent
rm -rf ~/.config/workspace-init
# + 你放咗 skill 入去嘅位置
```

## License

MIT

---

## Changelog

### v2.2.0 → v3.0.0

- **Multi-agent 支援**：Claude Code / OpenCode / 其他 agent（neutral 路徑）
- **Agent 解析**：`--agent` flag > `HKINIT_AGENT` env var > 自動偵測（只裝 opencode → opencode，否則 claude-code）
- **OpenCode 安裝**：`~/.config/opencode/skills/`，local profile 用 `.opencode/`
- **Agent-agnostic 讀取**：讀 profile 時 union 所有 agent 位置（active 優先），切換 agent 唔丟 profile；寫入只去 active agent
- **Profile 新增 `agent` field**：記錄建立時用緊邊個 agent
- **新 `--set <key> <value>`**：更新單一欄位（local > multi > global），`/init --lang` / `--tone` 改用佢
- **`--save` 明確化**：固定存 global profile（basic info 5 參數），對返 SKILL.md 文檔（原本 8 參數 priority 邏輯，文檔同 script 唔一致）
- **新 `--agent-list`**：列出支援嘅 agents
- **`--reset`**：連 multi-project profiles 一併清（原本淨 global）
- **Bug fix: macOS 冇 `md5sum`** → portable hash（`md5` fallback），multi-project 分倉修正
- **Bug fix: update.sh repo URL** → `KaitoHina/workspace-hkinit-skill`（原本指向錯誤嘅 repo）
- **update.sh 更新所有安裝位置**（Claude Code + OpenCode 各一份都 update）
- **SKILL_DIR 由 script 位置推斷**：唔再 hardcode `~/.claude`，任何安裝路徑都 work
- `--ctx` output 新增 `agent` field；`no_profile` 情況帶 agent 確認提示

### v2.1.0 → v2.2.0

- **Profile priority**: `.claude/project-profile.json` > `workspace-profiles/<hash>.json` > global
- **Default save**: 預設建立 local profile，global 只係 optional backup
- **JSON escaping**: 全部用 `jq -n --arg` build JSON，唔再 raw string interpolation
- **JSON format**: 全部 output formatted multi-line
- **`use_global` status**: detect 冇 local 但有 global 時提示建立 local
- **Cache**: 完全移除 `CACHE_FILE` / `CACHE_TTL`
