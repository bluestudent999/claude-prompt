---
name: boot3-config-migrate
description: 遷移 application.yml / application.properties / bootstrap.yml 的 Spring Boot 3 屬性改名與棄用。用 spring-boot-properties-migrator 取得 runtime 報告，照著遷移，保持設定語義不變。設定檔對齊 Boot 3 時使用。
---

# Spring Boot 3 設定屬性遷移

> 設定遷移走「讓 Boot 自己報告過時屬性」最可靠。詳細規範見 `agents/config-migrator.md`，本 skill 是操作備忘。

## 啟用時機

- Step 2 Phase C：設定檔遷移（與 OpenRewrite 並行）。
- 升級後啟動報 `Unknown property` / 設定不生效時。

## 主力：spring-boot-properties-migrator

```xml
<!-- 暫時加入待升級模組 pom（驗證後務必移除）-->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-properties-migrator</artifactId>
    <scope>runtime</scope>
</dependency>
```

目標 JDK 下啟動，讀 log：
- `REPLACED` → 屬性改名，照新名改。
- `UNSUPPORTED` → 已移除，找等價設定或移除（不確定列 OQ）。

> **硬規則：遷移驗證完成後務必移除此依賴**（升級期診斷工具，不可進正式依賴）。

## 高頻屬性遷移（對照 breaking-changes.md §B）

| 舊 | 新 |
|----|-----|
| `spring.redis.*` | `spring.data.redis.*` |
| `server.max-http-header-size` | `server.max-http-request-header-size` |
| `spring.mvc.pathmatch.matching-strategy` | 確認預設改 path-pattern-parser 後的自訂值 |

> 完整對照以 migrator runtime 報告為準，不憑記憶。

## 非 application 設定出沒點（grep 補掃）

```bash
# spring.factories auto-config 棄用 → 改 .imports
grep -rln "EnableAutoConfiguration" --include=*.factories src/main/resources/META-INF
# logback/log4j2 的 servlet appender（jakarta）
grep -rn "javax.servlet" --include=*.xml src/main/resources
```

## 遷移流程

```
1. grep 盤所有設定檔 + 非 application 出沒點
2. 加 properties-migrator → 目標 JDK 啟動 → 收集 REPLACED/UNSUPPORTED
3. 逐條遷移（保語義），UNSUPPORTED 列 OQ
4. 重啟確認不再報警
5. 移除 properties-migrator 依賴
```

## 原則

- 遷移是**改 key 不改語義**——不順手調整設定值。
- spring.factories→.imports 涉及自訂 auto-config 載入行為 → 標記交 `regression-reviewer`。
