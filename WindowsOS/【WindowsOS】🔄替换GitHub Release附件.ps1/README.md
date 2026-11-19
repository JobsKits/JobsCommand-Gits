# Windows Release 附件替换入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、依赖与运行](#run)
- [二、交互、文件范围与产物](#safety)
- [三、验证边界](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

最低支持系统：**Windows 10 + Windows PowerShell 5.1**。Windows 11 ARM64 虚拟机验证待完成；不支持以 XP、Server 2003、Windows 7 或 8.1 作为当前运行基线。完整功能、安全机制和备份恢复见 [上级 README](../README.md)。

| 文件 | 职责 |
| --- | --- |
| [【WindowsOS】🔄替换GitHub Release附件.cmd](<./【WindowsOS】🔄替换GitHub Release附件.cmd>) | 双击入口，透传参数，显示退出码；未设置 `JOBS_NO_PAUSE` 时暂停。 |
| [【WindowsOS】🔄替换GitHub Release附件.ps1](<./【WindowsOS】🔄替换GitHub Release附件.ps1>) | 完整业务实现，也可由 Windows PowerShell 5.1 或已安装的 PowerShell 7 直接运行。 |

两份同名入口放在同一目录。`.ps1` 使用 UTF-8 BOM；`.cmd` 使用 ASCII / CRLF，先关闭继承的延迟展开，再通过 `%~dpn0.ps1` 定位同名脚本，保留路径和参数中的中文、emoji 及 `!`。脚本不修改用户或系统全局执行策略。

## 一、<span id="run">依赖与运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

预先安装并加入 `PATH`：[Git](https://git-scm.com/download/win)、[GitHub CLI](https://cli.github.com/) 和 [fzf](https://github.com/junegunn/fzf/releases)。使用系统兼容的工具发行包；Windows 不依赖 jq。缺失时脚本给出官方入口并停止，不自动安装。先完成 `gh auth login --hostname github.com`，账号须有仓库写权限。

双击 `.cmd`，或在本目录 PowerShell 中运行。两个位置参数可同时省略，改为交互选择：

```powershell
& '.\【WindowsOS】🔄替换GitHub Release附件.cmd' `
  main `
  v1.0.0 `
  --repo-dir '..\..\目标仓库' `
  --source-dir '..\..\目标仓库\Releases\v1.0.0'
```

目录为示例，换成实际已有目录；入口保持当前工作目录，参数中的相对路径也相对该目录解析。直接只读查看帮助，不产生日志且不额外暂停：

```powershell
powershell.exe `
  -NoLogo `
  -NoProfile `
  -ExecutionPolicy Bypass `
  -File '.\【WindowsOS】🔄替换GitHub Release附件.ps1' `
  --help
```

`.cmd` 仅为本次 PowerShell 子进程指定执行策略，未调用 `Set-ExecutionPolicy`。如果组织组策略限制脚本运行，按组织规则处理后再启动。

## 二、<span id="safety">交互、文件范围与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先回车确认自述，再通过 fzf 选择。子层 `←` 返回上层；多选 `Enter` 勾选 / 取消、`Space` 确认、`Ctrl+A` 全选、`Ctrl+D` 清空、`Esc` 取消。空选不执行，备份完成后只有精确大写 `YES` 才覆盖。完整参数默认值见 [参数表](../README.md#arguments)。

只处理来源目录顶层、大小写精确同名、非空且非重解析点的普通文件。排除 Windows 非法字符、尾部点或空格、保留设备名及 `#`；详见 [文件范围](../README.md#source-files)。

系统临时运行目录保留 `Release-Replace.log`、来源与哈希清单、上传副本、旧附件、下载核验文件和 `RESTORE.txt`。二进制下载不经 PowerShell 文本重定向；逐字节及 SHA-256 均一致才记为成功。上传失败可能已删除旧附件，先核对远端，再审查手动恢复命令，不自动回滚或重试覆盖。

## 三、<span id="verification">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 PowerShell 7 静态解析、帮助、隔离模拟事务和真实原生进程二进制输出验证。Windows 11 ARM64 虚拟机中的 Windows PowerShell 5.1、双击入口、fzf 真实终端操作待验证；没有用本脚本实际覆盖远端，也未验证上传附件本身的业务行为。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> `.cmd`／`.bat` 入口内嵌完整会话守护：黑底白字及强调色保护就绪或明确降级后才开始业务，全部退出路径同步等待恢复回执；同时核对父进程身份。原 PowerShell／Python 启动命令和业务参数不经过再次解析，保护初始化后恢复进入时的延迟扩展模式，原业务自己的 `setlocal` 保留；嵌套 PowerShell 复用同一会话保护。守护脚本只写入本轮系统临时目录，成功恢复后清理控制文件。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
