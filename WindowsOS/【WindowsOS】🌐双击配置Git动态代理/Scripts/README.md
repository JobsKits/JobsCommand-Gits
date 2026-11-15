# `Git 动态代理 Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、文件职责](#jobs-toc-heading-2)
- [二、运行与风险](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本目录是独立 [**Windows PowerShell**](https://learn.microsoft.com/powershell/) Git 代理配置运行核心，从本仓配套入口加载，不注册右键菜单。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| `Configure.ps1` | 首屏、安装/检查/恢复模式与终端交互 |
| `ProxyInstaller.psm1` | 精确用户 PATH、私有快照、独立 shim 安装与恢复 |
| `NetworkPolicy.psm1` | 动态读取系统代理、可达性选路、单次 Git 业务派发 |
| `Policy.ps1` | shim 到策略模块的调用桥接 |
| `GitShim.cs` | 原始 argv 与退出码转发 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从[上级入口](../README.md)运行。配置前核对首屏的作用范围、日志与恢复方式；这里不应直接运行网络策略桥接文件。需要 Windows PowerShell 5.1、Git 和系统自带 .NET 编译能力；当前用户 LocalAppData 中保存运行产物、审计与快照。仅恢复本工具写入项，并发修改冲突时停止。没有执行真实本机安装。



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
