為指定的 Service 類別生成對應的 JUnit 5 測試檔案，風格與現有測試保持一致。

目標類別：`$ARGUMENTS`（例如 `DepositService` 或 `com.lion.crypto.service.user.DepositService`）

## 執行步驟

1. **定位目標類別**
   - 在 `crypto-payment-service/src/main/java/` 下搜尋 `$ARGUMENTS.java`
   - 若找到多個候選，列出讓使用者確認
   - 若找不到，停下說明

2. **讀取類別資訊**
   - 建構子參數（即所有依賴 bean，for mock 清單）
   - 所有 `public` 方法的簽名（名稱、入參型別、回傳型別、throws）
   - 類別上的注釋（`@Service`、`@Transactional` 等）

3. **參考現有測試風格**
   讀取 `crypto-payment-service/src/test/java/` 中現有測試，擷取：
   - import 慣例
   - mock 注入方式（constructor injection）
   - assertion 風格（AssertJ）
   - 命名規則（`should_*_when_*`）

4. **生成測試檔案**

   測試路徑：對應 `src/test/java/` 下的同套件路徑，檔名為 `{ClassName}Test.java`

   每個 `public` 方法生成：
   - **Happy path**：mock 回傳正常值，驗證回傳結果
   - **Exception case**：若有 `throws` 或明顯防禦邏輯（null check、狀態判斷），加入對應測試

   **固定 boilerplate**：
   ```java
   @ExtendWith(MockitoExtension.class)
   @Slf4j
   class {ClassName}Test {

       // 依建構子順序 mock 所有依賴
       @Mock private XxxRepository xxxRepository;
       // ...

       private {ClassName} {classNameCamelCase};

       @BeforeEach
       void setUp() {
           {classNameCamelCase} = new {ClassName}(/* mock 依賴 */);
       }
       // ...
   }
   ```

5. **暫停確認**
   - 顯示完整的生成測試程式碼
   - **等待使用者確認後再寫入檔案**
   - 確認後寫入，並執行 `mvn test -pl crypto-payment-service -Dtest={ClassName}Test` 驗證編譯通過
