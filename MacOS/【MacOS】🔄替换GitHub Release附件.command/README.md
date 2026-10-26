# macOS Release 附件替换入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录提供可双击的 macOS 原生 [zsh](https://www.zsh.org/) 脚本：[【MacOS】🔄替换GitHub Release附件.command](<./【MacOS】🔄替换GitHub Release附件.command>)。完整功能、按键、参数、备份恢复和限制见 [上级 README](../README.md)。

## 一、<span id="run">运行与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

使用 macOS 系统 `/bin/zsh`，依赖 Git、[GitHub CLI](https://cli.github.com/)、[jq](https://jqlang.org/) 与 [fzf](https://github.com/junegunn/fzf)。先完成 `gh auth login --hostname github.com`，账号须有目标仓库写权限。缺少 gh / jq / fzf 时，安装交互及 Homebrew 边界见 [依赖说明](../README.md#environment)。

双击 `.command`，或在本目录终端运行；分支和 Tag 可同时省略，改为交互选择：

```shell
"./【MacOS】🔄替换GitHub Release附件.command" \
  main \
  v1.0.0 \
  --repo-dir "../../目标仓库" \
  --source-dir "../../目标仓库/Releases/v1.0.0"
```

上述目录是示例，换成实际已有目录。只读查看帮助：

```shell
"./【MacOS】🔄替换GitHub Release附件.command" --help
```

## 二、<span id="safety">确认、产物与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先回车确认用途，再依次选择仓库、远端、分支、Release 和同名附件。fzf 子层 `←` 返回上层；多选 `Enter` 勾选 / 取消、`Space` 确认、`Ctrl+A` 全选、`Ctrl+D` 清空、`Esc` 取消。空选不执行。备份完成后只有精确大写 `YES` 才开始删除旧附件并上传。

日志、来源快照、旧附件、下载校验文件和 `RESTORE.txt` 保留在显示出的系统临时运行目录。中断或失败不自动回滚，先核对远端再审查恢复命令。其余附件、Release 元信息和 Tag 提交均受完整快照校验保护；并发窗口及部分完成风险见 [备份恢复说明](../README.md#backup-recovery)。

当前通过静态和隔离回归，以及真实终端 fzf 操作验证；未通过该脚本实际覆盖远端。脚本可以单独复制使用，配套文档建议一并保留。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
