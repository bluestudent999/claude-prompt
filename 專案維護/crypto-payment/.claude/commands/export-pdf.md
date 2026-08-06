將 `README.md` 轉換為 PDF，輸出至 `docs/README.pdf`（含 Mermaid 圖表渲染）。

## 執行步驟

1. **環境檢查**
   確認以下工具存在，缺少則輸出安裝指引：
   - `pandoc`（`which pandoc`）
   - `/tmp/mermaid-render/node_modules/.bin/mmdc`（若不存在：`cd /tmp/mermaid-render && npm install @mermaid-js/mermaid-cli`）
   - `/Applications/Google Chrome.app`
   - `scripts/render_mermaid.py`

2. **pandoc：Markdown → HTML**
   ```bash
   pandoc README.md \
     -f markdown+raw_html \
     -t html5 \
     --standalone \
     --syntax-highlighting=none \
     --embed-resources \
     -o docs/README_raw.html
   ```
   - 不加 `--metadata title`（避免與 README 的 H1 產生重複標題）

3. **Mermaid 渲染：code block → inline SVG**
   ```bash
   python3 scripts/render_mermaid.py docs/README_raw.html docs/README.html
   ```
   - 使用 Node.js 25（`/opt/homebrew/bin/node`）+ mermaid-cli 11
   - 渲染 3 張圖（架構圖、存款流程、專案結構）

4. **Chrome headless：HTML → PDF（無頁首頁尾）**
   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
     --headless=new \
     --disable-gpu \
     --no-sandbox \
     --print-to-pdf="docs/README.pdf" \
     --print-to-pdf-no-header \
     --no-pdf-header-footer \
     "file://{絕對路徑}/docs/README.html"
   ```

5. **清理暫存檔**
   ```bash
   rm -f docs/README_raw.html
   ```

6. **輸出結果**
   - 顯示 `docs/README.pdf` 的檔案大小
   - 提示：`open docs/README.pdf` 開啟確認
