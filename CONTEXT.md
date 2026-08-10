# NasMon — 文件预览流式传输

NasMon 是一个 Synology NAS 管理 iOS App，当前版本支持仪表盘监控、文件管理器、视频/音频播放器和文件预览。此上下文记录**预览流式传输**的领域模型和决策。

## Language

**Preview Category（预览分类）**:
对 NAS 文件的预览显示方式的分类。包括 image、pdf、text、video、audio、quickLook 和 unsupported。
_Avoid_: preview type, file category

**Preview Manager（预览管理器）**:
负责获取可预览本地文件副本的协调层。职责：缓存检查 → 获取 → 返回本地 URL。不处理 UI 状态，也不决定使用哪个预览表面。
_Avoid_: download manager, file fetcher

**Preview Cache（预览缓存）**:
存储在 `Caches/PreviewCache/` 目录下的本地文件缓存，通过文件路径的稳定哈希来建立映射关系。

**File Station Download API（文件站下载 API）**:
Synology DSM 的 `/webapi/entry.cgi` 端点，使用 `SYNO.FileStation.Download` API 和 `mode=download` 参数从 NAS 获取文件内容。
_Avoid_: download endpoint

**WebDAV Server（WebDAV 服务）**:
Synology NAS 上的 WebDAV 服务，支持原生 HTTP Range 请求，可作为一种传输通道获取文件字节。

**Transport Channel（传输通道）**:
获取文件字节的通道。File Station Download API 是主通道，WebDAV 服务是可选的增强通道。
_Avoid_: download method, fetcher

**Preview Surface（预览表面）**:
呈现已取得预览内容并负责显示、滚动和交互行为的 UI 边界——例如图片查看器、PDFKit、Runestone 和 QuickLook。它不负责文件获取、传输或缓存。
_Avoid_: previewer, preview UI

**Preview Chrome（预览框架）**:
包围 Preview Surface 的共享导航与操作界面。PDF 与 Code Preview 通过全屏 cover 进入，并使用显式返回按钮退出；文件获取流程不参与 presentation 决策。
_Avoid_: preview toolbar, modal preview

**Immersive Preview（沉浸预览）**:
用户点击 Preview Surface 可切换 Preview Chrome 的显示与隐藏；切换只改变界面框架的可见性，不改变或跳转当前阅读位置。
_Avoid_: scroll-triggered chrome, permanently visible chrome

**Preview Session（预览会话）**:
用户从文件列表进入单个文件预览，直到返回文件列表的连续阅读期间。阅读位置在该期间内跨 Chrome 切换、视口变化和渐进刷新保持；退出后不承诺再次打开时恢复位置。
_Avoid_: persisted reading history, cross-session resume

**Preview Interaction Priority（预览交互优先级）**:
Preview Surface 的语义交互优先于 Preview Chrome 切换：PDF 链接与 annotation、文本选择、缩放、拖动和滚动先处理，只有未被内容消费的单击才切换 Chrome。
_Avoid_: global tap interception, gesture-triggered chrome toggle

**Preview Viewport（预览视口）**:
当前设备和方向下未被 Preview Chrome 或系统区域遮挡、可用于阅读内容的可见区域。其边界必须随设备和窗口变化自适应，而不是由固定的横竖屏数值定义。
_Avoid_: fixed top inset, orientation constant

**Preview Scroll Clearance（预览滚动净空）**:
Preview Surface 背景可以延伸至屏幕边缘，但文档首尾必须能够滚动到系统遮挡区域之外并完整可见。首尾净空属于可滚动范围而不属于文档内容，并随实际 Preview Viewport 自适应；Chrome 隐藏时不改变当前阅读位置。
_Avoid_: permanent safe-area strip, fixed scroll padding, document-owned spacer

**Code Preview（代码预览）**:
Text Preview Surface 的只读源码查阅体验，保持类似 VS Code 的行号、语法高亮、文本选择和复制能力，但不提供编辑能力，也不退化为普通文档排版。
_Avoid_: plain-text document preview, text editor

**Adaptive Preview Appearance（自适应预览外观）**:
Preview Chrome 和 Code Preview 跟随系统浅色或深色外观，代码画布、行号与语法颜色作为统一主题切换。PDF 画布跟随系统外观，但不改写 PDF 页面自身颜色。
_Avoid_: forced-dark code preview, preview-specific theme preference

