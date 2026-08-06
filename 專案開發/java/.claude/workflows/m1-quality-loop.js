export const meta = {
  name: 'm1-quality-loop',
  description: 'M1 對齊品質迭代：跑 golden set → 看 accuracy/false-auto → 提調整建議，直到達北極星（accuracy≥0.98、false-auto≤0.001）',
  phases: [
    { title: 'Evaluate' },
    { title: 'Advise' },
  ],
}

const METRICS = {
  type: 'object',
  properties: {
    accuracy: { type: 'number' },
    falseAutoRate: { type: 'number' },
    autoRate: { type: 'number' },
    regressions: { type: 'array', items: { type: 'string' } },
  },
  required: ['accuracy', 'falseAutoRate'],
}

const MAX_ROUNDS = 5
let round = 0

while (round < MAX_ROUNDS) {
  round++

  phase('Evaluate')
  const m = await agent(
    '執行 M1 golden set 評估（可呼叫專案的評估指令 / 測試標的），' +
    '回報 accuracy、falseAutoRate、autoRate 與退步案例 regressions。',
    { label: `eval#${round}`, phase: 'Evaluate', schema: METRICS }
  )
  log(`round ${round}: accuracy=${m.accuracy} falseAuto=${m.falseAutoRate}`)

  if (m.accuracy >= 0.98 && m.falseAutoRate <= 0.001) {
    return { reached: true, round, metrics: m }
  }

  phase('Advise')
  await agent(
    `目前 accuracy=${m.accuracy}、falseAuto=${m.falseAutoRate}。` +
    `退步案例：${((m.regressions) || []).join('; ') || '無'}。\n` +
    '提出具體調整建議（特徵權重 / 信心門檻 / 別名補強 / facets 補資料），' +
    '**列給人確認，不要自行套用**。',
    { label: `advise#${round}`, phase: 'Advise' }
  )
}

return { reached: false, rounds: round, note: `已達 ${MAX_ROUNDS} 輪上限仍未達北極星，建議人工介入` }
