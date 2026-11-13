# 功能清单

这里列出本维护版相对 [原版 PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 新增的功能和修复。

- [x] 已完成，并已合入 `release`
- [ ] 进行中或计划中

原版本身的功能见 [README](README.md)。

## iPhone Duo 适配

第一版适配已冻结为 [`iphone-duo-v1`](https://github.com/ShionjiART/PiliPlus/releases/tag/iphone-duo-v1)。

- [x] 合上和展开时自动切换布局，旋转和开合都会跟着调整
- [x] 首页、动态、我的使用系统原生的 Liquid Glass 标签栏，并放进竖状态栏
- [x] 页面、播放器控件和直播间都避开竖状态栏
- [x] 视频页隐藏时间和 Wi-Fi，内容铺满竖状态栏的位置（合上和展开都是）
- [x] 展开后视频页右栏加宽，相关视频的 ⋮ 按钮不再被遮住
- [x] 保存评论和动态的图片不再比直板手机宽：最多 402pt，和普通 iPhone 一致（[#20](https://github.com/ShionjiART/PiliPlus/pull/20)）
- [x] 旋转或开合时页面不会被重置
- [x] 之前手动打开过「横屏适配」的用户，升级后仍保持打开
- [x] 修复真机合上时启动卡在启动画面
- [x] 直接打开的页面也避开竖状态栏，修复通讯录页标签栏伸到竖栏下面（[#4](https://github.com/ShionjiART/PiliPlus/pull/4)）
- [ ] 移植 [@Stasert](https://github.com/Stasert) 的竖栏导航等功能，进度见 [#2](https://github.com/ShionjiART/PiliPlus/issues/2)

## 播放

- [x] iOS 支持 AV1 硬解，更省电、发热更小；不支持的设备自动用软解（[#6](https://github.com/ShionjiART/PiliPlus/pull/6)）
- [x] iOS 锁屏或切到后台再回来后，自动恢复硬解（[#5](https://github.com/ShionjiART/PiliPlus/pull/5)）
- [x] iOS 上 HDR 和杜比视界视频改用系统播放器播放，画面和官方客户端一致，不再过曝（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 可选所有视频都用系统播放器（实验性）（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 系统播放器支持画中画、截图和字幕（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 修复部分 HDR 真彩、杜比视界视频无法用系统播放器播放，或在播放信息里显示成 SDR（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 修复打开视频偶尔整块黑屏或有声音没画面（原版也有，见 [bggRGjQaUbCoE/PiliPlus#3246](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3246)）：被盖住或已关闭的视频页不再抢用播放器，初始化失败时显示封面可点击重试（[#16](https://github.com/ShionjiART/PiliPlus/pull/16)）

## 离线缓存

- [x] 修复网络不好时缓存「瞬间完成」但视频不完整：下载完核对文件大小，断了自动续传，续传多次仍不完整就标为失败；续传时换了视频流会从头下载（[#15](https://github.com/ShionjiART/PiliPlus/pull/15)）

## 投屏

- [x] 修复 iOS 投屏一直「搜索设备失败」、不弹局域网授权（[#9](https://github.com/ShionjiART/PiliPlus/pull/9)）
- [x] 支持 AirPlay 投屏，和现有的局域网投屏并存（[#14](https://github.com/ShionjiART/PiliPlus/pull/14)）

## 开发

- [x] 每次提 PR 时自动检查代码并运行测试（[#8](https://github.com/ShionjiART/PiliPlus/pull/8)）
- [x] 修复原版中 2 个一直失败的测试（[#7](https://github.com/ShionjiART/PiliPlus/pull/7)）
- [x] 维护指南 [`CLAUDE.md`](CLAUDE.md)（[#3](https://github.com/ShionjiART/PiliPlus/pull/3)、[#10](https://github.com/ShionjiART/PiliPlus/pull/10)）

## 已提交给原版

- 切回前台后自动恢复硬解：[bggRGjQaUbCoE/PiliPlus#3584](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3584)
- iOS 支持 AV1 硬解（询问是否采用）：[bggRGjQaUbCoE/PiliPlus#3585](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3585)
