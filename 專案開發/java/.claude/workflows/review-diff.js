export const meta = {
  name: 'review-diff',
  description: 'SDRP 多維度 code review：六角邊界 / 審計 / 冪等可旁路 / 安全 / Phase 越界，逐發現對抗驗證',
  phases: [
    { title: 'Review' },
    { title: 'Verify' },
  ],
}

const DIMENSIONS = [
  { key: 'hexagonal', prompt: '審查目前 git diff 是否違反六角/分層：L2 Domain 引入 Spring/SQL/SDK、跨模組 import internal、reference 反向依賴 alignment、OpenAPI 註解越層。' },
  { key: 'audit', prompt: '審查 diff 的寫入型路徑是否都經 AuditPort 留審計，是否帶 correlationId 與 actor_type。' },
  { key: 'idempotency', prompt: '審查對結算引擎的輸出是否冪等，是否具備 SDRP_UNAVAILABLE 的 fail-safe 旁路。' },
  { key: 'security', prompt: '審查 secrets 是否外洩、Swagger UI 是否在 prod 暴露、輸入驗證是否足夠。' },
  { key: 'phase-scope', prompt: '審查本 diff 是否越界做了後續 Phase 的事（對照各 phase 的 Out of Scope）。' },
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
      `對抗驗證以下 SDRP review 發現是否為真（預設保守：不確定就判 isReal=false）：\n` +
      `「${f.title}」 — ${f.detail}（${f.file || 'n/a'}）`,
      { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT }
    ).then((v) => ({ ...f, dimension: d.key, verdict: v }))
  ))
)

const confirmed = results.flat().filter(Boolean).filter((x) => x.verdict && x.verdict.isReal)
return { confirmed }
