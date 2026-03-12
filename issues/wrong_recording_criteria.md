# 臭蟲：錄製守護程序即使螢幕未更改仍建立片段

## 摘要

錄製守護程序持續建立新片段，不論螢幕上是否發生任何視覺更改。這導致過度的儲存空間使用，並產生毫無意義的錄製，不包含任何新資訊。

## 重現步驟

1. 建置並安裝守護程序：`dotnet build src/Tmrc.sln`
2. 開始錄製：`tmrc record`
3. 保持桌面完全閒置（無滑鼠移動、無視窗活動、無游標閃爍）幾分鐘。
4. 停止錄製：`tmrc stop`
5. 檢查寫入 `~/.tmrc/segments/` 的片段。

**預期：** 螢幕靜止時不寫入新片段。
**實際：** 即使螢幕上未發生任何變化，仍以穩定的速率寫入新片段。

## 環境

- 作業系統：Windows 10/11
- .NET：8
- 工具版本：最新 `main` 分支

## 根本原因分析

變更偵測邏輯存在於 `ScreenCapture.ComputeHasEvent()`
（`src/Tmrc.Cli/Capture/ScreenCapture.cs`，第 112–128 行）。

```csharp
long sum = 0;
int step = Math.Max(1, current.Length / 10_000);
for (int i = 0; i < current.Length && sum < _diffThreshold; i += step)
{
    sum += Math.Abs((int)current[i] - (int)_previous[i]);
}

sum = sum * (current.Length / Math.Max(1, step));   // ← 上調
return sum >= _diffThreshold;
```

有兩個複合問題：

### 問題 1 — 提前退出迴圈誇大了上調估計

當 `sum` 達到 `_diffThreshold`（500,000）時迴圈立即中斷。迴圈後，`sum` 乘以 `current.Length / step`（≈ 10,000）。如果迴圈提前退出—因為即使是小的區域變化（游標閃爍、插入符閃爍、動畫系統匣圖示）也會將部分和推到閾值—迴圈後乘法會產生天文數字般的誇大值（例如 500,000 × 10,000 = 5,000,000,000）。閾值比較隨後始終評估為 `true`，即使實際總差異很小，每個後續フレーム也會報告為「事件」。

### 問題 2 — 取樣步驟按位元組對齊，不按像素對齊

`step = current.Length / 10_000` 以 BGRA 緩衝區中的位元組計算（每個像素 4 位元組）。取樣跨度因此不與像素邊界對齐，所以取樣的位元組是 B、G、R 和 A 通道的任意混合。來自 GDI 擷取的 Alpha 通道可能引入一致的非零偏差，將部分和推到提前退出閾值，即使在完全靜止的螢幕上。

## 預期行為

當連續幀的像素內容相同（或低於有意義的視覺變化閾值）時，`ComputeHasEvent()` 應傳回 `false`。只有真正的螢幕活動應產生片段。

## 建議修復方向

- 移除或重新考慮迴圈內的 `sum < _diffThreshold` 提前退出條件。累積完整樣本，然後將原始（非上調或正確上調）和與閾值比較。
- 將取樣步驟對齐到像素邊界（4 的倍數），使 Alpha 位元組的各通道雜訊不會導致虛假差異。
- 考慮僅比較 R、G 和 B 通道（跳過每個像素的位元組索引 3），以排除 GDI 合成引入的任何 Alpha 通道變化。

## 相關檔案

| 檔案 | 相關性 |
|------|-------|
| `src/Tmrc.Cli/Capture/ScreenCapture.cs` | `ComputeHasEvent()` — 幀差異邏輯 |
| `src/Tmrc.Core/Recording/EventSegmenter.cs` | 由 `hasEvent` 驅動的片段開啟/清除邏輯 |

---

# Bug: Recording daemon creates segments even when the screen has not changed

## Summary

The recording daemon continuously creates new segments regardless of whether any
visual change has occurred on screen. This causes excessive storage usage and
produces meaningless recordings that contain no new information.

## Steps to Reproduce

1. Build and install the daemon: `dotnet build src/Tmrc.sln`
2. Start recording: `tmrc record`
3. Leave the desktop completely idle (no mouse movement, no window activity, no
   blinking cursors) for several minutes.
4. Stop recording: `tmrc stop`
5. Inspect the segments written to `~/.tmrc/segments/`.

**Expected:** No new segments are written while the screen is static.
**Actual:** New segments are written at a steady rate even though nothing changed
on screen.

## Environment

- OS: Windows 10/11
- .NET: 8
- Tool version: latest `main` branch

## Root Cause Analysis

The change-detection logic lives in `ScreenCapture.ComputeHasEvent()`
(`src/Tmrc.Cli/Capture/ScreenCapture.cs`, lines 112–128).

```csharp
long sum = 0;
int step = Math.Max(1, current.Length / 10_000);
for (int i = 0; i < current.Length && sum < _diffThreshold; i += step)
{
    sum += Math.Abs((int)current[i] - (int)_previous[i]);
}

sum = sum * (current.Length / Math.Max(1, step));   // ← upscale
return sum >= _diffThreshold;
```

There are two compounding issues:

### Issue 1 — Early-exit loop inflates the upscaled estimate

The loop breaks as soon as `sum` reaches `_diffThreshold` (500 000). After the
loop, `sum` is multiplied by `current.Length / step` (≈ 10 000). If the loop
exits early — because even a small localized change (cursor blink, caret flash,
animated tray icon) drives the partial sum to the threshold — the post-loop
multiplication produces an astronomically inflated value (e.g.
500 000 × 10 000 = 5 000 000 000). The threshold comparison then always evaluates
to `true`, and every subsequent frame is reported as an "event" even if the actual
total difference is small.

### Issue 2 — Sampling step is byte-aligned, not pixel-aligned

`step = current.Length / 10_000` is computed in bytes over a BGRA buffer
(4 bytes per pixel). The sampling stride is therefore not aligned to pixel
boundaries, so the sampled bytes are an arbitrary mix of B, G, R, and A channels.
The alpha channel from GDI captures may introduce a consistent, non-zero bias that
pushes the partial sum past the early-exit threshold even on a perfectly static
screen.

## Expected Behavior

`ComputeHasEvent` should return `false` when the pixel content of consecutive
frames is identical (or below a meaningful visual-change threshold). Only genuine
screen activity should produce segments.

## Suggested Fix Direction

- Remove or rethink the `sum < _diffThreshold` early-exit condition inside the
  loop. Accumulate the full sample, then compare the raw (non-upscaled or
  correctly-upscaled) sum against the threshold.
- Align the sampling step to pixel boundaries (multiples of 4) so that
  per-channel noise from the alpha byte does not contribute spurious differences.
- Consider comparing only the R, G, and B channels (skip byte index 3 of each
  pixel) to exclude any alpha-channel variation introduced by GDI compositing.

## Related Files

| File | Relevance |
|------|-----------|
| `src/Tmrc.Cli/Capture/ScreenCapture.cs` | `ComputeHasEvent()` — frame diff logic |
| `src/Tmrc.Core/Recording/EventSegmenter.cs` | Segment open/flush logic driven by `hasEvent` |
