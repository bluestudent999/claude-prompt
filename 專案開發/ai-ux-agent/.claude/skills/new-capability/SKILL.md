---
name: new-capability
description: 為 UX 審計管線新增一個能力骨架（新的管線階段 / Observation 收集器 / Persona / Task / UX Rule / Report 格式），遵循 Core-Port-Adapter 分層。新增能力時使用。
---

# new-capability

建立一個符合分層與階段紀律的能力骨架（骨架先行，不實作業務邏輯）。

## 步驟

1. 向使用者確認：能力類型（管線階段 / Observation 種類 / Persona / Task / UX Rule / Report 格式）、名稱、與**所屬 E-Phase**。
2. **範圍守門**：對照 dev-plan §6 能力矩陣，確認該能力屬當前階段；若屬後續階段（如 E1 想加 HTML / A11y），**停止並回報越界**。
3. 建立骨架，放置到正確分層：
   - 純模型 / 規則 → Core / Domain（不依賴框架）。
   - 需外部技術（LLM / 瀏覽器 / 檔案）→ 定義 / 沿用 Port，Adapter 放 Infrastructure，並補 Stub。
4. **契約對齊**：若涉及 `Observation / Issue / Report`，確保 Issue 仍能連結證據、四欄位齊全。
5. **不實作業務邏輯**（骨架先行）。
6. 完成後執行 `/arch-check` 確認邊界未被打穿。

需要設計資料模型時委派 `persona-task-modeler`；需要建立 Port/Adapter 時委派 `port-adapter`。
