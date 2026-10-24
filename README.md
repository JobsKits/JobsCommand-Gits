# `JobsCommand@Gits`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、Git 子模块脚本](#git-submodule-scripts)
  - [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](#jobs-toc-heading-3)
  - [【MacOS】🧭更新引用Git父仓=＞子仓.command](#jobs-toc-heading-4)
  - [【MacOS】🧾更新gitmodules.command](#jobs-toc-heading-5)
- [二、目录结构](#repository-layout)
- [三、其它脚本执行流程](#script-workflows)
  - [【MacOS】🌐双击配置Git动态代理.command](#jobs-toc-heading-8)
  - [【MacOS】⏬双击下载SourceTree效率脚本.command](#jobs-toc-heading-9)
  - [【MacOS】♻️双击Git 提交回退.command](#jobs-toc-heading-10)
  - [【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](#jobs-toc-heading-11)
  - [【MacOS】♻️批量Git提交（不含推送）.command](#jobs-toc-heading-12)
  - [【MacOS】♻️检测并转换为子Git.command](#jobs-toc-heading-13)
  - [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](#jobs-toc-heading-14)
  - [【MacOS】⚙️双击生成Github远程仓库URL.command](#jobs-toc-heading-15)
  - [【MacOS】⬆️Git添加子模块.command](#jobs-toc-heading-16)
  - [【MacOS】🎬上传GitHub视频附件.command](#jobs-toc-heading-17)
  - [【MacOS】🔍Git依据提交日志关键字查找.command](#jobs-toc-heading-18)
  - [【MacOS】🔍Git寻找分支最近的一次原始切点.command](#jobs-toc-heading-19)
  - [【MacOS】🚪双击打开Github.Flutter.command](#jobs-toc-heading-20)
  - [【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](#jobs-toc-heading-21)
  - [【MacOS】🚪双击打开Github.JobsOCKit.command](#jobs-toc-heading-22)
  - [【MacOS】🧮双击统计MD文件的有效行数.command](#jobs-toc-heading-23)
  - [【MacOS】🧹清理Git子仓运行态记录.command](#jobs-toc-heading-24)
- [四、MacOS / WindowsOS 功能对应](#dual-platform)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本仓收纳 [**Git**](https://git-scm.com/) 操作脚本。三个子模块入口分别负责下载更新、按磁盘修复关联、增量补齐关联；运行前先按下面的流程选择。

两个平台分别进入 [`./MacOS/`](./MacOS/README.md) 和 [`./WindowsOS/`](./WindowsOS/README.md)。以下既有 zsh 流程和环境变量说明适用于 MacOS；Windows 使用同功能的 CMD / PowerShell 入口，参数及平台差异见[双端对应](#dual-platform)。

本机 Git 网络自动选路使用[双击配置入口](./MacOS/【MacOS】🌐双击配置Git动态代理.command/【MacOS】🌐双击配置Git动态代理.command)：双击同名主脚本，阅读自述后回车，即可安装终端与 [**Sourcetree**](https://www.sourcetreeapp.com/) 共用的用户级配置。系统代理可用时优先，代理关闭或不可用再尝试直连；无需每次手写代理参数。完整检查、备份与恢复说明见[入口 README](./MacOS/【MacOS】🌐双击配置Git动态代理.command/README.md)。

本仓由上层 `JobsGenesis` 的 `.gitmodules` 登记：

```ini
[submodule "JobsCommand@Gits"]
    path = JobsCommand@Gits
    url = ../JobsCommand-Gits.git
    branch = main
```

| 已配置父仓地址 | 子仓解析地址 |
| --- | --- |
| `ssh://git@github.com/JobsKits/JobsGenesis.git` | `ssh://git@github.com/JobsKits/JobsCommand-Gits.git` |
| `git@gitee.com:JobsGo/JobsGenesis.git` | `git@gitee.com:JobsGo/JobsCommand-Gits.git` |

`path` 是本地目录，`url` 使用真实仓名；相对 URL 跟随父仓线路解析。目标平台需已有子仓及父仓指针指定的提交。

<strong id="readonly-submodule-mode">先选用途：只拉取电脑默认跟随分支最新，子仓保持本地分支</strong>

| 启动选择 | 版本依据 | 是否写入父仓提交 |
| --- | --- | --- |
| 只拉取，默认 | 更新当前父仓明确的远程上游，再逐层跟随子仓目标分支最新提交，保持本地跟踪分支 | 不暂存、不提交、不推送 |
| 维护子模块，显式选择 | 按本仓清单及原有菜单，把所选子树更新到各自远端目标分支最新 | 沿用 `AUTO_PARENT_COMMIT` / `AUTO_PARENT_PUSH` 原有开关 |

启动第一屏显示同步策略版本 `2026.10.21`。新电脑须先取得并运行带此版本号的入口；另一台电脑上的本地修改不会自动更新到新电脑。任一仓库拉取、分支切换或递归校验失败时，本轮不能视为全部完成；处理日志中的具体路径后重新运行。

只拉取模式从脚本所在仓库向下递归处理全部已登记子模块；不向上处理，不使用清单新增关联，也不把子仓最新提交自动提交回父仓。各层优先使用直接父仓 `.gitmodules` 的显式 `branch`，`.` 继承该层计划更新后的直接父仓分支；未配置时读取该子仓远端默认分支。首次下载和已有游离 HEAD 都会恢复或创建对应本地跟踪分支，获取最新提交并快进；成功结束时子仓显示实际分支名。每层相对 URL 随当前父仓的下载线路解析。只拉取模式只依赖系统 Git、zsh、Perl 等现有工具，不进入维护模式的 Homebrew / fzf 安装流程。

子仓源码、未跟踪内容、已暂存 gitlink、未完成操作或本地独有提交会报出具体路径并停止；不会强制覆盖或丢弃独有的游离提交，父仓 `YES` 不扩散到子仓。当前父仓自己的源码改动或本地独有提交，仍须红字列明并精确输入 `YES` 才舍弃。目标分支不存在、远端默认分支无法确定或最新提交获取失败时，停止并报告对应仓库与来源；不会把旧 gitlink SHA 当作最新分支结果。

只拉取模式在入口仓已有本地分支时仍要求明确上游。入口仓自身处于游离 HEAD 时，先使用直接父仓 `.gitmodules` 的显式 `branch`，`.` 继承直接父仓当前分支；无配置时读取 `origin` 或唯一远端的默认分支。已有目标本地分支须明确跟踪所选远端的同名分支；先获取最新提交，预检整棵子树与提交历史，并复查确认期间的状态，再恢复或创建本地跟踪分支。入口源码未提交、需继承分支时直接父仓同样游离、目标不明、目标分支无法快进或存在未受引用保护的独有游离提交时停止；普通父仓的 `YES` 不授权舍弃这些提交。

`REMOTE_NAME` 等原有清单参数只用于维护模式。设置 `DRY_RUN=1` 时，默认只拉取会停止并提示选择维护演练，不能忽略演练标志后执行真实更新。未初始化但存在旧 Git 缓存的空工作树须先恢复，脚本不会覆盖缓存内索引或独有提交。

下文关于清单新增、多选、可切换同步深度、目录清理及自动提交的既有流程，均指显式选择的**维护模式**。只拉取模式默认向下递归到分支最新，不使用这些写入父仓的开关；子仓最新提交与父仓 gitlink 可能不同，父仓会显示待审阅的子模块指针改动。两种模式都保留各仓独立清单和来源显示；只拉取日志带运行时间与进程号，终端会输出实际路径。

维护模式补齐或新增登记时，不自动写入 `branch = main`；已有 `branch` 与缺省状态均保留。显式 `branch` 严格指定目标分支，`.` 继承直接父仓分支；未配置时跟随子仓远端默认分支。目标不存在、直接父仓分支无法确定或远端默认分支无法确定时停止。

<strong id="capability-map">按目标找入口</strong>

| 目标 | 功能范围与入口 |
| --- | --- |
| 下载、关联与维护子模块 | 默认只拉取 / 显式维护、修复父子关联、增补 gitmodules、全量重建、运行态记录清理；各自确认与提交策略不同。 |
| 保存与找回本地资料 | 批量提交（不推送）、soft / hard / tag / reflog 回退、dangling 对象恢复；macOS 恢复包含自动合并，先阅读包内风险。 |
| 网络与账户 | Git 动态代理安装 / 检查 / 精确恢复、SSH 密钥、GitHub 仓库创建及视频附件上传。 |
| 历史分析与快捷打开 | 描述关键词 / 分支来源推断、reflog / 拓扑切点分析、三个固定 GitHub 页面。 |
| 文档自动化 | 安装 Markdown 行数 pre-commit 钩子；有效行数定义与自动暂存边界见对应入口。 |
| 平台入口 | [macOS 20 个脚本包](./MacOS/README.md) / [Windows 20 组入口](./WindowsOS/README.md)。同名功能的菜单与保护条件按各平台源码分别说明。 |

## 一、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](./MacOS/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 默认递归拉取已登记子模块目标分支的最新提交，保持本地跟踪分支；显式维护模式保留清单与登记能力。

- 启动时回车默认进入[只拉取模式](#readonly-submodule-mode)，先预检本地状态，再更新当前父仓并逐层快进到子仓目标分支最新提交；恢复已有游离 HEAD，不提交、不推送。
- 显式选择维护模式后，按以下原有清单和菜单流程处理。

* 确认自述后读取脚本清单、检查远端，尝试拉取父仓。
* 父仓有未提交改动：跳过父仓拉取，继续处理子仓。
* 在主菜单选择同步范围；“切换同步深度”可在默认“向下递归”和“仅直属子模块”之间切换，当前深度适用于各同步动作。
  * 全量同步：逐项同步清单内全部目标，按目录状态复用或首次克隆。
  * 只更新已有：更新清单内已存在的子仓；一个都没有时转全量同步。
  * 指定子模块：回车勾选或取消，空格确认开始。
  * 添加地址：输入新仓地址，自动用仓名作为目录，本轮登记并同步。
* 补齐关联配置，检查并处理目标子仓目录。
  * 目录为空或缺失：首次克隆；已有有效 Git 工作区：保留目录、缓存及后代，直接更新。
  * 已有 `modules/` 缓存时先核验并恢复空工作区；非 Git 非空目录保护并停止。
  * 子仓有未提交、已暂存或未跟踪内容：红字加粗显示该仓绝对路径并循环等待；精确输入 `YES` 只放弃当前仓自己的未提交内容，或在外部处理后回车复检。其它输入继续复检；无交互或输入结束则停止。
* 拉取并快进到远端目标分支最新提交：优先使用该层 `.gitmodules` 显式 `branch`，`.` 继承直接父仓分支；未设置时读取该子仓远端默认分支；显式目标分支不存在时立即停止，不回退其它分支。
  * 已有目标本地分支只允许快进，领先远端或发生分叉时停止并保留本地提交；缺少目标分支时创建本地跟踪分支。
* 按当前深度同步：默认逐层读取所选子仓下的 `.gitmodules`，将已登记后代同步到各自远端目标分支最新提交；仅直属模式不下载或更新下层代码。
  * 只处理本层所选子树，不向上扫描，也不接管未登记的嵌套仓库。
  * 递归更新本层前先检查当前已有后代；各仓单独确认，子模块 HEAD 与父仓 gitlink 的普通差异不作为源码未提交反复提示。
  * `YES` 清理仅作用于当前仓：`reset --hard HEAD` 与 `clean -fd`；保留忽略文件和独立嵌套 Git 仓，残留冲突须外部处理后复检。
  * `PRUNE_STALE_GITMODULES` 默认 `0`，保留清单外旧登记；主动设为 `1` 时，每个旧登记另用红字加粗列明目录和后代删除范围，逐项精确输入 `YES` 才删除，其它输入、输入结束或非交互则停止；演练只展示，删除前仍逐仓检查已有后代。
  * 深层只下载更新，不自动暂存或提交其父仓的 gitlink；递归后这些父仓可能显示子模块指针改动，保留待审阅。
* 整理入口父仓 Git 元数据与来源日志。
* 默认自动提交入口父仓的关联变化，不自动推送。
  * 设置 `AUTO_PARENT_COMMIT=0`：跳过提交；`AUTO_PARENT_PUSH=1`：启用父仓推送。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】🧭更新引用Git父仓=＞子仓.command](<./MacOS/【MacOS】🧭更新引用Git父仓=＞子仓.command/【MacOS】🧭更新引用Git父仓=＞子仓.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 修复目录改名、旧路径残留或元数据指向错误，让父仓关联符合当前磁盘布局。

* 扫描父仓第一层实际带 `.git` 的子目录，读取远端和已有登记。
  * 远端缺失、元数据归属不明或属于链接工作树：停止修复。
* 展示磁盘目录、父仓状态与清理计划，确认后备份关联状态。
  * 直接回车：跳过；输入任意字符后回车：执行；`--dry-run`：只预览。
* 按现存目录对齐 `.gitmodules`，保留仍存在条目的 URL、分支及扩展字段。
  * 目录缺失，包括尚未下载：移除旧登记和旧子模块指针，磁盘文件保留。
* 修复可证明失效的工作树指向，暂存各子仓当前提交号，用官方命令归集元数据并补齐父仓本地登记。
* 核对磁盘目录、清单和父仓子模块指针是否一致，输出状态；不拉取代码、不提交、不推送。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】🧾更新gitmodules.command](./MacOS/【MacOS】🧾更新gitmodules.command/【MacOS】🧾更新gitmodules.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将新放入的直属子仓完整纳入父仓子模块管理，保留已有登记与指针。

* 读取已有登记，扫描直属子仓，预检远端、提交、索引和元数据冲突。
  * 有冲突或缺少必要信息：停止，展示问题。
* 生成增量计划，保留已有 URL、分支、扩展字段、子模块指针和暂缺目录登记。
  * `--dry-run` 或 `DRY_RUN=1`：只预览，不执行关联写入。
* 确认计划后备份关联配置和父仓索引。
  * 直接回车：跳过；输入任意字符后回车：执行。
* 补齐 `.gitmodules` 和缺失的子模块指针，初始化本地登记，将元数据归集到父仓。
* 核验父子关系和子仓提交号；仅暂存必要关联，不联网拉取、不提交、不推送。

## 二、<span id="repository-layout">目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

下面按当前磁盘第一层列出真实文件与目录；包内主脚本由下方完整名称直接进入。

```text
JobsCommand@Gits/
├── README.md
├── MacOS/                 # 原 20 个脚本包、README、资源与测试
├── WindowsOS/             # 20 组 CMD + PowerShell 平行功能
│   ├── GitTools.psm1      # 公共原生 Windows Git 实现
│   ├── MarkdownLines.ps1  # 提交钩子统计核心
│   ├── 功能映射.json
│   └── 各功能包/
├── .jobs-markdown-toc/    # 受控文档目录工具
└── .gitattributes
```

## 三、<span id="script-workflows">其它脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本仓提供 20 项功能、MacOS 20 个和 WindowsOS 20 个用户入口。统计时间：2026-10-23；MacOS 按平台目录中同名主脚本计数，WindowsOS 每对 CMD / PS1 计一个入口，独立子 Git、测试、函数库及内嵌运行模板不作为用户运行入口。这里只列本仓维护的主入口，以下步骤以静态源码和配套说明为准；具体脚本的验证范围另见其 README。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[【MacOS】🌐双击配置Git动态代理.command](./MacOS/【MacOS】🌐双击配置Git动态代理.command/【MacOS】🌐双击配置Git动态代理.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 一次安装终端与 Sourcetree 共用的动态网络入口，自动使用当前可达的系统代理或直连链路。

- 双击主脚本，先展示作用范围、流量走向、日志和恢复方式，回车确认后配置；`Ctrl+C` 取消。
- 检查 macOS 原生 Git 和必要系统工具，从脚本内嵌内容部署独立运行入口，不依赖已有 JobsMacEnv 或下载仓库的位置。
- 备份本次精确修改项，在当前用户 Shell 配置末尾挂载入口，并配置已安装的 Sourcetree；保留原有正文与其它偏好，不修改系统代理或固定 `http.proxy`。
  - 已运行的 Sourcetree 不强制结束；保存任务并重新启动后加载新的入口。
- 后续普通 HTTP / HTTPS Git 操作先验证当前系统代理，代理关闭或不可用时再尝试直连；不绑定 VPN 品牌或固定端口。
- 重复安装保持幂等；可只读检查或精确恢复本次配置，后续用户改动发生冲突时保留并停止，不清空整份配置。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】⏬双击下载SourceTree效率脚本.command](<./MacOS/【MacOS】⏬双击下载SourceTree效率脚本.command/【MacOS】⏬双击下载SourceTree效率脚本.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 重新下载 SourceTree 效率脚本库，并为脚本添加执行权限。

- 来源固定为 `https://github.com/JobsKits/SourceTree.sh.git`，目标是当前用户目录下的 `SourceTree.command`。
- 进入业务后直接删除已有目标目录，再执行 `git clone --depth=1`；只保留浅克隆历史。
- 递归对下载库中的 `.sh`、`.command` 文件添加执行权限。
- 完成后用 Finder 打开目标目录；不运行新脚本，也不安装 SourceTree 菜单。
  - **源码没有目标备份、YES 二次确认或失败回滚。** 首屏回车之后，目标已有内容及 Git 元数据会被删除，克隆失败也不会恢复。

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS】♻️双击Git 提交回退.command](<./MacOS/【MacOS】♻️双击Git 提交回退.command/【MacOS】♻️双击Git 提交回退.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 通过 fzf 选择上一提交、tag 或 reflog，并执行 Git 本地回退。

- 检查 / 安装 Homebrew、fzf，选择脚本所在 Git 根或拖入仓库；只接受 `.git` 目录形式的仓库。
- 发现暂存区已有变更时停止，要求先处理暂存内容。
- “上一提交”可选 `soft` 或 `hard`，目标为 `HEAD^`。
- “tag”先按标签选择目标，再选择 soft / hard；“reflog”选择记录后固定 soft。
- 取消菜单或不选择标签 / reflog 时跳过对应回退；结果写入同名临时日志。
  - **hard 会直接丢弃已跟踪工作区改动，当前实现没有额外 YES 确认，也不先创建恢复分支。** 首屏确认与选择菜单即进入执行。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](<./MacOS/【MacOS】♻️双击恢复误删本地Git已储藏的资料.command/【MacOS】♻️双击恢复误删本地Git已储藏的资料.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 搜寻 Git dangling 对象，并尝试恢复 commit、tree 与 blob。

- 从脚本所在目录定位 Git 根，执行 `git fsck --lost-found`，把对象清单暂存到工作树 `.fsck_temp`。
- 每个 dangling commit 创建 `recovered-commit-<SHA>` 分支，再自动尝试合并到当前分支。
- 每个 dangling tree 用 `git commit-tree` 创建提交和 `recovered-tree-<SHA>` 分支，再尝试合并。
- 每个 dangling blob 输出为工作树 `recovered/blobs/<SHA>.txt` 并自动暂存；后缀 txt 不代表原对象一定是文本。
- 结束移除 `.fsck_temp`，由用户检查恢复文件和合并现场，决定是否创建最终提交。
  - **该入口不是普通 stash 选择恢复。** 它批量处理 fsck 暴露的悬空对象，且自动尝试 `merge --allow-unrelated-histories --no-commit`，可能产生冲突。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】♻️批量Git提交（不含推送）.command](<./MacOS/【MacOS】♻️批量Git提交（不含推送）.command/【MacOS】♻️批量Git提交（不含推送）.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 遍历指定大目录中的 Git 仓库，有改动时自动暂存和创建本地提交。

- 输入 / 拖入扫描根目录；当前用户目录的 `.last_sourcetree_path` 保存上次路径，后续回车复用。
- 用 find 搜寻 `.git` 目录并排序去重；实体 `.git` 才被列入，指针形式的子模块 / worktree 不在此扫描范围。
- 逐仓检查 `git status --porcelain`；有改动执行 `git add .`。
- 提交说明固定为 `自动提交：<当前日期时间>`；无改动仓库跳过，提交失败显示提示后继续。
- 不执行 push，最终留在扫描循环最后成功进入的仓库。
  - 会把每个仓库全部可跟踪改动混入同一提交，没有逐仓预览或自定义提交说明菜单。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS】♻️检测并转换为子Git.command](<./MacOS/【MacOS】♻️检测并转换为子Git.command/【MacOS】♻️检测并转换为子Git.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 扫描父仓中的独立嵌套 Git，交互选择后转成子模块关联。

- 默认以启动时当前目录为起点，也接受第一个路径参数；非 Git 路径循环要求重输，并解析到所属 Git 根。
- 枚举 `.git` 目录或指针文件，排除 `.gitmodules` 已登记 path 及 Pods、build、DerivedData、Carthage、.swiftpm、node_modules、.gradle、.idea、.vscode 等目录。
- 展示相对路径、origin、分支；单项直接确认，多项用 fzf 的 TAB 多选、ALL 或 Ctrl+A 全选。
- 父仓有改动时显示状态，回车继续、非空返回；每项再次采用回车转换、非空跳过。
- 转换前把原工作树移到系统临时目录备份，清理对应旧索引 / 关联残留，再用原 origin 执行 submodule add。
  - 会移动子仓工作树、写父仓 `.gitmodules`、索引 gitlink 和本地关联；备份位置以终端实际输出为准，不能承诺零副作用。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](<./MacOS/【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command/【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 生成个人 SSH 密钥，加载 ssh-agent、复制公钥并打开 GitHub 配置页面。

- 选择算法：回车或 `1` 为 ED25519，`2` 为 RSA 4096；非法输入回落 ED25519。
- 个人邮箱可输入或使用屏幕提示的默认值；生成目标固定为当前用户 `.ssh` 中的 `id_rsa_personal`，与所选算法无关。
- 生成密钥使用空口令；启动 ssh-agent，调用 `ssh-add --apple-use-keychain` 并列出已加载密钥。
- 显示并复制 `.pub` 公钥，打开 GitHub SSH 设置页供手工登记。
- 缺少 `Host github.com` 时向 `.ssh/config` 追加配置；向已有 `.zshrc`、`.bash_profile` 追加 ssh-agent 启动行，最后交互测试 `ssh -T git@github.com`。
  - 生成和检查确认采用“回车同意，非空输入退出”；不能把本入口写成统一 YES 确认。已有同名密钥由 ssh-keygen 自己询问覆盖。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS】⚙️双击生成Github远程仓库URL.command](<./MacOS/【MacOS】⚙️双击生成Github远程仓库URL.command/【MacOS】⚙️双击生成Github远程仓库URL.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 在 GitHub 创建远端仓库，并输出、打开 API 返回的网页地址。

- 检查 Homebrew 与 jq；jq 缺失时执行 `brew install jq`。
- 交互输入 GitHub 用户名、个人访问令牌和仓库名；用户名仅收集，API 根据令牌确定账户。
- 向 `https://api.github.com/user/repos` 发送 POST，只提交 `name` 字段；未提供 private/public 菜单。
- 用 jq 读取 `html_url`，在终端输出，并优先调用 `xdg-open`、否则 macOS `open`。
  - 令牌由普通 `read` 读取，会在终端回显；不能在共享终端运行，也不要把令牌复制到日志或截图。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【MacOS】⬆️Git添加子模块.command](<./MacOS/【MacOS】⬆️Git添加子模块.command/【MacOS】⬆️Git添加子模块.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 按内置五仓清单全量重建子模块，并把关联与最新指针提交到父仓。

- 定位脚本所属 Git 根，执行 git init / add，并枚举 `.gitmodules` 与索引中的全部子模块路径。
- 直接删除现有子模块工作树及对应 `.git/modules`，清空 `.gitmodules`，尝试创建清理提交。
- 内置重新添加 Flutter、iOS、Gits、Others、JobsSh 五仓，使用 `../真实仓名.git`；分支默认 main，环境变量 `SUBMODULE_BRANCH` 可覆盖添加分支。
- 同步登记、递归初始化、拉取远端并 merge；随后尽可能切到 main / origin/main，再把 gitlink 变更提交回父仓。
- 父仓已有 origin 时保留；缺少时要求输入可访问远端并配置。源码没有 git push 调用。
  - **这是破坏性全量重建。** 首屏与业务自述回车后即可删除，不存在额外 YES 门禁；没有原工作树备份。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【MacOS】🎬上传GitHub视频附件.command](<./MacOS/【MacOS】🎬上传GitHub视频附件.command/【MacOS】🎬上传GitHub视频附件.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 上传本地视频为 GitHub 附件并取得可粘贴 URL。

- 输入仓库地址与 MP4 / MOV / WEBM 文件，校验文件和格式。
- 检查 gh 登录和目标仓库写权限。
- 上传附件，输出并复制 URL；重复执行会产生新附件，不自动改 README。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【MacOS】🔍Git依据提交日志关键字查找.command](<./MacOS/【MacOS】🔍Git依据提交日志关键字查找.command/【MacOS】🔍Git依据提交日志关键字查找.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 依据提交说明推断当前分支来源，并在无法自动判断时搜索提交锚点。

- 输入 / 拖入仓库；回车默认脚本目录，支持 `.git` 目录、指针以及裸仓识别。
- 读取当前分支和从早到晚的提交标题，解析 `Merge … into …` / 中文“合并…到…”语句，寻找目标为当前分支的来源。
- 自动未命中进入锚点模式：可用 fzf 选已有标题，也可手输字面关键词；空输入跳过。
- 优先在 HEAD 第一父链匹配，未命中再搜索 HEAD 全历史；默认选择结果列表首项，输入 `2` 选末项。
- 输出锚点完整 SHA、作者、时间和标题；不切换分支，不修改提交。
  - 分支来源属于基于提交文字的推断，提交标题不规范、重命名、squash 或历史重写会影响结果；不能当作拓扑证明。

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【MacOS】🔍Git寻找分支最近的一次原始切点.command](<./MacOS/【MacOS】🔍Git寻找分支最近的一次原始切点.command/【MacOS】🔍Git寻找分支最近的一次原始切点.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 结合本机 reflog 与 Git 拓扑，推断目标分支父分支及分叉提交。

- 输入 / 拖入仓库；回车默认脚本目录，要求 `.git` 目录或指针。
- 从本地、远端跟踪分支中选目标；有 fzf 时选择，缺失或取消可手输分支名。
- 读取目标本地分支最早保留的 reflog，尝试提取 Created from / checkout 来源线索。
- 逐个候选执行 `merge-base --fork-point`，失败回落 `merge-base`；按分叉时间和候选第一父链距离评分。
- 输出推测父分支、分叉提交详情、分叉后首个独有提交、ahead / behind 和 first-parent 提交数。
- 回车继续分析同仓其它分支，`c` 更换仓库，`q` 退出。
  - reflog 仅反映当前机器保留的记录；自动排名是启发式推断，多次合并和改写历史时需要人工核对。

### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.Flutter.command](<./MacOS/【MacOS】🚪双击打开Github.Flutter.command/【MacOS】🚪双击打开Github.Flutter.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。

### <span id="jobs-toc-heading-21" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](<./MacOS/【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command/【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。

### <span id="jobs-toc-heading-22" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.JobsOCKit.command](<./MacOS/【MacOS】🚪双击打开Github.JobsOCKit.command/【MacOS】🚪双击打开Github.JobsOCKit.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。

### <span id="jobs-toc-heading-23" data-jobs-toc="v2">[【MacOS】🧮双击统计MD文件的有效行数.command](<./MacOS/【MacOS】🧮双击统计MD文件的有效行数.command/【MacOS】🧮双击统计MD文件的有效行数.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装 pre-commit 钩子，在提交时更新 Markdown 的有效行数标记。

- 定位脚本所在 Git 根，用 `git rev-parse --git-path hooks/pre-commit` 解析真实钩子路径；已有钩子或链接时停止保留。
- 只有预先包含独占行 `当前总行数：0 行`（数字可不同）的 `.md` 才参与更新。
- 每次提交时递归 find `.md`，排除空行、以 # 开头的行与三反引号围栏行后计算行数；围栏内正文仍计数。
- 用 macOS sed 原地替换标记，并对改过的每份文档执行 `git add`。
- 安装完成显示钩子文件属性；当前运行只安装钩子，不立即创建 Git 提交。
  - 已有钩子不会覆盖，须手工整合；提交时的行数更新会整文件暂存，部分暂存文档须先核查。

### <span id="jobs-toc-heading-24" data-jobs-toc="v2">[【MacOS】🧹清理Git子仓运行态记录.command](<./MacOS/【MacOS】🧹清理Git子仓运行态记录.command/【MacOS】🧹清理Git子仓运行态记录.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 让运行态记录退出 Git 跟踪，同时保留本机文件。

- 定位外层仓库及 .gitmodules 中的子仓，确认待处理范围。
- 输入 YES 后，为各仓补齐运行态忽略规则。
- 将匹配的已跟踪运行态路径从索引移除，真实文件不删除；完成后检查各仓差异。

## 四、<span id="dual-platform">MacOS / WindowsOS 功能对应</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

MacOS 原脚本整体保留在 [`./MacOS/`](./MacOS/README.md)，Windows 实现位于 [`./WindowsOS/`](./WindowsOS/README.md)。本仓 20 项功能均不涉及 iOS 模拟器控制，全部提供 Windows 对应入口；打开 OC 仓库网页与下载 iOS 项目源码仍可在 Windows 使用。

| MacOS 功能包 | Windows 功能包 |
| --- | --- |
| [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](<./MacOS/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/README.md>) | [【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）](<./WindowsOS/【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）/README.md>) |
| [【MacOS】⏬双击下载SourceTree效率脚本.command](<./MacOS/【MacOS】⏬双击下载SourceTree效率脚本.command/README.md>) | [【WindowsOS】⏬双击下载SourceTree效率脚本](<./WindowsOS/【WindowsOS】⏬双击下载SourceTree效率脚本/README.md>) |
| [【MacOS】♻️双击Git 提交回退.command](<./MacOS/【MacOS】♻️双击Git 提交回退.command/README.md>) | [【WindowsOS】♻️双击Git 提交回退](<./WindowsOS/【WindowsOS】♻️双击Git 提交回退/README.md>) |
| [【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](<./MacOS/【MacOS】♻️双击恢复误删本地Git已储藏的资料.command/README.md>) | [【WindowsOS】♻️双击恢复误删本地Git已储藏的资料](<./WindowsOS/【WindowsOS】♻️双击恢复误删本地Git已储藏的资料/README.md>) |
| [【MacOS】♻️批量Git提交（不含推送）.command](<./MacOS/【MacOS】♻️批量Git提交（不含推送）.command/README.md>) | [【WindowsOS】♻️批量Git提交（不含推送）](<./WindowsOS/【WindowsOS】♻️批量Git提交（不含推送）/README.md>) |
| [【MacOS】♻️检测并转换为子Git.command](<./MacOS/【MacOS】♻️检测并转换为子Git.command/README.md>) | [【WindowsOS】♻️检测并转换为子Git](<./WindowsOS/【WindowsOS】♻️检测并转换为子Git/README.md>) |
| [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](<./MacOS/【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command/README.md>) | [【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）](<./WindowsOS/【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）/README.md>) |
| [【MacOS】⚙️双击生成Github远程仓库URL.command](<./MacOS/【MacOS】⚙️双击生成Github远程仓库URL.command/README.md>) | [【WindowsOS】⚙️双击生成Github远程仓库URL](<./WindowsOS/【WindowsOS】⚙️双击生成Github远程仓库URL/README.md>) |
| [【MacOS】⬆️Git添加子模块.command](<./MacOS/【MacOS】⬆️Git添加子模块.command/README.md>) | [【WindowsOS】⬆️Git添加子模块](<./WindowsOS/【WindowsOS】⬆️Git添加子模块/README.md>) |
| [【MacOS】🌐双击配置Git动态代理.command](<./MacOS/【MacOS】🌐双击配置Git动态代理.command/README.md>) | [【WindowsOS】🌐双击配置Git动态代理](<./WindowsOS/【WindowsOS】🌐双击配置Git动态代理/README.md>) |
| [【MacOS】🎬上传GitHub视频附件.command](<./MacOS/【MacOS】🎬上传GitHub视频附件.command/README.md>) | [【WindowsOS】🎬上传GitHub视频附件](<./WindowsOS/【WindowsOS】🎬上传GitHub视频附件/README.md>) |
| [【MacOS】🔍Git依据提交日志关键字查找.command](<./MacOS/【MacOS】🔍Git依据提交日志关键字查找.command/README.md>) | [【WindowsOS】🔍Git依据提交日志关键字查找](<./WindowsOS/【WindowsOS】🔍Git依据提交日志关键字查找/README.md>) |
| [【MacOS】🔍Git寻找分支最近的一次原始切点.command](<./MacOS/【MacOS】🔍Git寻找分支最近的一次原始切点.command/README.md>) | [【WindowsOS】🔍Git寻找分支最近的一次原始切点](<./WindowsOS/【WindowsOS】🔍Git寻找分支最近的一次原始切点/README.md>) |
| [【MacOS】🚪双击打开Github.Flutter.command](<./MacOS/【MacOS】🚪双击打开Github.Flutter.command/README.md>) | [【WindowsOS】🚪双击打开Github.Flutter](<./WindowsOS/【WindowsOS】🚪双击打开Github.Flutter/README.md>) |
| [【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](<./MacOS/【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command/README.md>) | [【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo](<./WindowsOS/【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo/README.md>) |
| [【MacOS】🚪双击打开Github.JobsOCKit.command](<./MacOS/【MacOS】🚪双击打开Github.JobsOCKit.command/README.md>) | [【WindowsOS】🚪双击打开Github.JobsOCKit](<./WindowsOS/【WindowsOS】🚪双击打开Github.JobsOCKit/README.md>) |
| [【MacOS】🧭更新引用Git父仓=＞子仓.command](<./MacOS/【MacOS】🧭更新引用Git父仓%3D＞子仓.command/README.md>) | [【WindowsOS】🧭更新引用Git父仓到子仓](<./WindowsOS/【WindowsOS】🧭更新引用Git父仓到子仓/README.md>) |
| [【MacOS】🧮双击统计MD文件的有效行数.command](<./MacOS/【MacOS】🧮双击统计MD文件的有效行数.command/README.md>) | [【WindowsOS】🧮双击统计MD文件的有效行数](<./WindowsOS/【WindowsOS】🧮双击统计MD文件的有效行数/README.md>) |
| [【MacOS】🧹清理Git子仓运行态记录.command](<./MacOS/【MacOS】🧹清理Git子仓运行态记录.command/README.md>) | [【WindowsOS】🧹清理Git子仓运行态记录](<./WindowsOS/【WindowsOS】🧹清理Git子仓运行态记录/README.md>) |
| [【MacOS】🧾更新gitmodules.command](<./MacOS/【MacOS】🧾更新gitmodules.command/README.md>) | [【WindowsOS】🧾更新gitmodules](<./WindowsOS/【WindowsOS】🧾更新gitmodules/README.md>) |

Windows 使用 PowerShell 5.1+、Git for Windows；不依赖 Homebrew、zsh、osascript。所有入口先显示自述；危险动作精确 `YES`。Windows 分支最新同步、回退、恢复、关联、清理等保留本地审查边界，自动创建提交/推送不作为同步默认动作。动态代理具有独立安装、只读检查和精准恢复，不修改系统代理。具体参数、日志和 Windows 实机验证边界见各包 README。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
