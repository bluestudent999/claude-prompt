export const meta = {
  name: 'scaffold-modules',
  description: '平行 scaffold SDRP Phase 0 的 Spring Modulith 模組骨架，最後跑架構測試驗證邊界',
  phases: [
    { title: 'Scaffold' },
    { title: 'Verify' },
  ],
}

// Phase 0 要建立的模組（邊界以 package 表達；不實作業務邏輯）
const MODULES = ['ingestion', 'reference', 'alignment', 'decision', 'hitl']

phase('Scaffold')
// 各模組建立在不同的 package 路徑，彼此不衝突，故不需 worktree 隔離
await parallel(MODULES.map((m) => () =>
  agent(
    `為 SDRP 建立 Spring Modulith 模組 '${m}' 的骨架：` +
    `在 src/main/java/com/sdrp/${m}/ 下建立 domain(L2)、application(L3)、infrastructure(L1)、interfaces(L4) 四層 package，` +
    `並加 package-info.java 標註 @org.springframework.modulith.ApplicationModule。不要實作任何業務邏輯。回報建立的檔案清單。`,
    { label: `scaffold:${m}`, phase: 'Scaffold' }
  )
))

phase('Verify')
const result = await agent(
  '於 repo 根目錄執行 `./mvnw -q test -Dgroups=architecture`（ApplicationModules.verify() + ArchUnit），' +
  '回報是否綠燈，以及任何模組/分層邊界違規。',
  { label: 'arch-verify', phase: 'Verify' }
)
return result
