# slots（YUMMY 老虎機）開發範本 — 使用指南

> 給誰看：要在 slots repo 上開發的人，以及第一次接手這套 `.claude/` 的 AI Agent。
> 一句話定位：**企劃已經跑完，工單在 backlog，而且企劃文件你有權直接改。**

---

## 部署

```bash
prompt-setup 專案開發 java slots
```

會把整個 `.claude/` 貼到 slots repo 根目錄，並把 `.claude/CLAUDE.md` 搬到 `./CLAUDE.md`。

> 部署後記得把 `CLAUDE.md`、`.claude/*`（`settings.json` 除外）加進專案 `.gitignore` —— `CLAUDE.md` 最後一節有現成片段。

---

## ⚠ 三件開工前必知

### 1. 工單在 `plan/yummy/backlog.md`，不用自己想

企劃階段已完成：**32 顆 T 任務、87 條 AC 全覆蓋、DAG 無環、9 批實作順序**。

每顆任務都標好了 `Required Spec Sections` —— **只讀那幾節**。
spec 有 35KB，通讀就是在浪費上下文，而企劃已經幫你切好了。

兩個關鍵節點：

- **T-09（引擎回歸驗證）** 是全案收斂點。它一次驗證線型、賠率、替代規則、派彩公式。**沒過，後面派彩相關任務都不該開始。**
- **T-11（派彩入帳）** 是最大扇出點，後接 7 顆。它的 R-7 鐵則做錯，彩池／批量／BONUS／免費旋轉全部受影響。

### 2. 你有權改所有企劃文件，不用切回企劃範本

規格有洞、任務切得不對、AC 寫錯、某條規則決定不照參考站做 —— **直接改**。

| 可改 | 唯一的規矩 |
|---|---|
| `backlog.md`、`spec.md`、`business-logic.md`、`brief.md` | 改了要**回寫**，編號要一致 |
| `reference-sampling.md` | 只能新增取樣或更正判讀，**不要把我方的決定寫進去** |

判準：**一個新來的人只讀 `plan/`，能不能完整知道現在的規則是什麼？**

細節見 `rules/plan-authority.md`。特別注意 §3 的第三種標記 —— 改了規則要把**受影響的已完成任務標回未完成**，這是最容易漏的。

### 3. 規則不在這套範本裡，一個字都沒有

本範本**刻意不寫**任何賠率、線型、符號、公式、UI 行為。
要知道櫻桃三連賠多少？**去讀 `plan/yummy/spec.md` §1.4。**

理由：抄一份就是多一個會過期的來源，而這個專案的核心指標（M-1 保真度 100%）最怕的就是有兩份不一樣的規則。

範本只管**工程紀律**：錢不會算錯地方、不會動兩次、事後查得到、依據追得回去。

---

## 業務規則 vs 工程不變量：什麼能改、什麼不能

這是這套範本的核心切分：

| | 住在哪 | 能不能改 |
|---|---|---|
| **業務規則**（怎麼算、怎麼連、怎麼觸發、賠多少） | `plan/yummy/spec.md` | ✅ **能**，回寫即可 |
| **工程不變量 I1~I8**（後端權威、錢包唯一、入帳不依賴前端、冪等、整數、守恆、留痕、無真金流） | `rules/game-invariants.md` | ❌ **不能**，改了就不是對的軟體 |
| **營運參數**（權重、機率、比例、RTP 目標） | 設定檔，`spec.md` §1.4.4 | ✅ 能，由營運訂 |

> `business-logic.md` §5 已經做過一次關鍵切分：**可觀察的照抄，不可觀察的自訂。**
> 符號權重、彩池注入比例、觸發機率從截圖本來就看不出來，**也不需要看出來** ——
> 它們是 brief §2.2 V-2「數值自主」要的東西。

---

## 這套規範在防什麼

