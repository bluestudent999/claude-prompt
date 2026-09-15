# Claude Prompt 範本庫

一組可重複部署的 `.claude/` AI Agent 規範範本，涵蓋軟體專案生命週期的不同階段。
透過 `prompt-setup` 指令，一鍵把對應範本安裝到任何專案目錄。

---

## 目錄

- [範本清單](#範本清單)
- [快速開始](#快速開始)
- [安裝 prompt-setup](#安裝-prompt-setup)
- [指令用法](#指令用法)
- [更新既有部署（乾淨取代）](#更新既有部署乾淨取代)
- [選項總覽](#選項總覽)
- [部署後結構](#部署後結構)
- [常見情境](#常見情境)
- [一致性檢查（prompt-lint）](#一致性檢查prompt-lint)
- [設計說明](#設計說明)

---

## 範本清單

| 指令 | 範本 | 適用場景 | 語言棧 |
|------|------|---------|--------|
| `prompt-setup 專案企劃` | 需求規劃 | PM / BA 需求收斂、規格、任務拆解 | 純文件（無程式碼） |
| `prompt-setup 專案開發 java` | 新開發（Java） | SDRP、Spring Modulith | Java 21 / Spring Boot 3 |
| `prompt-setup 專案開發 ai-ux-agent` | 新開發（Python） | AI UX 稽核平台 | Python / Playwright |
| `prompt-setup 專案維護 cx-sports` | 維運 | cx-sports-v2 主業務維護 | Java 8 / Spring Boot 2 / Vue 2 |
| `prompt-setup 專案維護 crypto-payment` | 維運 | crypto-payment 加密支付維護 | Java 21 / Spring Boot 3 / Vue 2 |
| `prompt-setup 版本管理` | 版本升級 | Java 8→21、Boot 2→3 遷移 | Java / OpenRewrite |
| `prompt-setup 網站體驗稽核` | UX 稽核 | 讓 AI 實際體驗已完成的網站，產 UX 修改建議報告 | 純文件（需 Chrome DevTools MCP） |
| `prompt-setup 專案維護 sicbo` | 維運 | sicbo 骰寶骰子辨識服務維護 | Python 3.12 / YOLOv8 / OpenCV |
| `prompt-setup 專案開發 java crypto-node` | 新開發（Java） | crypto-node 鏈下索引服務（多租戶、38 步驟驅動） | Java 21 / Spring Boot 3.5 / PostgreSQL |

> 隨時用 `prompt-setup --list` 查看實際可用範本。

---

## 快速開始

```bash
cd /path/to/你的專案          # 1. 進入目標專案目錄
prompt-setup 專案開發 ai-ux-agent # 2. 安裝對應範本
claude                        # 3. 啟動 Claude Code，範本自動生效
```

指令會：
1. 把對應的 `.claude/` 整包複製到當前目錄
2. 把其中的 `CLAUDE.md` **搬到專案根目錄**（Claude Code 從根目錄讀取）
3. 若範本附 `settings.local.json.example`，自動產生一份 `settings.local.json` 供你填金鑰

---

## 安裝 prompt-setup

指令腳本位於本範本庫的 [`bin/prompt-setup`](bin/prompt-setup)。安裝成全域指令（擇一）：

**方式 A：symlink 到 PATH（推薦，改腳本免重裝）**

```bash
ln -sf /Users/joel_java/Documents/claude-prompt/bin/prompt-setup ~/.local/bin/prompt-setup
```

**方式 B：加 alias 到 shell 設定**

```bash
echo 'alias prompt-setup="/Users/joel_java/Documents/claude-prompt/bin/prompt-setup"' >> ~/.zshrc
source ~/.zshrc
```

驗證：

```bash
prompt-setup --list
```

> 若安裝後在目前終端機找不到指令，開新終端機即可（確認 `~/.local/bin` 在 `PATH`）。

---

## 指令用法

```
prompt-setup <分類> [子項] [選項]
```

參數即**目錄路徑**：多層用空白隔開，單層直接給。

```bash
prompt-setup 專案開發 ai-ux-agent   # → 專案開發/ai-ux-agent/.claude
prompt-setup 專案開發 java       # → 專案開發/java/.claude
prompt-setup 專案開發 java crypto-node  # → 專案開發/java/crypto-node/.claude
prompt-setup 專案維護 cx-sports       # → 專案維護/cx-sports/.claude
prompt-setup 專案維護 crypto-payment  # → 專案維護/crypto-payment/.claude
prompt-setup 專案維護 sicbo          # → 專案維護/sicbo/.claude
prompt-setup 版本管理            # → 版本管理/.claude
prompt-setup 專案企劃            # → 專案企劃/.claude
prompt-setup 網站體驗稽核        # → 網站體驗稽核/.claude
```

安裝到指定目錄（不用先 `cd`）：

```bash
prompt-setup 專案維護 cx-sports --dir /path/to/專案
```

先預覽不寫入：

```bash
prompt-setup 版本管理 --dry-run
```

---

## 更新既有部署（乾淨取代）

目標若已有 `.claude` / `CLAUDE.md`，預設會**擋下**避免誤蓋。要更新請加 `--force`——它是**乾淨取代**：清除原有 `.claude` 與舊的根 `CLAUDE.md`，再貼上全新一份（不會殘留舊範本的檔案）。

```bash
prompt-setup 專案維護 crypto-payment --force              # 清舊貼新，但「保留」你已填金鑰的 settings.local.json
prompt-setup 專案維護 crypto-payment --force --reset-local # 徹底重置，連 settings.local.json 也清掉
```

| 指令 | .claude 內容 | settings.local.json（機密） |
|------|-------------|---------------------------|
| （無 `--force`，目標已存在） | 不動作，直接擋下 | — |
| `--force` | 清除重貼 | **保留** |
| `--force --reset-local` | 清除重貼 | 清除，改由 `.example` 重建 |

---

## 選項總覽

| 選項 | 說明 |
|------|------|
| `-d, --dir <path>` | 指定目標目錄（預設：目前工作目錄） |
| `-f, --force` | 乾淨取代：清除原有 `.claude` 與舊根 `CLAUDE.md` 再重貼（保留 `settings.local.json`） |
| `--reset-local` | 搭配 `--force`：連 `settings.local.json` 一起清掉 |
| `-n, --dry-run` | 只顯示會做什麼，不實際寫入 |
| `--with-local` | 一併複製範本庫內的 `settings.local.json`（預設略過，避免帶入本機私有設定） |
| `-l, --list` | 列出所有可用範本 |
| `-h, --help` | 顯示說明 |

---

## 部署後結構

以 `prompt-setup 專案開發 ai-ux-agent` 為例，目標專案會變成：

```
你的專案/
├── CLAUDE.md          ← 從 .claude 搬到根目錄（Claude Code 入口）
└── .claude/
    ├── settings.json
    ├── settings.local.json   ← 有 .example 時自動生成，填金鑰用（勿進版控）
    ├── rules/         ← 每次 session 自動注入的規範
    ├── agents/        ← Sub-agent 定義
    ├── skills/        ← 依任務載入的技能
    ├── hooks/         ← Session / 編輯前 / commit 前觸發腳本
    └── workflows/     ← 多 agent 編排腳本（部分範本有）
```

> `專案維護` 下每個專案（`cx-sports` / `crypto-payment`）各含 `.claude/README.md`（該專案的詳細使用指南），會一併保留在 `.claude/` 內。

---

## 常見情境

**第一次幫某專案裝規範**

```bash
cd ~/work/my-service && prompt-setup 專案開發 java
```

**範本庫更新後，同步到已部署的專案**

```bash
cd ~/work/my-service && prompt-setup 專案開發 java --force
```

**讓 AI 稽核一個已完成的網站，產 UX 建議報告**

```bash
cd ~/work/ux-audits && prompt-setup 網站體驗稽核
claude mcp add chrome-devtools -- npx -y chrome-devtools-mcp@latest   # Agent 的眼睛與手，必裝
# 填 .claude/audit-target.md（目標站 / 環境模式 / 憑證環境變數名），然後：
claude
> /ux-audit https://your-site.com
```

**忘記範本名稱**

```bash
prompt-setup --list
```

**想先看會改哪些檔案**

```bash
prompt-setup 版本管理 --dir ~/work/legacy-app --dry-run
```

---

## 一致性檢查（prompt-lint）

各範本刻意保持獨立、不抽共用 base（見[設計說明](#設計說明)），代價是**少數本該一致的內容會慢慢改歪**。`bin/prompt-lint` 就是用來抓這種漂移的——**只檢查、不改檔**。

```bash
./bin/prompt-lint              # 跑全部檢查
./bin/prompt-lint --only links # 只跑單項（會列出完整清單，不截斷）
./bin/prompt-lint -q           # 只輸出問題
./bin/prompt-lint --list       # 列出偵測到的範本
```

| 檢查 | 抓什麼 |
|------|--------|
| `routing` | 7 份 `CLAUDE.md` 的職責路由表是否逐字一致（以多數份為基準，逐列指出差異） |
| `self-row` | 「你在這裡…**表格第 N 列**」的 N 與該範本指令在表中的實際列號相符 |
| `shared` | 標記為 `<!-- shared:<id> -->` … `<!-- /shared -->` 的區塊跨檔案未漂移 |
| `links` | Markdown 連結與反引號路徑指向的 `.claude` 內部檔案存在 |
| `json` | `.claude` 下所有 `*.json` 格式合法 |

離開碼 `0` = 全數通過、`1` = 有問題、`2` = 用法錯誤，可直接掛 CI 或 pre-commit。

**路徑解析慣例**（`links` 檢查依此判定）：

| 寫法 | 解析基準 |
|------|---------|
| `rules/x.md`、`agents/x.md`、`skills/…`、`references/…`、`templates/…` | `.claude/` 根（不論引用者在哪一層） |
| `.claude/x.md` | `.claude/` 根（入口 `CLAUDE.md` 部署後在專案根目錄，故帶此前綴） |
| `./x.md`、`../x.md` | 引用檔案自己的目錄 |
| 其他（`plan/`、`pom.xml`、`evidence/…`） | 視為**目標專案**路徑，不檢查 |

含 `*` `<` `>` 的萬用/佔位路徑與 `settings.local.json`（部署時才生成）自動略過。

> **`shared` 標記怎麼用：** 目前有 3 個——`test-branch-one-way`（**測試分支單向流動**紅線，見下），落在 6 套開發／維護範本的 `rules/git-workflow.md`；`claude-local-only`（**Claude Code 設定不進版控**紅線，`settings.json` 除外），落在全部 9 套範本的 `CLAUDE.md`；`next-step-closing`（**收尾必寫「下一步執行」**），同樣落在全部 9 套範本的 `CLAUDE.md`。若日後又有某段規範必須在多個範本間逐字一致，把它包進 `<!-- shared:<id> -->` … `<!-- /shared -->`，`prompt-lint` 就會盯住它不漂移——**不需要建組裝機制，也不影響部署**。

---

## 設計說明

- **不合併、保持各套獨立**：各範本的技術棧與規範差異大（甚至互相衝突，如註解語言簡體 vs 繁體），且部署到不同 repo，`.claude/rules/` 又是每 session 全量注入——合成單一範本會造成 token 爆量與指令打架。因此維持獨立範本 + 一鍵部署。
- **CLAUDE.md 搬到根目錄**：Claude Code 從專案根目錄讀取 `CLAUDE.md`，不會自動讀 `.claude/CLAUDE.md`。範本庫把它收在 `.claude/` 內方便管理，部署時再搬出去。
- **乾淨取代優於原地覆蓋**：更新部署時，殘留的舊範本檔案可能造成規範不一致，故 `--force` 一律「清除再貼上」；同時自動保留本機 `settings.local.json`，避免洗掉已填的金鑰。
- **symlink 安裝**：`bin/prompt-setup` 以 symlink 掛到 PATH，日後修改腳本即時生效，無需重裝。

---

## 相關檔案

| 檔案 | 用途 |
|------|------|
| [`bin/prompt-setup`](bin/prompt-setup) | 一鍵部署指令 |
| [`bin/prompt-lint`](bin/prompt-lint) | 範本庫一致性檢查（路由表 / 列號 / shared 區塊 / 連結 / JSON） |
| [`CLAUDE.md`](CLAUDE.md) | 本範本庫自身的 AI Agent 規範（Prompt Architect 角色） |
| `<範本>/.claude/` | 各階段的規範範本本體 |
