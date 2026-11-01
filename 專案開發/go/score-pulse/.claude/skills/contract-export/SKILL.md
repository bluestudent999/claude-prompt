---
name: contract-export
description: 產出並檢查交付 H5／App 部門的契約——swag 產前台與後台 OpenAPI、比對 platform/envelope 與 realtime.md 的欄位短名、確認四份固定附件存在、以 git diff 判斷契約是否變更並提醒寫 CHANGELOG。任何 A 類 ticket 動到 /api/front/**、WebSocket 或 Kafka 封包後使用。
---

# contract-export — 契約產出與變更判定

**用法：** `/contract-export`，或 `bash .claude/skills/contract-export/contract-export.sh`（`make contract-export` 同義）

契約是交付物的一部分（`rules/api-contract.md`）。產出落在 `docs/contract/`，與程式碼**同一個 commit**。

---

## Step 1 · 跑腳本

```bash
bash .claude/skills/contract-export/contract-export.sh
```

腳本做五件事：

| # | 做什麼 | 失敗代表 |
|---|--------|---------|
| 1 | `swag init` 兩組：前台（`--instanceName front`，掃 `internal/{match,odds,member,notify,operator}/controller`）、後台（`--instanceName admin`，掃 `internal/admin`、業主後台 controller）→ `docs/contract/openapi-{front,admin}.yaml` | swag 註解缺或壞；handler 沒有 `@router` |
| 2 | 比對 `internal/platform/envelope/*.go` 的 json tag 與 `docs/contract/realtime.md` 出現的短名 | 新增或改了欄位沒更新文件 |
| 3 | 檢查 `docs/contract/{README.md,realtime.md,ws-client.example.ts,CHANGELOG.md}` 存在 | 固定附件缺（`api-contract.md` §5） |
| 4 | `git diff --stat -- docs/contract/` 判斷契約是否變更；變更而 `CHANGELOG.md` 無本次條目 → 警告 | 忘記寫變更紀錄 |
| 5 | 輸出「契約有更新：<端點清單>」給回覆用 | — |

## Step 2 · 判定相容性（人工，對照 `api-contract.md` §3）

```bash
git diff -- docs/contract/openapi-front.yaml | grep -E '^[-+]\s+(/api|required:|type:|- [a-zA-Z_]+$)' | head -60
```

| 看到 | 判定 |
|------|------|
| 只有 `+` 的路徑、欄位、enum 值 | 相容 → CHANGELOG 一行 |
| 有 `-` 的路徑或欄位、`type:` 改變、`required:` 變多 | **破壞性 → 停手**，開 OQ 回報，等使用者協調過渡期 |
| `realtime.md` 的 `v` 升版 | 舊版並行至少一個 App 發版週期 |

## Step 3 · CHANGELOG 格式

```markdown
## 2026-11-20 — S2-T8
- [相容] 新增 `GET /api/front/v1/match/{id}/snapshot` 回應欄位 `seq`、`ts`
- [相容] WebSocket `/match/{matchId}` 推送新增 `stall` 旗標
```

## Step 4 · 回覆裡固定寫

```
契約有更新：
- GET /api/front/v1/match/{id}/snapshot（新增）
- WS /match/{matchId}（欄位 +stall）
判定：相容 ／ CHANGELOG 已記 ／ 需通知另一部門：是
```

**下一步執行** 派 `contract-reviewer`
