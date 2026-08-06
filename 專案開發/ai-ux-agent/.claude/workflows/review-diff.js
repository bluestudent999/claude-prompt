export const meta = {
  name: 'review-diff',
  description: 'AI UX Platform 多維度 code review：管線/分層邊界 / 證據紀律 / 非 RPA / 憑證安全 / E-Phase 越界，逐發現對抗驗證',
  phases: [
    { title: 'Review' },
    { title: 'Verify' },
  ],
}

const DIMENSIONS = [
  { key: 'layering', prompt: '審查目前 git diff 是否違反管線/分層：Core/Domain 引入 Playwright/LLM SDK/HTTP/檔案 I/O、在 Core 直接 new Adapter 或呼叫 SDK、管線非單向（下游回改上游證據）。' },
  { key: 'evidence', prompt: '審查 diff 是否違反證據紀律：出現「無證據 Issue」、Issue.Evidence 未指向真實 Observation、Issue 四欄位（Severity/Category/Evidence/Recommendation）缺漏或 Severity 非合法 Enum。' },
  { key: 'not-rpa', prompt: '審查 diff 是否退化成 RPA/測試框架思維（Click→Assert→Pass），而非產出有證據的 Issue；審計流程是否仍走 Observation→Reasoning→Evaluation→Reporting。' },
  { key: 'failure-trace', prompt: '審查可預期例外（登入失敗/Session 逾時/憑證缺失/API 逾時/目標站不可達）是否被靜默吞掉（裸 except / except: pass），或未在報告留痕、未附失敗證據。' },
  { key: 'secrets', prompt: '審查憑證/secret 是否外洩：明碼帳密/Token/Cookie 進版控或日誌、secret 進入 Core、對目標站的非授權大量請求。' },
  { key: 'phase-scope', prompt: '審查本 diff 是否越界做後續 E-Phase 的事（對照 dev-plan §6：E1 不做 A11y/Network/Perf、HTML、排程、多 Agent、CI/CD）。' },
]

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          file: { type: 'string' },
          detail: { type: 'string' },
        },
        required: ['title', 'detail'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT = {
  type: 'object',
  properties: {
    isReal: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['isReal', 'reason'],
}

// pipeline：每個維度審完即對其發現對抗驗證，無須等所有維度
const results = await pipeline(
  DIMENSIONS,
  (d) => agent(
    `${d.prompt}\n先用 \`git diff\` 取得變更內容，再回傳 findings。`,
    { label: `review:${d.key}`, phase: 'Review', schema: FINDINGS }
  ),
  (review, d) => parallel(((review && review.findings) || []).map((f) => () =>
    agent(
      `對抗驗證以下 UX Platform review 發現是否為真（預設保守：不確定就判 isReal=false）：\n` +
      `「${f.title}」 — ${f.detail}（${f.file || 'n/a'}）`,
      { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT }
    ).then((v) => ({ ...f, dimension: d.key, verdict: v }))
  ))
)

const confirmed = results.flat().filter(Boolean).filter((x) => x.verdict && x.verdict.isReal)
return { confirmed }
