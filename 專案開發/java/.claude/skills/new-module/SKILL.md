---
name: new-module
description: 建立一個 SDRP Spring Modulith 模組骨架（domain/application/infrastructure/interfaces 四層 + @ApplicationModule package-info）。新增模組時使用。
---

# new-module

建立一個符合分層紀律的 Modulith 模組骨架。

## 步驟

1. 向使用者確認模組名稱 `<name>`（如 `acquisition`）。
2. 在 `src/main/java/com/sdrp/<name>/` 下建立四層 package：
   - `domain/`（L2，純邏輯 + Port 介面）
   - `application/`（L3，用例編排）
   - `infrastructure/`（L1，Adapter 實作）
   - `interfaces/`（L4，Controller / Listener）
3. 加 `package-info.java`，標註 `@org.springframework.modulith.ApplicationModule`。
4. **不實作業務邏輯**（骨架先行）。
5. 完成後執行 `/arch-check` 確認新模組邊界未被打穿。

需要為模組設計領域模型時，委派 `domain-modeler`；需要建立 Port/Adapter 時，委派 `port-adapter`。
