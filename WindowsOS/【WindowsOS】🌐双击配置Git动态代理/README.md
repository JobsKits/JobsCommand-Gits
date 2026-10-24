# `【WindowsOS】🌐双击配置Git动态代理`

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

配置当前用户 Git 动态入口；系统代理可达优先、不可达再直连，支持检查与精确恢复。

对应 [MacOS 原入口](<../../MacOS/【MacOS】🌐双击配置Git动态代理.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】🌐双击配置Git动态代理.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】🌐双击配置Git动态代理.ps1'
```

只读检查可传 `-Mode Check`，恢复可传 `-Mode Restore`；直接运行默认为 `Menu`。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 双击后回车安装；C 只读检查；R 精确恢复。首屏说明侵入性配置范围、流量走向与恢复方式。
- 仅安装当前用户 PATH 与独立 Git shim，备份将要修改的值和运行文件；不改系统代理、VPN、项目 remote 或固定 http.proxy。
- 系统代理可达时优先，关闭或不可达时再尝试直连；连接选择与原始 Git 业务分离，业务只执行一次。
- 恢复只还原本工具实际修改且当前值仍符合记录的项目；并发改动发生冲突时停止。当前用户运行文件与快照位于 LocalAppData 下 JobsGitNetworkStrategy。
- Windows 机器 PATH 可能优先于用户 PATH；用安装输出的 OpenGitCmd.cmd / OpenGitPowerShell.cmd，或把 Sourcetree 自定义 Git 选择到实际 shim。退出并重启应用后复检。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

运行需要 Windows PowerShell 5.1（Desktop）和已安装的 Git。`Scripts/` 携带完整独立运行核心，不依赖 OS@Extension 的安装位置；审计、状态与精确恢复快照位于用户 LocalAppData 的 `JobsGitNetworkStrategy`。这会修改用户级 PATH，配置前必须阅读首屏。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
