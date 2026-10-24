# `【WindowsOS】🧮双击统计MD文件的有效行数`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、执行流程](#jobs-toc-heading-3)
- [三、依赖、日志与风险](#jobs-toc-heading-4)
- [四、验证边界](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

安装 pre-commit 有效行数钩子；保留已有钩子，部分暂存文档停止。

对应 [MacOS 原入口](<../../MacOS/【MacOS】🧮双击统计MD文件的有效行数.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】🧮双击统计MD文件的有效行数.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】🧮双击统计MD文件的有效行数.ps1'
```

通过 `-Repository 'D:\Repos\目标仓库'` 指定目标，未指定时提示输入，回车使用入口所属仓库。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 确认目标 Git 工作树，按实际 hooks 路径定位，适配子模块 .git 指针。
- 已有 pre-commit 时停止，保留用户钩子；精确 YES 才安装 sh 转发和 PowerShell 统计脚本。
- 提交时处理已完整暂存且含“当前总行数：0 行”标记的 Markdown，过滤空行、标题和代码围栏行后更新数字。
- 部分暂存或未暂存差异阻断提交，防止钩子把其它正文自动暂存。保留 UTF-8 BOM 状态与原换行。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先显示内置自述，回车确认后执行业务；危险步骤再次要求精确 `YES`。外部命令失败返回非零并停止。日志位于系统临时目录 `JobsGit-hook-时间-进程号.log`。

所有路径参数按单独参数传给命令，支持空格、中文和括号；不使用字符串执行。批量扫描跳过 Git 元数据、依赖、产物和重解析点。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
