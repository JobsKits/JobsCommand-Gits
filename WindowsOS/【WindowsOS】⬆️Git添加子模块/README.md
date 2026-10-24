# `【WindowsOS】⬆️Git添加子模块`

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

备份旧子模块工作树和关联后，按五仓清单重新建立子模块；不自动提交。

对应 [MacOS 原入口](<../../MacOS/【MacOS】⬆️Git添加子模块.command/README.md>)。Windows 使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+ 与 [**Git for Windows**](https://gitforwindows.org/)，不依赖 Homebrew、zsh、AppleScript 或 iOS 模拟器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】⬆️Git添加子模块.cmd`，或在 PowerShell 中执行：

```powershell
& '.\【WindowsOS】⬆️Git添加子模块.ps1'
```

针对目标仓库只读预览，不修改目标配置或索引：

```powershell
& '.\【WindowsOS】⬆️Git添加子模块.ps1' `
  -Repository 'D:\Repos\目标仓库' `
  -DryRun
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 显示现存子模块列表与 JobsCommand 五仓目标清单。
- 精确 YES 后保护未提交内容，备份父仓索引、配置、清单，并把旧工作树移动到独立备份目录；已验明归属的原始元数据一并分区备份。
- 移除旧关联及索引 gitlink，保留 Git 历史缓存，按 Flutter、iOS、Gits、Others、JobsSh 仓库重建；iOS 项目源码本身并非 iOS 模拟器动作。
- 备份目录里的原始 `.git` 指针不改写，恢复时按 `worktree-metadata-map.json` 把工作树、元数据和父仓配置/索引还原到原位置，再核验，不把备份目录直接当活动仓库。
- 按每层 branch 规则同步到本地跟踪分支，差异留待审阅，不自动提交或推送；缓存冲突停止并保留备份。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先显示内置自述，回车确认后执行业务；危险步骤再次要求精确 `YES`。外部命令失败返回非零并停止。日志位于系统临时目录 `JobsGit-rebuild-时间-进程号.log`。

所有路径参数按单独参数传给命令，支持空格、中文和括号；不使用字符串执行。批量扫描跳过 Git 元数据、依赖、产物和重解析点。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已进行本机 PowerShell Parser 静态检查与隔离 Git 夹具验证；未真实创建远端、生成私人密钥、上传视频、安装代理、提交或推送。Windows 资源管理器双击、OpenSSH 服务、GitHub 登录和 Sourcetree 实机行为仍需 Windows 验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