**Accessible Preview（无障碍预览）**:
Preview Chrome 的文件信息、传输状态和操作具有明确的辅助功能语义。Code Preview 跟随系统文字大小，包括辅助功能字号；重新排版时保持源码位置，行号作为上下文而不是独立的重复焦点。减少动态效果开启时，Chrome 状态变化不使用位移或缩放。PDF 保留其原生文档无障碍能力。
_Avoid_: fixed code font size, unlabeled preview action, individually focused line number, mandatory motion

**Wrapped Code Preview（折行代码预览）**:
超过 Preview Viewport 宽度的源码行按当前视口自动软换行，不提供水平滚动；同一源码行的所有视觉行共享一个源码行号。视口变化时重新折行并保持当前源码位置。
_Avoid_: horizontal code scrolling, fixed-width code canvas

**Continuous Document Preview（连续文档预览）**:
PDF 页面按单页宽度纵向连续排列，横竖屏使用相同的阅读方向，并支持缩放。视口变化时应保持当前页和页内阅读位置。
_Avoid_: horizontal paging, orientation-dependent paging

**Preview Transfer Status（预览传输状态）**:
Preview Chrome 中与文件名并列的临时状态，表示预览内容仍在到达；可计算总量时显示进度，否则显示不定进度。它随 Preview Chrome 一起隐藏，并在传输完成后消失。
_Avoid_: content-overlay progress bar, persistent download banner

**Preview Share（预览分享）**:
通过系统分享界面导出已经完整到达的本地预览文件；内容仍在渐进到达时不可用，也不会为了分享启动另一套获取流程。
_Avoid_: partial-file share, preview-specific download

**Preview Content State（预览内容状态）**:
Preview Surface 尚不能呈现内容或无法呈现内容时的明确反馈。初始等待使用居中的系统加载指示；可呈现渐进内容后，由 Preview Transfer Status 接续反馈。空文件、无法解码的文本和损坏的 PDF 使用居中的说明与可用的重试操作；这些状态下 Preview Chrome 保持可见。
_Avoid_: blank loading canvas, silent failure, chrome-hidden error

**Streaming Preview（流式预览）**:
不等待完整下载即可显示或部分显示文件内容的机制，与当前"先完整下载再显示"的模式相对。
_Avoid_: partial download, chunk loading

**Progressive Rendering（渐进渲染）**:
非媒体预览中"数据到达即显示"的渲染方式——PDF 先出首页、文本边下载边浏览、图片边下载边显示等。
_Avoid_: incremental loading, streaming UI

**Stable Progressive Reading（稳定渐进阅读）**:
渐进内容刷新时，Preview Surface 保持用户当前的源码位置或 PDF 页内位置；新增字节不会触发自动滚动，即使用户先前位于已到达内容的末尾。预览是文档阅读体验，不承担实时日志跟随职责。
_Avoid_: tail-following preview, progress-triggered scroll, refresh-to-top

**Last Valid Preview（最后有效预览）**:
渐进文件暂时无法解析时采用的内容状态。首次成功呈现前保持加载反馈；成功呈现后，后续临时解析失败保留最近一次有效内容并等待更多字节。只有完整文件仍无法呈现时才进入错误状态。
_Avoid_: transient corruption error, blank-on-refresh, partial-file failure

**Resumable Cache（可续传缓存）**:
已到达的文件字节落盘保存、并支持从上次位置继续获取的缓存形态，是 Preview Cache 的一种条目。
_Avoid_: partial file, chunk cache

**Byte-Offset Resume（字节级续传）**:
从上次中断的字节偏移处继续获取文件的能力，依赖传输通道支持 Range 请求。
_Avoid_: true resume, range resume

**Session Resume（会话内续传）**:
在同一预览会话内暂停/恢复下载任务的能力；App 重启后不保证跨会话继续。
_Avoid_: task resume

**Fake Seek（伪跳转）**:
在传输通道不支持 Range 时，通过从头重新流式获取并丢弃前缀字节，将读取位置推进到目标字节的定位机制。
_Avoid_: simulated seek, seek workaround
