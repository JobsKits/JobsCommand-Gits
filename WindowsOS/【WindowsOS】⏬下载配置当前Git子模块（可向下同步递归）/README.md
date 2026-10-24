# `【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）`

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

按登记逐层拉取目标分支最新，恢复本地跟踪分支；默认不提交、不推送。

对应 [MacOS 原入口](<../../MacOS/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）.ps1'
```

针对目标仓库只读预览，不修改目标配置或索引：

```powershell
& '.\【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）.ps1' `
  -Repository 'D:\Repos\目标仓库' `
  -DryRun
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 先选择只拉取、维护清单、仅已有、指定子模块或新增地址。默认沿已有登记同步。
- 入口分支要求明确上游；游离入口依据远端默认分支恢复。每层显式 branch 优先，`.` 继承直接父仓分支，缺省读取远端默认分支。
- 逐层显示来源再 fetch，复用已有工作树；首次 clone --no-checkout 先记录真实远端，再检出分支。Gitee 标准 SSH 地址仅在命令进程改为 HTTPS。
- 未提交内容逐仓红字列明；回车外部处理后复检，精确 YES 才舍弃当前仓。独有提交、分叉、未知缓存或非空非仓目录停止，不覆盖。
- 选择递归或仅直属；子仓保持本地跟踪分支。有有效目录过滤器才 restore/verify，缺配置明确跳过，不自动安装。
- 父仓与深层 gitlink 差异留待审查；Windows 入口不自动提交或推送。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先显示内置自述，回车确认后执行业务；危险步骤再次要求精确 `YES`。外部命令失败返回非零并停止。日志位于系统临时目录 `JobsGit-download-时间-进程号.log`。

所有路径参数按单独参数传给命令，支持空格、中文和括号；不使用字符串执行。批量扫描跳过 Git 元数据、依赖、产物和重解析点。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
