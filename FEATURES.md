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
- [x] 左右切换标签时，下一页从竖状态栏下面滑进来（透过竖栏上的玻璃按钮能看到），停下后内容仍避开竖状态栏（[#42](https://github.com/ShionjiART/PiliPlus/pull/42)）。后来修复合上时打开视频再展开，播放器下方的简介变成空白（[#47](https://github.com/ShionjiART/PiliPlus/pull/47)）
- [x] 合上时播放器底部的进度条铺满整行（摄像头只在竖栏顶部，挡不到），下面一排按钮仍避开竖栏，合上全屏也一样（[#35](https://github.com/ShionjiART/PiliPlus/pull/35)）。控件隐藏时的细进度条起初改成避开竖栏（[#24](https://github.com/ShionjiART/PiliPlus/pull/24)），后来改回铺满（[#35](https://github.com/ShionjiART/PiliPlus/pull/35)）
- [x] 合上时播放器的锁定按钮、截图按钮和下面一排按钮也和进度条一样铺到竖栏上，不再空出一截（摄像头只在竖栏顶部，挡不到）；普通 iPhone 横屏时仍避开灵动岛（[#48](https://github.com/ShionjiART/PiliPlus/pull/48)）
- [x] 视频页隐藏时间和 Wi-Fi，内容铺满竖状态栏的位置（合上和展开都是）
- [x] 展开竖屏时视频页也隐藏顶部的时间和 Wi-Fi，播放器铺到屏幕最上面，不再留一条黑边，和合上、横屏时一致（[#52](https://github.com/ShionjiART/PiliPlus/pull/52)）
- [x] 视频页的对话框（播放信息等）在整个屏幕里居中，不再往左上偏：竖状态栏隐藏时不再让开它，上下也留出相同的边距，较高的对话框不会碰到摄像头（[#48](https://github.com/ShionjiART/PiliPlus/pull/48)）
- [x] 展开后视频页右栏加宽，相关视频的 ⋮ 按钮不再被遮住
- [x] 动态流合上时单列、展开时双列，不再因为合上状态启动就一直是单列（[#23](https://github.com/ShionjiART/PiliPlus/pull/23)）
- [x] 保存评论和动态的图片不再比直板手机宽：最多 402pt，和普通 iPhone 一致（[#20](https://github.com/ShionjiART/PiliPlus/pull/20)）
- [x] 旋转或开合时页面不会被重置
- [x] 之前手动打开过「横屏适配」的用户，升级后仍保持打开
- [x] 修复真机合上时启动卡在启动画面
- [x] 视频页偶尔右侧留出空白（时间和 Wi-Fi 没隐藏）：每次都和系统重新同步竖状态栏状态，回到前台时重新确认（[#18](https://github.com/ShionjiART/PiliPlus/pull/18)）
- [x] 修复从相关视频返回后竖状态栏重新出现，以及开合时被盖住的视频页把竖状态栏改回显示；首页上打开大图时系统标签栏也会隐藏（[#57](https://github.com/ShionjiART/PiliPlus/pull/57)）
- [x] 直接打开的页面也避开竖状态栏，修复通讯录页标签栏伸到竖栏下面（[#4](https://github.com/ShionjiART/PiliPlus/pull/4)）
- [x] 修复开启「改用侧边栏」后首页搜索栏和头像消失：iOS 26 起的 iPhone 由系统标签栏负责导航，这个设置不再生效并在设置里置灰（普通 iPhone 也适用）（[#19](https://github.com/ShionjiART/PiliPlus/pull/19)）
- [x] 合上时二级页面在竖状态栏显示返回键；首页等一级页面和视频页不显示，弹窗不影响（[#21](https://github.com/ShionjiART/PiliPlus/pull/21)）。页面左上角的返回键起初保留，后来去掉（[#28](https://github.com/ShionjiART/PiliPlus/pull/28)）
- [x] 一级页面的竖状态栏顶部放头像，以及搜索和私信的组合按钮，私信带未读角标；未登录时不显示私信，头像点了去登录；首页顶部的头像在 Duo 上去掉（[#22](https://github.com/ShionjiART/PiliPlus/pull/22)）
- [x] 视频页的底部弹窗（长按评论的菜单、分享、收藏、缓存、转发、播放器设置等）和页面一样铺满竖状态栏的位置，右边不再留出一条（[#25](https://github.com/ShionjiART/PiliPlus/pull/25)）。后来修复横屏时播放器设置面板、播放信息等弹窗和对话框里的列表整体右移一截：竖状态栏的安全区不再传给弹窗里的内容（[#67](https://github.com/ShionjiART/PiliPlus/pull/67)）
- [x] 动态详情页的点赞、评论、分享、转发放进竖状态栏，带简短的数量（1.2万、1千万、1.2亿）；发评论单独一个按钮放在最下面，代替页面上的悬浮按钮；底部操作栏保留（[#26](https://github.com/ShionjiART/PiliPlus/pull/26)）。后来顺序改为点赞、评论、转发（带数量）、分享（只有图标），按钮变矮，通话时也不会被收进 ⋯ 菜单（[#33](https://github.com/ShionjiART/PiliPlus/pull/33)）
- [x] Duo 上首页顶部的搜索栏、消息按钮和头像那一行去掉（都已在竖状态栏里），分区标签移到最上面（[#27](https://github.com/ShionjiART/PiliPlus/pull/27)）
- [x] 展开竖屏时首页的头像、搜索栏和消息按钮放进顶部状态栏那一行（右边让开时间和 Wi-Fi），和 B 站官方客户端一样；往上滑时这一行连同状态栏一起收起，分区标签移到最上面，往下滑再出现（[#52](https://github.com/ShionjiART/PiliPlus/pull/52)）。后来这一行的位置和给时间、Wi-Fi 让出的宽度改用系统给的值，并修复合上时启动、展开后首页仍是旧样式（[#58](https://github.com/ShionjiART/PiliPlus/pull/58)）。#52 曾让直板 iPhone 首页上滑时顶栏画进灵动岛，已修复（[#60](https://github.com/ShionjiART/PiliPlus/pull/60)）。上下滑动时搜索栏一卡一卡、往回跳的问题也已修复：状态栏收起时不再让整个页面重新排版（[#62](https://github.com/ShionjiART/PiliPlus/pull/62)）
- [x] 展开竖屏时二级页面的标题栏（返回键、标题、按钮）也放进状态栏那一行，右边停在时间左边，和系统设置、App Store 一样；「我的」「动态」顶部那排按钮和分类标签也放进这一行，用户空间、话题、收藏夹等可折叠头部跟着调整（[#59](https://github.com/ShionjiART/PiliPlus/pull/59)）
- [x] 二级页面只保留竖状态栏里的返回键，页面左上角的去掉，标题和左边留出间距；竖状态栏的头像点了弹出账号切换，未登录时去「我的」页面登录（[#28](https://github.com/ShionjiART/PiliPlus/pull/28)）
- [x] 合上时首页、「我的」等页面顶部不再多出一段空白：状态栏在竖栏里时，不再给屏幕顶部留位置（[#31](https://github.com/ShionjiART/PiliPlus/pull/31)）
- [x] 在账号切换里选了匿名后，点竖栏头像仍弹出账号切换，可以切回原账号；一个账号都没有时才去「我的」登录。竖栏头像图片放大，留白收窄（[#32](https://github.com/ShionjiART/PiliPlus/pull/32)）
- [x] 竖栏头像加载失败后会重新加载，不再一直显示占位图；切换底部标签时页面不再闪一下（[#55](https://github.com/ShionjiART/PiliPlus/pull/55)）
- [x] 动态详情页顶部不再空出一条：作者直接在最上面，往上滑过作者后顶栏才浮出来，标签栏停在顶栏下面（[#33](https://github.com/ShionjiART/PiliPlus/pull/33)）
- [x] 音乐详情页顶部也不再空出一条：歌曲卡片直接在最上面，往上滑过后顶栏才浮出来，评论栏停在顶栏下面（[#41](https://github.com/ShionjiART/PiliPlus/pull/41)）
- [x] 动态详情和音乐页的顶栏在浮动和普通之间切换时，不再重建页面、丢失滚动位置（[#56](https://github.com/ShionjiART/PiliPlus/pull/56)）
- [x] 合上时视频页暂停后往上滑、播放器收成一条工具栏，右边的 ⋮ 不再被摄像头挡住：按钮和播放器控件一样避开左右安全区（[#40](https://github.com/ShionjiART/PiliPlus/pull/40)）
- [x] 移植 [Stasert](https://github.com/Stasert) 的竖栏导航等功能：能用的都已移植，其余几项决定不移植，逐项记录见 [#2](https://github.com/ShionjiART/PiliPlus/issues/2)

## 播放

- [x] iOS 支持 AV1 硬解，更省电、发热更小；不支持的设备自动用软解（[#6](https://github.com/ShionjiART/PiliPlus/pull/6)）
- [x] iOS 锁屏或切到后台再回来后，自动恢复硬解（[#5](https://github.com/ShionjiART/PiliPlus/pull/5)）
- [x] iOS 上 HDR 和杜比视界视频改用系统播放器播放，画面和官方客户端一致，不再过曝（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 可选所有视频都用系统播放器（实验性）（[#12](https://github.com/ShionjiART/PiliPlus/pull/12)）
- [x] 系统播放器支持画中画、截图和字幕（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 修复部分 HDR 真彩、杜比视界视频无法用系统播放器播放，或在播放信息里显示成 SDR（[#13](https://github.com/ShionjiART/PiliPlus/pull/13)）
- [x] 修复 CDN 返回不完整的数据时系统播放器让 App 闪退，现在会改用内置播放器（[#55](https://github.com/ShionjiART/PiliPlus/pull/55)）
- [x] 修复部分杜比视界 Profile 5 视频用系统播放器播放失败、退回内置播放器后颜色错误；视频文件的色彩信息和码流不一致、AV1 HDR 没有色彩信息时，不再播放失败或被当成普通画质；解析异常数据时不再闪退（[#63](https://github.com/ShionjiART/PiliPlus/pull/63)）
- [x] 离线缓存的 HDR、杜比视界视频也用系统播放器播放（[#36](https://github.com/ShionjiART/PiliPlus/pull/36)）
- [x] 「所有视频」模式下尽量都用系统播放器（包括普通画质的 HEVC 和离线缓存）；系统播放器加载超时或没有画面时自动切回内置播放器（[#38](https://github.com/ShionjiART/PiliPlus/pull/38)）
- [x] 修复系统播放器超过 2 倍速时一直显示「加载中」、一卡一卡：使用系统播放器时倍速最高 2 倍，倍速菜单和长按倍速都封顶 2 倍（[#49](https://github.com/ShionjiART/PiliPlus/pull/49)）
- [x] 修复系统播放器快速切换分集或画质时，悄悄改用内置播放器或一直转圈；系统播放器出错退回内置播放器时，保持原来的播放或暂停状态；切回内置播放器后恢复 2 倍以上的倍速；缓冲卡住时进度不再往前走（[#54](https://github.com/ShionjiART/PiliPlus/pull/54)）
- [x] 系统播放器：离线视频倍速最高 3 倍；「所有视频」模式下的普通画质视频，选了系统播放器达不到的倍速或开了超分辨率时改用内置播放器；「缓冲时长」对系统播放器生效；播放信息显示码流的实际格式和屏幕的 HDR 余量（[#64](https://github.com/ShionjiART/PiliPlus/pull/64)）
- [x] 内置播放器播 HDR：杜比视界 8.4 不再过曝，Profile 5 自动改放 HDR 真彩；新增「内置播放器 HDR 色调映射」设置（[#64](https://github.com/ShionjiART/PiliPlus/pull/64)）
- [x] 修复打开视频偶尔整块黑屏或有声音没画面（原版也有，见 [bggRGjQaUbCoE/PiliPlus#3246](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3246)）：被盖住或已关闭的视频页不再抢用播放器，初始化失败时显示封面可点击重试（[#16](https://github.com/ShionjiART/PiliPlus/pull/16)）

## 离线缓存

- [x] 修复网络不好时缓存「瞬间完成」但视频不完整：下载完核对文件大小，断了自动续传，续传多次仍不完整就标为失败；续传时换了视频流会从头下载（[#15](https://github.com/ShionjiART/PiliPlus/pull/15)）
- [x] 修复存储空间满等写入出错时，残缺的缓存仍显示「已完成」：现在照常续传，重试几次仍失败就标为失败（[#53](https://github.com/ShionjiART/PiliPlus/pull/53)）

## 投屏

- [x] 修复 iOS 投屏一直「搜索设备失败」、不弹局域网授权（[#9](https://github.com/ShionjiART/PiliPlus/pull/9)）
- [x] 支持 AirPlay 投屏，和现有的局域网投屏并存（[#14](https://github.com/ShionjiART/PiliPlus/pull/14)）
- [x] AirPlay 投原画质：4K 和 HDR 真彩都能投（杜比视界能不能投还没确认），选好设备前手机不预先下载，投不出来时自动退回原来的方式（[#65](https://github.com/ShionjiART/PiliPlus/pull/65)）
- [x] Android 只开流量时，投屏搜索不再对运营商内网扫描（[#53](https://github.com/ShionjiART/PiliPlus/pull/53)）

## 关于和更新

- [x] 关于页的源码、提交、问题反馈链接和检查更新改用本仓库：不再提示下载没有 iPhone Duo 适配的原版安装包；刚装上的版本也不会被当成有新版本（[#44](https://github.com/ShionjiART/PiliPlus/pull/44)）
- [x] iOS 检查更新只打开安装包，不会打开同名的 .sha256 校验文件；没有当前平台的安装包时不提示更新（[#53](https://github.com/ShionjiART/PiliPlus/pull/53)）
- [x] iOS 版可以从 AltStore 或 SideStore 安装和更新：在 iPhone 上打开 <https://shionjiart.github.io/PiliPlus/>，点「添加到 AltStore」或「添加到 SideStore」，也可以手动添加源 `https://shionjiart.github.io/PiliPlus/altstore.json`。每次发布新版本后源会自动更新（[#68](https://github.com/ShionjiART/PiliPlus/pull/68)）。源和 App 在 AltStore 里显示为「PiliPlus (sssakuya)」，和原版区分开（[#69](https://github.com/ShionjiART/PiliPlus/pull/69)）

## 已知问题

暂不处理，记录在这里。

- 合上横屏、竖状态栏在右边时，摄像头在竖栏下端（屏幕右下角），会压住播放器进度条的末端，并紧挨着右下角的「退出全屏」按钮。竖栏在左边时摄像头在左上角，不受影响。进度条和底部按钮铺到竖栏上时只考虑了摄像头在竖栏上端的情况（[#35](https://github.com/ShionjiART/PiliPlus/pull/35) 和 [#48](https://github.com/ShionjiART/PiliPlus/pull/48)）

## 开发

- [x] 每次提 PR 时自动检查代码并运行测试（[#8](https://github.com/ShionjiART/PiliPlus/pull/8)）
- [x] 修复原版中 2 个一直失败的测试（[#7](https://github.com/ShionjiART/PiliPlus/pull/7)）
- [x] 维护指南 [`CLAUDE.md`](CLAUDE.md)（[#3](https://github.com/ShionjiART/PiliPlus/pull/3)、[#10](https://github.com/ShionjiART/PiliPlus/pull/10)）

## 已提交给原版

- 切回前台后自动恢复硬解：[bggRGjQaUbCoE/PiliPlus#3584](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3584)
- iOS 支持 AV1 硬解（询问是否采用）：[bggRGjQaUbCoE/PiliPlus#3585](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3585)