| 規範 | 防的事 |
|---|---|
| I1 後端權威 + `architecture.md` | 前端算錢。只要有第二個地方算得出金額，遲早不一致 |
| I3 入帳不依賴前端 | 玩家動畫播到一半關瀏覽器 → 獎金被吃掉（spec R-7 鐵則的理由） |
| I4 單局冪等 | 連點扣兩次；批量與免費旋轉序列用整批當識別碼，重試整批重算 |
| I6 資金守恆 | 彩池被掏空或超額派獎，而且沒有對帳點可以發現 |
| `architecture.md` §4 | 判定引擎綁死 Spring → M-2 實測回歸與 100 萬局 RTP 模擬都跑不動 |
| `rng-rtp.md` §4 | RTP 沒達標就去調權重表 —— 那會同時蓋掉派彩的 bug，而且之後沒人會再查 |
| `fidelity.md` 依據追溯 | 規則改了卻只改程式不改 spec，半年後沒人知道當初為什麼這樣寫 |
| `plan-authority.md` §3 | 改了規則，卻忘記把受影響的已完成任務標回去重驗 |
| `development-workflow.md` OQ 兩條 | 寫沒人看得懂的問題然後卡住；或把自己能決定的事丟回去問 |

---

## 快速開始

```bash
# 1. 看工單
sed -n '/## 任務清單/,/## 建議實作順序/p' plan/yummy/backlog.md

# 2. 挑一顆（第 1 批：T-01 或 T-05，兩條獨立起點）
#    只讀它 Required Spec Sections 指定的章節

# 3. 動到玩法規則的提交前
/fidelity-check

# 4. 動到判定引擎或派彩後必跑
/payout-verify
```

---

## Sub-agents 怎麼派

| 動到什麼 | 派誰 | 它只看一件事 |
|---|---|---|
| 玩法規則 | `fidelity-reviewer` | 指得出 spec 編號嗎？spec 同步了嗎？ |
| 錢 | `payout-guard` | 算錯、動錯、動兩次、對不起來？ |
| RNG／參數／彩池 | `rng-rtp-reviewer` | 公不公正、查不查得到？ |
| 結構、前後端介面 | `arch-guard` | 職責有沒有放錯地方？ |
| 前端 | `game-client-reviewer` | 有沒有越界算錢、行為對 AC 嗎？ |
| 其他 Java | `code-reviewer` | 結構、命名、資源、併發 |

五個守門人**可以平行跑**，職責刻意不重疊。

> 注意：**它們不會因為「這條規則跟參考站不一樣」就擋你** —— 只要 spec 標了 `🔧 自訂` 就是合法的。
> 它們擋的是「你做了決定卻沒寫下來」。

---

## 檔案結構

```
.claude/
├── CLAUDE.md                  入口：backlog 驅動、企劃修改權、紅線、派工
├── rules/
│   ├── plan-authority.md      ★ 企劃書可以怎麼改、回寫紀律（本範本的特色）
│   ├── game-invariants.md     ★ I1~I8 工程不變量（不可改的那一半）
│   ├── fidelity.md            ★ 依據要追得回去（M-1 怎麼驗）
│   ├── architecture.md        後端權威、餘額歸屬、判定引擎可獨立測試
│   ├── wallet-seam.md         錢包／啟動憑證／獎勵事件三個接縫
│   ├── rng-rtp.md             開獎公正性、營運參數、模擬紀律
│   ├── game-client.md         前端零計算、動畫與入帳、狀態還原
│   ├── testing.md             L1-L3、三種保真度測試、四種危險情境
│   ├── development-workflow.md backlog 驅動流程、OQ 兩條硬規則、輸出契約
│   ├── coding-style.md        Java 21 / Boot 3.5
│   ├── flyway-migration.md    migration 版本號
│   └── git-workflow.md        分支與提交（測試分支禁止回流）
├── agents/                    8 個：planner + 5 守門人 + code-reviewer + build-error-resolver
├── skills/                    /fidelity-check /payout-verify /rtp-sim /arch-check /strategic-compact
├── hooks/                     OQ 未決時攔截提交
└── settings.json              權限與 hook（**唯一進版控的檔案**）
```

---

## 一句話總結

**規則去讀 `plan/`，不夠就自己補進去；I1~I8 不准動；不知道的先自己判斷，真要問就問得讓國中生聽得懂。**
