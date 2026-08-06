export const meta = {
  name: 'verify-equivalence',
  description: '升級後行為等價多維度驗證：對照 baseline，逐維度（啟動/鑑權/API契約/編碼/序列化/資料正確性）審查 diff 是否行為等價，逐發現對抗驗證',
  phases: [
    { title: 'Verify' },
    { title: 'Challenge' },
  ],
}

// 對應 breaking-changes.md §F 的行為等價維度
const DIMENSIONS = [
  { key: 'startup', prompt: '審查升級後應用能否在目標版本啟動：context 載入、bean 裝配、auto-config（spring.factories→.imports）、jakarta namespace 是否漏遷導致 runtime ClassNotFound。對照 verification.md V1。' },
  { key: 'security', prompt: '審查 Spring Security 5→6 的路徑匹配是否語義等價（breaking-changes §C4）：requestMatchers 是否覆蓋升級前 antMatchers 的所有授權規則，有無誤放行/誤擋。要求整合測試證據。' },
  { key: 'api-contract', prompt: '審查對外 API 契約：trailing slash（§B5）相容性、response JSON 格式/欄位順序是否與升級前一致。' },
  { key: 'encoding', prompt: '審查字元編碼（§A8）：getBytes() / new String(byte[]) / FileReader 是否顯式 UTF-8，JDK 18+ 預設變更是否影響中文/多語輸出。' },
  { key: 'serialization', prompt: '審查時間/序列化（§A9 + Jackson）：日期格式化、JSON 序列化行為是否變化。' },
  { key: 'data-correctness', prompt: '審查資料正確性（§D4，若用 JPA/Hibernate）：主鍵生成策略、欄位映射、HQL 查詢結果是否與升級前等價。若用 MyBatis 則審 mapper 掃描與 starter 變更。' },
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
          breakingChangeRef: { type: 'string', description: '對應 breaking-changes.md 編號，如 C4 / A8' },
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
    behaviorChanged: { type: 'boolean', description: '是否確實造成行為改變（非等價）' },
    reason: { type: 'string' },
    neededVerification: { type: 'string', description: '需要的測試/QA 證據' },
  },
  required: ['behaviorChanged', 'reason'],
}

// pipeline：每維度審完即對其發現對抗驗證
const results = await pipeline(
  DIMENSIONS,
  (d) => agent(
    `${d.prompt}\n先用 \`git diff\` 取得升級變更，對照 .claude/rules/breaking-changes.md §F 與 verification.md §1 baseline 對照法，回傳 findings。`,
    { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS }
  ),
  (review, d) => parallel(((review && review.findings) || []).map((f) => () =>
    agent(
      `對抗驗證以下升級行為等價疑慮（預設保守：無法確認等價就判 behaviorChanged=true，要求補測試）：\n` +
      `「${f.title}」 — ${f.detail}（${f.file || 'n/a'}，ref: ${f.breakingChangeRef || 'n/a'}）`,
      { label: `challenge:${d.key}`, phase: 'Challenge', schema: VERDICT }
    ).then((v) => ({ ...f, dimension: d.key, verdict: v }))
  ))
)

const confirmed = results.flat().filter(Boolean).filter((x) => x.verdict && x.verdict.behaviorChanged)
return { confirmed, total: results.flat().filter(Boolean).length }
