---
name: sec-scan
description: 對標的做完整資安掃描 —— 盤點攻擊面、九條軸分軸掃描、對抗式驗證、產出交給維護方的報告。要做一次完整資安稽核時使用。
---

# sec-scan — 全面資安掃描

**用法：** `/sec-scan`

四階段，**不得跳步**（`rules/scan-workflow.md`）。

---

## 開工前確認三件事

```bash
cat .claude/scan-target.md | head -20
```

1. **標的對不對** —— 掃錯 repo 是事故。
2. **模式是不是靜態稽核** —— 是的話，不得對任何執行中系統發請求（`rules/scope-safety.md` 紅線 1）。
3. **產出位置** —— `<標的>/sec-reports/<YYYY-MM-DD>/`，這是唯一可寫入處。

---

## 階段 1 · 盤點攻擊面

派 `recon`，產出 `recon.md`。**這一階段沒做完不准進階段 2。**

沒有入口清單，後面每條 finding 都論證不了可達性，而可達性是硬要求。

---

## 階段 2 · 分軸掃描（八個 auditor 可平行）

| 軸 | Agent | 優先 |
|---|---|---|
| 多平台隔離 | `tenant-isolation-auditor` | **最高** |
| **過濾器繞過** | `filter-bypass-auditor` | **最高（已發生過實際事故）** |
| 認證授權與越權 | `authz-auditor` | 高 |
| 金流與錢包 | `money-flow-auditor` | 高 |
| **賠率、限額與結算** | `odds-settlement-auditor` | 高（體育投注獨有） |
| 注入與輸入處理 | `injection-auditor` | 中 |
| 機密與設定暴露 | `config-exposure-auditor` | 中 |
| 依賴 CVE | `dependency-cve-auditor` | 低（誤報率最高，最後跑） |

**派工 briefing 必須自包含**（子 agent 不繼承上下文）：`recon.md` 路徑 + 該軸在 `references/scan-axes.md` 的節 + 標的路徑 + 提醒產出候選 finding 交驗證。

> 產出的是**候選 finding**，不是 finding。

---

## 階段 3 · 對抗式驗證

每一條候選 finding 派 `finding-verifier`。**這階段不能省。**

三種去處：通過 → Finding；誤報 → 丟掉（理由不直觀就進「已排除項目」）；驗不出來 → 「待查清單」，不給嚴重度。

---

## 階段 4 · 產出報告

派 `report-writer`，依 `rules/report-standard.md` 組裝。

---

## 交付前自檢

- [ ] 每條 finding 七個必備欄位齊全
- [ ] 每條攻擊路徑從**對外入口**寫起
- [ ] 每條「修復方向」是具體改法，且盡量引用 cx-sports-v2 自己的規範條文
- [ ] 報告中**沒有**真實憑證、可執行 payload、真實玩家資料
- [ ] 跨 repo 問題獨立成章，未混入統計
- [ ] 待查清單、已排除項目、本次掃描限制三章都有
- [ ] 修復優先序依「嚴重度 × 修復成本」四象限排
- [ ] 一頁摘要用白話寫

---

## 回報格式（給使用者的一段話）

報告路徑、Finding 總數與嚴重度分佈、最嚴重的三條各一句白話、待查幾條、本次掃描限制一句話。

> **不要在回報裡說「我可以幫你修」。** 交付邊界到報告為止（`rules/scope-safety.md` 紅線 2）。
