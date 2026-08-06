// ⚠️ 觸發時機：僅在「報告品質不穩、需反覆迭代到達當前 E-Phase 退出閘門」時由人工觸發。
//    這是 token 放大器（最多 5 輪 ×3~4 agent）**不是每個 task 的常規動作**。
//    單次審計請直接用 /run-audit；只想度量成品品質用 /ux-audit-eval。
//
// E-Phase 不寫死：閘門依「當前環境階段」動態決定。
//   - 可用 args 傳入覆寫，例如 { ePhase: 'E2' }；未傳則由 agent 從文件判讀。
//   - 跨階段不變的紅線（證據覆蓋率、四欄位齊全 = 1.0）恆為硬性通過條件。
//   - 階段專屬閘門（最少證據 Issue 數、需審計的觀察模態、報告格式、Persona 數、
//     是否需登入審計 / 例外留痕）一律「從 plan/ 文件讀出」，不在此捏造數字。
export const meta = {
  name: 'quality-loop',
  description: '審計品質迭代（人工觸發、非例行）：判定當前 E-Phase 與其退出閘門 → 跑審計 → 度量證據完整性/閘門 → 提調整建議，直到達當前階段閘門或達輪次上限',
  phases: [
    { title: 'Resolve' },
    { title: 'Audit' },
    { title: 'Evaluate' },
    { title: 'Advise' },
  ],
}

// 從文件判讀出來的「當前階段閘門規格」。數字/清單由 agent 依 dev-plan §6 與當前 Backlog 填入，不寫死。
const GATE_SPEC = {
  type: 'object',
  properties: {
    ePhase: { type: 'string', enum: ['E1', 'E2', 'E3'] },
    minEvidencedIssues: { type: 'number' },                 // 當前階段要求的最少「有證據 Issue」數
    requiredObservations: { type: 'array', items: { type: 'string' } }, // 該階段須落地的觀察模態（E1: screenshot,dom；E2+: 加 a11y/network/console/perf）
    reportFormats: { type: 'array', items: { type: 'string' } },        // E1: [md]；E2+: [md, html] …
    requireLoginAudited: { type: 'boolean' },               // 該階段是否要求審計登入後頁面
    requireFailureTraced: { type: 'boolean' },              // 該階段是否要求可預期例外全數留痕
    source: { type: 'string' },                             // 閘門依據出處（檔案 + 章節），供人工複核
  },
  required: ['ePhase', 'minEvidencedIssues', 'requiredObservations', 'requireLoginAudited'],
}

const METRICS = {
  type: 'object',
  properties: {
    evidenceCoverage: { type: 'number' },       // 有證據 Issue 佔比，硬紅線須 = 1.0
    fourFieldCompleteness: { type: 'number' },   // 四欄位齊全佔比，硬紅線須 = 1.0
    evidencedIssueCount: { type: 'number' },     // 對照 gate.minEvidencedIssues
    observationsPresent: { type: 'array', items: { type: 'string' } }, // 實際落地的觀察模態
    reportFormatsPresent: { type: 'array', items: { type: 'string' } },// 實際產出的報告格式
    loginAudited: { type: 'boolean' },
    failureTraced: { type: 'boolean' },
    regressions: { type: 'array', items: { type: 'string' } },
  },
  required: ['evidenceCoverage', 'fourFieldCompleteness', 'evidencedIssueCount'],
}

// ── Step Resolve：判定當前 E-Phase 與其退出閘門（可由 args 覆寫）──────────────
phase('Resolve')
const forced = (args && args.ePhase) ? `使用者已指定當前階段為 ${args.ePhase}，以此為準。` : ''
const gate = await agent(
  '判定「當前環境階段（E-Phase）」與該階段的 UX 審計退出閘門。' + forced + '\n' +
  '步驟：讀 CLAUDE.md 「§1 指路」的當前 E-Phase 標註；再讀 plan/ai-ux-agent-dev-plan.md §6 能力矩陣 ' +
  '與當前階段 Backlog（如 plan/ai-ux-agent-e1-backlog.md）的退出閘門。\n' +
  '據此回填：ePhase、minEvidencedIssues、requiredObservations（該階段須落地的觀察模態）、reportFormats、' +
  'requireLoginAudited、requireFailureTraced，並在 source 註明依據出處。' +
  '**不得自行捏造未載於文件的數字**；文件未明定者取該階段能力矩陣可推得的最小合理值並在 source 說明。',
  { label: 'resolve-gate', phase: 'Resolve', schema: GATE_SPEC }
)
log(`E-Phase=${gate.ePhase} 閘門：evidenced≥${gate.minEvidencedIssues} obs=[${gate.requiredObservations.join(',')}] login=${gate.requireLoginAudited} (源：${gate.source || 'n/a'})`)

