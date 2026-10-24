# `【WindowsOS】🧭更新引用Git父仓到子仓`

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

依据磁盘现存子仓对齐登记和 gitlink，备份配置与索引，保留源码与远端。

对应 [MacOS 原入口](<../../MacOS/【MacOS】🧭更新引用Git父仓%3D＞子仓.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】🧭更新引用Git父仓到子仓.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】🧭更新引用Git父仓到子仓.ps1'
```

针对目标仓库只读预览，不修改目标配置或索引：

```powershell
& '.\【WindowsOS】🧭更新引用Git父仓到子仓.ps1' `
  -Repository 'D:\Repos\目标仓库' `
  -DryRun
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 扫描第一层真实子 Git，并保留已登记的安全嵌套子 Git。
- 预检元数据归属、冲突及 .gitmodules 暂存边界；展示将移除的暂缺登记与 gitlink。
- 精确 YES 后备份配置/索引/清单，保留仍存在条目的 URL、branch 与扩展字段，更新当前 HEAD gitlink，再使用 Git 官方命令归集元数据。
- 保留子仓源码、分支和真实 origin；Windows 版对外部元数据、已失效 core.worktree、无法证明的改名保守停止，先人工修复再重试，不猜归属。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先显示内置自述，回车确认后执行业务；危险步骤再次要求精确 `YES`。外部命令失败返回非零并停止。日志位于系统临时目录 `JobsGit-align-时间-进程号.log`。

所有路径参数按单独参数传给命令，支持空格、中文和括号；不使用字符串执行。批量扫描跳过 Git 元数据、依赖、产物和重解析点。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
