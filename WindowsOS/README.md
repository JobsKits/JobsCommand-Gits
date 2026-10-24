# `WindowsOS`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行环境](#jobs-toc-heading-2)
- [二、功能与安全边界](#jobs-toc-heading-3)
- [三、平台适配](#jobs-toc-heading-4)
- [四、验证与日志](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本目录按功能平行提供 20 组 `.cmd` + `.ps1` 用户入口。统计依据为功能映射清单与同目录实际入口，时间为 2026-10-23。本仓没有 iOS 模拟器控制动作，因此无需排除此类功能。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行环境 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

使用 [**Windows PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更新版本，推荐直接双击 `.cmd`。普通入口使用 PowerShell 5.1 公共语法，动态代理安装专用入口明确要求 Desktop 5.1。需要 [**Git for Windows**](https://gitforwindows.org/)，远端创建与视频上传另需 [**GitHub CLI**](https://cli.github.com/)。脚本使用 UTF-8 BOM，CMD 使用当前脚本完整路径调用配套 PS1，路径可包含中文、空格和括号。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、功能与安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| Windows 入口 | 用途 |
| --- | --- |
| [【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）](<./【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）/README.md>) | 按登记逐层拉取目标分支最新，恢复本地跟踪分支；默认不提交、不推送。 |
| [【WindowsOS】⏬双击下载SourceTree效率脚本](<./【WindowsOS】⏬双击下载SourceTree效率脚本/README.md>) | 下载或安全快进 SourceTree 脚本库；保留非空目标与已有修改。 |
| [【WindowsOS】♻️双击Git 提交回退](<./【WindowsOS】♻️双击Git 提交回退/README.md>) | 选择上一提交、tag 或 reflog，soft/hard 回退；先创建原 HEAD 恢复分支。 |
| [【WindowsOS】♻️双击恢复误删本地Git已储藏的资料](<./【WindowsOS】♻️双击恢复误删本地Git已储藏的资料/README.md>) | 检查悬空 commit/tree/blob，按选择恢复为独立分支或二进制文件。 |
| [【WindowsOS】♻️批量Git提交（不含推送）](<./【WindowsOS】♻️批量Git提交（不含推送）/README.md>) | 扫描指定目录内 Git 工作树，后代先于父仓逐仓提交；不推送。 |
| [【WindowsOS】♻️检测并转换为子Git](<./【WindowsOS】♻️检测并转换为子Git/README.md>) | 扫描独立嵌套 Git，逐仓预检、备份、登记并使用 Git 官方命令归集元数据。 |
| [【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）](<./【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）/README.md>) | 生成个人 ED25519/RSA4096 密钥、增补 github-personal Host，复制公钥并打开设置页。 |
| [【WindowsOS】⚙️双击生成Github远程仓库URL](<./【WindowsOS】⚙️双击生成Github远程仓库URL/README.md>) | 通过已登录 GitHub CLI 创建 private/public 远端仓库并打开返回 URL。 |
| [【WindowsOS】⬆️Git添加子模块](<./【WindowsOS】⬆️Git添加子模块/README.md>) | 备份旧子模块工作树和关联后，按五仓清单重新建立子模块；不自动提交。 |
| [【WindowsOS】🌐双击配置Git动态代理](<./【WindowsOS】🌐双击配置Git动态代理/README.md>) | 配置当前用户 Git 动态入口；系统代理可达优先、不可达再直连，支持检查与精确恢复。 |
| [【WindowsOS】🎬上传GitHub视频附件](<./【WindowsOS】🎬上传GitHub视频附件/README.md>) | 上传 MP4/MOV/WEBM 到 GitHub 附件并复制 URL；不修改 README、不提交。 |
| [【WindowsOS】🔍Git依据提交日志关键字查找](<./【WindowsOS】🔍Git依据提交日志关键字查找/README.md>) | 按字面关键词搜索全部引用的提交说明，选择后展示提交详情。 |
| [【WindowsOS】🔍Git寻找分支最近的一次原始切点](<./【WindowsOS】🔍Git寻找分支最近的一次原始切点/README.md>) | 选择两个分支，通过 fork-point 或 merge-base 计算最近共同祖先。 |
| [【WindowsOS】🚪双击打开Github.Flutter](<./【WindowsOS】🚪双击打开Github.Flutter/README.md>) | 使用 Windows 默认浏览器打开 Flutter 官方源码仓库。 |
| [【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo](<./【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo/README.md>) | 使用 Windows 默认浏览器打开 JobsOCBaseConfigDemo 仓库。 |
| [【WindowsOS】🚪双击打开Github.JobsOCKit](<./【WindowsOS】🚪双击打开Github.JobsOCKit/README.md>) | 使用 Windows 默认浏览器打开 JobsOCKit 仓库。 |
| [【WindowsOS】🧭更新引用Git父仓到子仓](<./【WindowsOS】🧭更新引用Git父仓到子仓/README.md>) | 依据磁盘现存子仓对齐登记和 gitlink，备份配置与索引，保留源码与远端。 |
| [【WindowsOS】🧮双击统计MD文件的有效行数](<./【WindowsOS】🧮双击统计MD文件的有效行数/README.md>) | 安装 pre-commit 有效行数钩子；保留已有钩子，部分暂存文档停止。 |
| [【WindowsOS】🧹清理Git子仓运行态记录](<./【WindowsOS】🧹清理Git子仓运行态记录/README.md>) | 为登记子仓补运行态忽略规则，并移除运行态索引记录，保留真实文件。 |
| [【WindowsOS】🧾更新gitmodules](<./【WindowsOS】🧾更新gitmodules/README.md>) | 增量登记现有直属独立子仓，保留已有 URL/branch/扩展字段和 gitlink。 |

所有入口先内置说明和回车确认；危险写入要求精确 `YES`。`GitTools.psm1` 只提供公共函数，导入不执行业务；`MarkdownLines.ps1` 由安装后的 Git 钩子调用。`功能映射.json` 是 MacOS/Windows 入口对应关系。动态代理包的 `Scripts/` 自包含，不依赖另一个仓库。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、平台适配 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 子模块默认下载并保持本地跟踪分支；已有独有提交、分叉、非空非仓或未知缓存停止。维护结果留待审查，不自动提交或推送。
- 恢复悬空对象按选择导出，保留原始二进制内容；不直接批量合并全部对象。
- SSH 使用 Windows 原生 OpenSSH 和独立 github-personal Host；不写 macOS Keychain 配置，也不自动更改服务。
- 重建子模块先移动备份旧工作树；已失效元数据/缓存冲突不覆盖，需人工核验。
- `-DryRun` 只支持下载、关联、对齐、转换、批量提交、运行态清理和重建；不对不支持预览的功能偷偷执行业务。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

公共入口日志在系统临时目录；动态代理的审计与精确快照在当前用户 LocalAppData 的 JobsGitNetworkStrategy。当前完成 PowerShell Parser、BOM、文件名、Shell 静态检查及隔离 Git 回归，未操作真实项目索引、认证配置、远端提交或代理安装。Windows 双击与 GUI/服务实机仍待验。隔离回归入口与范围见 [`./Tests/README.md`](./Tests/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