const MAX_ROUNDS = 5
let round = 0

while (round < MAX_ROUNDS) {
  round++

  phase('Audit')
  await agent(
    `執行一次端到端 UX 審計（開站 → 觀察 → 推理 → 評估 → 報告），對指定目標產出報告並落地 reports/ 資料夾。` +
    `當前為 ${gate.ePhase} 階段：須落地觀察模態 [${gate.requiredObservations.join(', ')}]，` +
    `報告格式 [${(gate.reportFormats || ['md']).join(', ')}]。` +
    '觀察證據須落地磁碟，可預期例外須留痕不靜默。回報報告路徑與 Issue 數。' +
    '**不得實作超出當前階段的能力**（越界違反 E-Phase 範圍紀律）。',
    { label: `audit#${round}`, phase: 'Audit' }
  )

  phase('Evaluate')
  const m = await agent(
    `委派 ux-evidence-auditor 度量最新報告（當前 ${gate.ePhase} 階段）：` +
    'evidenceCoverage、fourFieldCompleteness、evidencedIssueCount、observationsPresent、reportFormatsPresent、' +
    'loginAudited、failureTraced、regressions。' +
    '逐一驗證每個 Issue 的 Evidence 是否指向真實存在的 Observation 檔。',
    { label: `eval#${round}`, phase: 'Evaluate', schema: METRICS }
  )
  log(`round ${round}: coverage=${m.evidenceCoverage} fields=${m.fourFieldCompleteness} evidenced=${m.evidencedIssueCount} obs=[${(m.observationsPresent||[]).join(',')}] login=${m.loginAudited}`)

  // ── 判定：硬紅線（全階段）+ 階段專屬閘門（來自 gate spec）──────────────
  const obsPresent = new Set(m.observationsPresent || [])
  const obsMissing = gate.requiredObservations.filter((o) => !obsPresent.has(o))
  const fmtPresent = new Set(m.reportFormatsPresent || [])
  const fmtMissing = (gate.reportFormats || []).filter((f) => !fmtPresent.has(f))

  const redlineOk = m.evidenceCoverage >= 1.0 && m.fourFieldCompleteness >= 1.0
  const phaseOk =
    m.evidencedIssueCount >= gate.minEvidencedIssues &&
    obsMissing.length === 0 &&
    fmtMissing.length === 0 &&
    (!gate.requireLoginAudited || m.loginAudited === true) &&
    (!gate.requireFailureTraced || m.failureTraced === true)

  if (redlineOk && phaseOk) {
    return { reached: true, ePhase: gate.ePhase, round, metrics: m, gate }
  }

  phase('Advise')
  const gaps = [
    m.evidenceCoverage < 1.0 ? `證據覆蓋率 ${m.evidenceCoverage}<1.0` : null,
    m.fourFieldCompleteness < 1.0 ? `四欄位齊全 ${m.fourFieldCompleteness}<1.0` : null,
    m.evidencedIssueCount < gate.minEvidencedIssues ? `有證據 Issue ${m.evidencedIssueCount}<${gate.minEvidencedIssues}` : null,
    obsMissing.length ? `缺觀察模態 [${obsMissing.join(',')}]` : null,
    fmtMissing.length ? `缺報告格式 [${fmtMissing.join(',')}]` : null,
    (gate.requireLoginAudited && m.loginAudited !== true) ? '登入後頁面未審計' : null,
    (gate.requireFailureTraced && m.failureTraced !== true) ? '例外未全數留痕' : null,
  ].filter(Boolean)

  await agent(
    `當前 ${gate.ePhase} 階段未達閘門。未達項：${gaps.join('；') || '（見度量）'}。` +
    `退步案例：${((m.regressions) || []).join('; ') || '無'}。\n` +
    '針對未達項提出具體調整建議（推理未引用證據 / UX 規則過寬或過嚴 / 例外未接管 / ' +
    '觀察模態未落地 / 報告格式缺項 / 登入流程未進登入後區域），' +
    '**列給人確認，不要自行套用**。',
    { label: `advise#${round}`, phase: 'Advise' }
  )
}

return { reached: false, ePhase: gate.ePhase, rounds: round, gate, note: `已達 ${MAX_ROUNDS} 輪上限仍未達 ${gate.ePhase} 閘門，建議人工介入` }
