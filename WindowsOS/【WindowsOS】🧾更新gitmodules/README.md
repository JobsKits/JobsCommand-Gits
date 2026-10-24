# `【WindowsOS】🧾更新gitmodules`

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

增量登记现有直属独立子仓，保留已有 URL/branch/扩展字段和 gitlink。

对应 [MacOS 原入口](<../../MacOS/【MacOS】🧾更新gitmodules.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】🧾更新gitmodules.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】🧾更新gitmodules.ps1'
```

针对目标仓库只读预览，不修改目标配置或索引：

```powershell
& '.\【WindowsOS】🧾更新gitmodules.ps1' `
  -Repository 'D:\Repos\目标仓库' `
  -DryRun
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 保留旧登记，扫描第一层现存独立 Git 与已登记的安全嵌套路径。
- 预检子仓 HEAD/origin、父仓索引冲突、普通文件跟踪冲突、外部元数据与链接工作树；全部通过才展示计划。
- 精确 YES 后备份配置、索引与清单；只补缺 section/URL/gitlink，已有字段和指针原样保留。
- 父子全部已配置 remote 能证明同站同 namespace、子仓同名时才写相对 URL，否则保留明确地址。
- submodule init 和 absorbgitdirs 完成后核验 HEAD 与 .git 指针；不联网、不提交、不推送。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先显示内置自述，回车确认后执行业务；危险步骤再次要求精确 `YES`。外部命令失败返回非零并停止。日志位于系统临时目录 `JobsGit-associate-时间-进程号.log`。

所有路径参数按单独参数传给命令，支持空格、中文和括号；不使用字符串执行。批量扫描跳过 Git 元数据、依赖、产物和重解析点。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
