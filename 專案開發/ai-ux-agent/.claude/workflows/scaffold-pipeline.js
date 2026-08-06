export const meta = {
  name: 'scaffold-pipeline',
  description: '平行 scaffold AI UX Platform 的核心管線階段骨架（Core-Port-Adapter 分層），最後跑架構檢查驗證邊界',
  phases: [
    { title: 'Scaffold' },
    { title: 'Verify' },
  ],
}

// 核心管線階段（骨架先行，不實作業務邏輯）。
// 依賴反轉：需外部技術者定義 Port，Adapter 放 Infrastructure。
const STAGES = [
  { name: 'browser',     note: 'Browser Control：定義 BrowserPort（開站/導航/互動/擷取），Playwright Adapter + BrowserStub。' },
  { name: 'observation', note: 'Observation：Observation 模型（E1 僅 Screenshot+DOM）+ 證據落地磁碟。' },
  { name: 'reasoning',   note: 'Reasoning：定義 InferencePort（雲端/本地/備援可設定），Adapter + InferenceStub；推理須引用 Observation。' },
  { name: 'evaluation',  note: 'UX Evaluation：Issue 模型（Severity Enum + 四欄位）與 UX Rule；每個 Issue 必連結真實 Observation。' },
  { name: 'report',      note: 'Reporting：Report 模型（E1 五要件）+ ReportSinkPort（落地可設定資料夾 reports/YYYY-MM-DD/，E1 Markdown）。' },
]

phase('Scaffold')
await parallel(STAGES.map((s) => () =>
  agent(
    `為 AI UX Audit Platform 建立管線階段 '${s.name}' 的骨架：${s.note}\n` +
    `遵循 Core-Port-Adapter 分層：純模型/規則放 Core（不 import Playwright/LLM SDK/HTTP/檔案 I/O），` +
    `外部技術經 Port，Adapter 放 Infrastructure 並補 Stub。不要實作任何業務邏輯。回報建立的檔案清單。`,
    { label: `scaffold:${s.name}`, phase: 'Scaffold' }
  )
))

phase('Verify')
const result = await agent(
  '執行架構守門檢查（若有 `pytest -q -m architecture` 則跑；並靜態掃 Core 是否被 Playwright/LLM SDK/HTTP/檔案 I/O 污染、外部相依是否都走 Port），' +
  '回報是否 PASS 以及任何管線/分層邊界違規。',
  { label: 'arch-verify', phase: 'Verify' }
)
return result
