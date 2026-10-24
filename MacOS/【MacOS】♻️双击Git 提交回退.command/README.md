# `【MacOS】♻️双击Git 提交回退.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、功能覆盖](#jobs-toc-heading-2)
- [二、运行方式](#jobs-toc-heading-3)
- [三、输入、选项与结果](#jobs-toc-heading-4)
- [四、环境与依赖](#jobs-toc-heading-5)
- [五、副作用、限制与日志](#jobs-toc-heading-6)
- [六、操作流程](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

- 采用 Shell 脚本的原因：Shell 来自 [**macOS**](https://www.apple.com/macos/) 原生系统底层，虽然写法相对繁琐冗杂，但执行效率高，并且不需要额外介入 [**Ruby**](https://www.ruby-lang.org)、[**Python**](https://www.python.org) 等第三方运行环境，因此具备更好的移植性。
- 本自述文件对应脚本：`【MacOS】♻️双击Git 提交回退.command`。
- 脚本位置：本目录中的同名 `.command`，从当前 README 所在目录运行。
- 脚本定位：通过 fzf 选择上一提交、tag 或 reflog，并执行 Git 本地回退。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 范围 | 当前能力 |
| --- | --- |
| 目标 | 通过 fzf 选择上一提交、tag 或 reflog，并执行 Git 本地回退。 |
| 能力 | 检查 / 安装 Homebrew、fzf，选择脚本所在 Git 根或拖入仓库；只接受 `.git` 目录形式的仓库；发现暂存区已有变更时停止，要求先处理暂存内容。 |
| 说明入口 | [同名主脚本](<./【MacOS】♻️双击Git 提交回退.command>) |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

推荐双击 `.command` 运行。终端方式如下：

```shell
chmod +x './【MacOS】♻️双击Git 提交回退.command'
'./【MacOS】♻️双击Git 提交回退.command'
```

脚本启动后显示内置说明并等待回车。后续选择与确认以本 README 的实际功能和副作用章节为准。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、输入、选项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

> **目的：** 通过 fzf 选择上一提交、tag 或 reflog，并执行 Git 本地回退。

- 检查 / 安装 Homebrew、fzf，选择脚本所在 Git 根或拖入仓库；只接受 `.git` 目录形式的仓库。
- 发现暂存区已有变更时停止，要求先处理暂存内容。
- “上一提交”可选 `soft` 或 `hard`，目标为 `HEAD^`。
- “tag”先按标签选择目标，再选择 soft / hard；“reflog”选择记录后固定 soft。
- 取消菜单或不选择标签 / reflog 时跳过对应回退；结果写入同名临时日志。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、环境与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 Git、Homebrew、fzf 与交互 TTY。Homebrew 会增补当前用户相应 Shell 的 shellenv；安装及升级可能联网。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、副作用、限制与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- **hard 会直接丢弃已跟踪工作区改动，当前实现没有额外 YES 确认，也不先创建恢复分支。** 首屏确认与选择菜单即进入执行。
- soft 移动 HEAD 并保留差异到暂存区；脚本不执行 push、不撤销远端提交。
- 已有 fzf 分支会执行 `brew upgrade fzf` 和 cleanup；Homebrew 总体 update/upgrade 的询问则回车跳过、非空执行。
- 仓库路径读取和 `.git` 目录门禁存在限制；子模块 / linked worktree 的 `.git` 指针不能按已支持描述。
- 日志为系统临时目录中的 `【MacOS】♻️双击Git 提交回退.log`，以脚本结束时打印的实际位置为准。脚本未保证业务命令全部 stdout / stderr 都写入日志。
- 本文按源码静态核对；没有执行真实创建、安装、删除、提交、密钥配置或远端操作。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、操作流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```mermaid
flowchart TD
    N0["检查依赖"] --> N1
    N1["选择仓库并检查暂存区"] --> N2
    N2["选择回退目标"] --> N3
    N3["soft 或 hard"] --> N4
    N4["输出结果"]
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
