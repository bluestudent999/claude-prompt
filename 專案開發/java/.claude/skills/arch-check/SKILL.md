---
name: arch-check
description: 跑 SDRP 架構測試（Spring Modulith verify + ArchUnit 分層規則），回報模組/分層邊界違規。驗證接縫、提交前檢查架構合規時使用。
---

# arch-check

執行 SDRP 的架構守門測試並回報結果。

## 步驟

1. 於 repo 根目錄執行：`./mvnw -q test -Dgroups=architecture`
   （涵蓋 `ApplicationModules.verify()` 與 ArchUnit 分層規則）
2. 解讀結果：
   - **綠燈** → 回報 `PASS`。
   - **紅燈** → 逐條說明：違反哪條邊界規則（Modulith 非法依賴 / Domain 依賴框架 / Application 依賴 Infrastructure / reference 反向依賴 alignment）、涉及哪些類別、**如何修**。
3. 需要更深入的 diff 邊界審查時，委派 `arch-guard` subagent。

只回報，不自行修改程式碼。
