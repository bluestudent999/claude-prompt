---
name: blockchain-wallet
description: crypto-payment 區塊鏈與錢包業務知識 — 錢包產生、AES-GCM 私鑰加密、鏈 client（Web3j BSC/ETH、Trident TRON、BitcoinJ）不可混用、入款流程、歸集(sweep)、webhook 驗簽、確認數/reorg。涉及錢包 / 入款 / 歸集 / 鏈對接時載入。
---

# 區塊鏈與錢包業務（crypto-payment）

> 支援 **TRON / BSC / Ethereum**。錢包 / 私鑰 / 金額處理錯誤會造成**不可逆資金損失**——有疑問一律停手問人（見 `rules/security.md`）。

## 錢包與私鑰

- **錢包產生邏輯只在 `service/platform/`**，禁他處重複
- **私鑰儲存前必須 AES-GCM 加密**（Bouncy Castle），**禁明文**落庫 / log / 回應
- 加解密類（含 `Aes`/`Gcm`/`Encrypt`/`Decrypt`/`Key`）**改動須明確確認**
- 每個錢包 platform-bound（多租戶）

## 鏈 Client（不可混用）

| 鏈 | Client | 備註 |
|----|--------|------|
| BSC / Ethereum | **Web3j 4.9.4** | EVM，gas 以 gwei |
| TRON | **Trident 0.10.0** | energy / bandwidth 模型 |
| （對應鏈） | BitcoinJ 0.15.10 | UTXO 模型 |

- **不可用一條鏈的 client 呼叫另一條鏈**
- 各鏈 **decimals 不同**，金額換算一律 `BigDecimal`，禁 `double`
- 鏈節點逾時 / 不可用 → 重試 + 退避，單次失敗不可標記入款失敗或漏收

## 入款流程（deposit）

```
webhook 收到（/api/thirdparty/*，QuickNode/Tatum）
  → 驗 HMAC / 來源校驗
  → 解析 chain log（ChainLogService）
  → 匹配用戶錢包（platform + address）
  → 達足夠確認數才視為最終（reorg 防護）
  → credit 用戶帳戶（@Transactional + BigDecimal + DOWN）
  → 觸發下游 Kafka event
```

- **冪等**：同一 `txHash` 只 credit 一次（DB 唯一約束 + 已處理判斷）——webhook 與 Kafka 都會重送
- **確認數**：未達 chain 設定的確認數不可入帳（防區塊重組）

## 歸集（sweep / collector）

- collector job 把用戶錢包小額入款歸集到**平台熱錢包**
- **尊重每 token 最小歸集門檻**（低於門檻不歸集，避免 gas 蝕本）
- gas / energy 需預估與檢查（來源錢包餘額不足 gas 時的處置）
- 歸集為 L1：金額 + 狀態機 + 冪等 + platform 隔離

## Webhook 驗簽（`/api/thirdparty/*`）

- QuickNode / Tatum 入站 webhook 驗簽或來源 IP 校驗後才解析
- provider / chain / token 設定在 `service/setting/` + config 表，透過 `*ConfigCache` 預載
- 新 provider 對接見 `api-connector-builder` skill

## 相關

- 私鑰 / HMAC / 金額 / platform_id → `rules/security.md`
- 冪等 / 確認數 / reorg → `rules/stability.md`
- 新鏈 / webhook provider → `api-connector-builder` skill
- 資料層 / Flyway → `mysql-shardingsphere5` skill
