export const meta = {
  name: 'upgrade-sweep',
  description: '多模組升級面平行盤點：每個模組獨立掃 javax 使用面 / 棄用 API / 依賴版本 / 設定屬性 / 換庫項，彙整成升級盤點報告',
  phases: [
    { title: 'Sweep' },
    { title: 'Aggregate' },
  ],
}

// args：要盤點的模組目錄清單，例 ["cx-app-service", "cx-single-wallet-service"]
// 未提供則預設整個 reactor 視為單一目標
const MODULES = Array.isArray(args) && args.length ? args : ['.']

const INVENTORY = {
  type: 'object',
  properties: {
    module: { type: 'string' },
    jakartaEE: { type: 'array', items: { type: 'string' }, description: '需遷 jakarta 的 javax 類別分布（servlet/persistence/validation 各幾檔）' },
    seWhitelist: { type: 'array', items: { type: 'string' }, description: 'Java SE 白名單 javax（不遷）' },
    deprecatedApis: { type: 'array', items: { type: 'string' }, description: '命中的棄用/移除 API（對應 breaking-changes 編號）' },
    riskyDeps: { type: 'array', items: { type: 'string' }, description: '高風險依賴現況版本（spring-boot/cloud/mybatis/springfox/hibernate/lombok...）' },
    configProps: { type: 'array', items: { type: 'string' }, description: '需遷移的 Boot 3 設定屬性' },
    replaceLibs: { type: 'array', items: { type: 'string' }, description: '需換庫而非升版的項（springfox→springdoc 等）' },
    jvmFlags: { type: 'array', items: { type: 'string' }, description: '已移除的 GC/JVM 旗標' },
    riskTier: { type: 'string', enum: ['U1', 'U2', 'U3'], description: '升級風險層初判' },
  },
  required: ['module', 'jakartaEE', 'deprecatedApis', 'riskyDeps', 'replaceLibs', 'riskTier'],
}

const SWEEP_PROMPT = (m) => `
你是升級盤點員。針對模組目錄「${m}」做升級面盤點，**只回結論不回原始 grep 行**。
依 .claude/skills/upgrade-inventory/SKILL.md 的六面盤點：

1. javax 使用面：grep "import javax\\." 後，用 .claude/rules/jakarta-migration.md §1 白名單分出「EE 需遷」vs「SE 不遷」，各列分類與檔數。
2. 棄用/移除 API：grep WebSecurityConfigurerAdapter / authorizeRequests / antMatchers / javax.xml.bind / finalize() 等，對應 breaking-changes.md 編號。
3. 高風險依賴現況：mvn dependency:tree 抓 spring-boot/cloud/mybatis/hibernate/springfox/springdoc/shardingsphere/lombok/flyway/validator 的現況版本。
4. 設定屬性：grep spring.redis / pathmatch / EnableAutoConfiguration 等需遷移項。
5. 換庫項：grep springfox / io.swagger.annotations / sleuth，標需換庫的。
6. JVM/GC：grep UseConcMarkSweepGC / UseParNewGC。

最後依命中情況初判風險層：命中 Security 5→6 / Hibernate 5→6 / 換庫 → U1；純 jakarta+設定遷移 → U2；純依賴 bump → U3。
回傳結構化盤點結果。`

const results = await parallel(
  MODULES.map((m) => () =>
    agent(SWEEP_PROMPT(m), { label: `sweep:${m}`, phase: 'Sweep', schema: INVENTORY, agentType: 'Explore' })
  )
)

const inventories = results.filter(Boolean)

// 彙整：產出整體盤點摘要 + 跨模組最高風險層
const summary = await agent(
  `以下是各模組的升級盤點結果（JSON）。彙整成一份 upgrade/inventory.md 草稿內容：\n` +
  `1. 跨模組總覽表（每模組：EE需遷檔數 / 命中 breaking-change / 風險層）\n` +
  `2. 全專案最高風險層（取各模組最高）\n` +
  `3. 換庫項彙整（需列 OQ 給 user 的）\n` +
  `4. 建議的升級階段順序（對照 upgrade-workflow.md Phase A-E）\n\n` +
  JSON.stringify(inventories, null, 2),
  { label: 'aggregate', phase: 'Aggregate' }
)

return { inventories, summary }
