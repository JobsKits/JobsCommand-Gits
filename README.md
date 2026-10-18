# `JobsCommand@Gits`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、Git 子模块脚本](#git-submodule-scripts)
  - [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](#jobs-toc-heading-3)
  - [【MacOS】🧭更新引用Git父仓=\>子仓.command](#jobs-toc-heading-4)
  - [【MacOS】🧾更新gitmodules.command](#jobs-toc-heading-5)
- [二、目录结构](#repository-layout)
- [三、其它脚本执行流程](#script-workflows)
  - [【MacOS】⏬双击下载SourceTree效率脚本.command](#jobs-toc-heading-8)
  - [【MacOS】♻️双击Git 提交回退.command](#jobs-toc-heading-9)
  - [【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](#jobs-toc-heading-10)
  - [【MacOS】♻️批量Git提交（不含推送）.command](#jobs-toc-heading-11)
  - [【MacOS】♻️检测并转换为子Git.command](#jobs-toc-heading-12)
  - [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](#jobs-toc-heading-13)
  - [【MacOS】⚙️双击生成Github远程仓库URL.command](#jobs-toc-heading-14)
  - [【MacOS】⬆️Git添加子模块.command](#jobs-toc-heading-15)
  - [【MacOS】🎬上传GitHub视频附件.command](#jobs-toc-heading-16)
  - [【MacOS】🔍Git依据提交日志关键字查找.command](#jobs-toc-heading-17)
  - [【MacOS】🔍Git寻找分支最近的一次原始切点.command](#jobs-toc-heading-18)
  - [【MacOS】🚪双击打开Github.Flutter.command](#jobs-toc-heading-19)
  - [【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](#jobs-toc-heading-20)
  - [【MacOS】🚪双击打开Github.JobsOCKit.command](#jobs-toc-heading-21)
  - [【MacOS】🧮双击统计MD文件的有效行数.command](#jobs-toc-heading-22)
  - [【MacOS】🧹清理Git子仓运行态记录.command](#jobs-toc-heading-23)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本仓收纳 [**Git**](https://git-scm.com/) 操作脚本。三个子模块入口分别负责下载更新、按磁盘修复关联、增量补齐关联；运行前先按下面的流程选择。

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

## 一、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将选中的子仓及可选的后代子模块更新到各自远端目标分支最新版本，并维护入口父仓关联。

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
* 拉取并强制对齐远端目标分支最新提交：优先使用该层 `.gitmodules` 显式 `branch`，`.` 继承直接父仓分支；未设置时优先 `main`，不存在则使用远端默认分支。
  * 使用 `checkout -B` 和 `reset --hard`：目标本地分支未推送的独有提交可能被覆盖。
* 按当前深度同步：默认逐层读取所选子仓下的 `.gitmodules`，将已登记后代同步到各自远端目标分支最新提交；仅直属模式不下载或更新下层代码。
  * 只处理本层所选子树，不向上扫描，也不接管未登记的嵌套仓库。
  * 递归更新本层前先检查当前已有后代；各仓单独确认，子模块 HEAD 与父仓 gitlink 的普通差异不作为源码未提交反复提示。
  * `YES` 清理仅作用于当前仓：`reset --hard HEAD` 与 `clean -fd`；保留忽略文件和独立嵌套 Git 仓，残留冲突须外部处理后复检。
  * `PRUNE_STALE_GITMODULES` 默认 `0`，保留清单外旧登记；主动设为 `1` 时，每个旧登记另用红字加粗列明目录和后代删除范围，逐项精确输入 `YES` 才删除，其它输入、输入结束或非交互则停止；演练只展示，删除前仍逐仓检查已有后代。
  * 深层只下载更新，不自动暂存或提交其父仓的 gitlink；递归后这些父仓可能显示子模块指针改动，保留待审阅。
* 整理入口父仓 Git 元数据与来源日志。
* 默认自动提交入口父仓的关联变化，不自动推送。
  * 设置 `AUTO_PARENT_COMMIT=0`：跳过提交；`AUTO_PARENT_PUSH=1`：启用父仓推送。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】🧭更新引用Git父仓=>子仓.command](./【MacOS】🧭更新引用Git父仓=%3E子仓.command/【MacOS】🧭更新引用Git父仓=%3E子仓.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 修复目录改名、旧路径残留或元数据指向错误，让父仓关联符合当前磁盘布局。

* 扫描父仓第一层实际带 `.git` 的子目录，读取远端和已有登记。
  * 远端缺失、元数据归属不明或属于链接工作树：停止修复。
* 展示磁盘目录、父仓状态与清理计划，确认后备份关联状态。
  * 直接回车：跳过；输入任意字符后回车：执行；`--dry-run`：只预览。
* 按现存目录对齐 `.gitmodules`，保留仍存在条目的 URL、分支及扩展字段。
  * 目录缺失，包括尚未下载：移除旧登记和旧子模块指针，磁盘文件保留。
* 修复可证明失效的工作树指向，暂存各子仓当前提交号，用官方命令归集元数据并补齐父仓本地登记。
* 核对磁盘目录、清单和父仓子模块指针是否一致，输出状态；不拉取代码、不提交、不推送。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】🧾更新gitmodules.command](./【MacOS】🧾更新gitmodules.command/【MacOS】🧾更新gitmodules.command)</span><!-- jobs-toc:heading-end -->

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
├── 【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/  # 1 个入口
├── 【MacOS】⏬双击下载SourceTree效率脚本.command/  # 1 个入口
├── 【MacOS】♻️双击Git 提交回退.command/  # 1 个入口
├── 【MacOS】♻️双击恢复误删本地Git已储藏的资料.command/  # 1 个入口
├── 【MacOS】♻️批量Git提交（不含推送）.command/  # 1 个入口
├── 【MacOS】♻️检测并转换为子Git.command/  # 1 个入口
├── 【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command/  # 1 个入口
├── 【MacOS】⚙️双击生成Github远程仓库URL.command/  # 1 个入口
├── 【MacOS】⬆️Git添加子模块.command/  # 1 个入口
├── 【MacOS】🎬上传GitHub视频附件.command/  # 1 个入口
├── 【MacOS】🔍Git依据提交日志关键字查找.command/  # 1 个入口
├── 【MacOS】🔍Git寻找分支最近的一次原始切点.command/  # 1 个入口
├── 【MacOS】🚪双击打开Github.Flutter.command/  # 1 个入口
├── 【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command/  # 1 个入口
├── 【MacOS】🚪双击打开Github.JobsOCKit.command/  # 1 个入口
├── 【MacOS】🧭更新引用Git父仓=>子仓.command/  # 1 个入口
├── 【MacOS】🧮双击统计MD文件的有效行数.command/  # 1 个入口
├── 【MacOS】🧹清理Git子仓运行态记录.command/  # 1 个入口
└── 【MacOS】🧾更新gitmodules.command/  # 1 个入口
```

## 三、<span id="script-workflows">其它脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本仓共有 19 个用户入口。这里只列本仓维护的主入口；独立子 Git、测试、函数库及打包资源模板不作为用户运行入口。步骤来自静态源码与配套说明，未执行安装、清理、构建或 Git 写操作。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[【MacOS】⏬双击下载SourceTree效率脚本.command](./%E3%80%90MacOS%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command/%E3%80%90MacOS%E3%80%91%E2%8F%AC%E5%8F%8C%E5%87%BB%E4%B8%8B%E8%BD%BDSourceTree%E6%95%88%E7%8E%87%E8%84%9A%E6%9C%AC.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 取得可本地运行的 [**Sourcetree**](https://www.sourcetreeapp.com/) 脚本库。

- 检查 Git 和脚本声明的下载位置。
- 按提示处理已有目标，再从配置的远端克隆脚本库。
- 给下载入口补执行权限并打开输出目录。


### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】♻️双击Git 提交回退.command](./%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BBGit%20%E6%8F%90%E4%BA%A4%E5%9B%9E%E9%80%80.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 为选中的 Git 仓库选择历史目标并执行回退。

- 定位当前仓库或子仓，检查可用的历史记录。
- 选择回退目标与模式，核对即将影响的提交和工作区。
- 按脚本确认后执行回退并打印状态。
  - 如果选择 hard，工作区修改可能丢失；先核对备份和确认提示。


### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](./%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%81%A2%E5%A4%8D%E8%AF%AF%E5%88%A0%E6%9C%AC%E5%9C%B0Git%E5%B7%B2%E5%82%A8%E8%97%8F%E7%9A%84%E8%B5%84%E6%96%99.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E5%8F%8C%E5%87%BB%E6%81%A2%E5%A4%8D%E8%AF%AF%E5%88%A0%E6%9C%AC%E5%9C%B0Git%E5%B7%B2%E5%82%A8%E8%97%8F%E7%9A%84%E8%B5%84%E6%96%99.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 从本地 Git 悬空对象中寻找并恢复误删资料。

- 在目标仓运行对象检查，列出可恢复的提交或文件对象。
- 选择恢复分支或文件名，核对对象内容。
- 按所选方式恢复到工作区或分支，并输出后续审查提示。


### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】♻️批量Git提交（不含推送）.command](./%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%89%B9%E9%87%8FGit%E6%8F%90%E4%BA%A4%EF%BC%88%E4%B8%8D%E5%90%AB%E6%8E%A8%E9%80%81%EF%BC%89.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%89%B9%E9%87%8FGit%E6%8F%90%E4%BA%A4%EF%BC%88%E4%B8%8D%E5%90%AB%E6%8E%A8%E9%80%81%EF%BC%89.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 为所选范围的本地仓库批量创建提交。

- 输入起点目录并选择待处理仓库范围。
- 遍历 Git 工作树，检查并暂存脚本范围内的修改。
- 为有变更的仓库创建提交并汇总结果，不执行推送。


### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】♻️检测并转换为子Git.command](./%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%A3%80%E6%B5%8B%E5%B9%B6%E8%BD%AC%E6%8D%A2%E4%B8%BA%E5%AD%90Git.command/%E3%80%90MacOS%E3%80%91%E2%99%BB%EF%B8%8F%E6%A3%80%E6%B5%8B%E5%B9%B6%E8%BD%AC%E6%8D%A2%E4%B8%BA%E5%AD%90Git.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 检查本地嵌套仓库并按选择转换为父仓子模块。

- 准备 [**Python**](https://www.python.org/) 环境并选择起点目录。
- 扫描可处理仓库，核对子仓远端和父子关系并展示计划。
- 按选择备份、转换和登记，完成后检查父仓差异；不应把此操作当纯扫描。


### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](./%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%B8%BA%E7%A7%81%E4%BA%BA%E8%B4%A6%E6%88%B7%E7%94%9F%E6%88%90%20SSH%20%E5%AF%86%E9%92%A5%EF%BC%88%E5%8A%A0%E5%AF%86%E6%89%8B%E6%AE%B5%EF%BC%9ARSA%204096%20%2B%20ED25519%20%E4%BA%8C%E9%80%89%E4%B8%80%EF%BC%89.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E4%B8%BA%E7%A7%81%E4%BA%BA%E8%B4%A6%E6%88%B7%E7%94%9F%E6%88%90%20SSH%20%E5%AF%86%E9%92%A5%EF%BC%88%E5%8A%A0%E5%AF%86%E6%89%8B%E6%AE%B5%EF%BC%9ARSA%204096%20%2B%20ED25519%20%E4%BA%8C%E9%80%89%E4%B8%80%EF%BC%89.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 为个人账号生成并配置 [**SSH**](https://www.openssh.com/) 登录密钥。

- 选择 RSA 4096 或 ED25519，填写邮箱和密钥保存位置。
- 检查既有密钥，按提示生成密钥并配置 SSH config 与 agent。
- 打开公钥设置页面，并按选择验证连接；私钥留在本机。


### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】⚙️双击生成Github远程仓库URL.command](./%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E7%94%9F%E6%88%90Github%E8%BF%9C%E7%A8%8B%E4%BB%93%E5%BA%93URL.command/%E3%80%90MacOS%E3%80%91%E2%9A%99%EF%B8%8F%E5%8F%8C%E5%87%BB%E7%94%9F%E6%88%90Github%E8%BF%9C%E7%A8%8B%E4%BB%93%E5%BA%93URL.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 调用 [**GitHub**](https://github.com) API 创建仓库并取得网页地址。

- 检查 [**Homebrew**](https://brew.sh/) / jq，输入账号、Token 和新仓名。
- 向 GitHub 创建仓库接口发送请求。
- 提取返回 URL 并打开浏览器；此操作会创建真实远端仓库。


### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS】⬆️Git添加子模块.command](./%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8FGit%E6%B7%BB%E5%8A%A0%E5%AD%90%E6%A8%A1%E5%9D%97.command/%E3%80%90MacOS%E3%80%91%E2%AC%86%EF%B8%8FGit%E6%B7%BB%E5%8A%A0%E5%AD%90%E6%A8%A1%E5%9D%97.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按内置清单重新建立子模块并记录父仓提交。

- 核对脚本清单、执行目录和已有子模块。
- 按源码流程清理现有子模块，再添加与下载目标清单。
- 更新子模块到配置分支并记录指针，处理父仓提交与远端配置；会删除重建关联。


### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【MacOS】🎬上传GitHub视频附件.command](./%E3%80%90MacOS%E3%80%91%F0%9F%8E%AC%E4%B8%8A%E4%BC%A0GitHub%E8%A7%86%E9%A2%91%E9%99%84%E4%BB%B6.command/%E3%80%90MacOS%E3%80%91%F0%9F%8E%AC%E4%B8%8A%E4%BC%A0GitHub%E8%A7%86%E9%A2%91%E9%99%84%E4%BB%B6.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 上传本地视频为 GitHub 附件并取得可粘贴 URL。

- 输入仓库地址与 MP4 / MOV / WEBM 文件，校验文件和格式。
- 检查 gh 登录和目标仓库写权限。
- 上传附件，输出并复制 URL；重复执行会产生新附件，不自动改 README。


### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【MacOS】🔍Git依据提交日志关键字查找.command](./%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E4%BE%9D%E6%8D%AE%E6%8F%90%E4%BA%A4%E6%97%A5%E5%BF%97%E5%85%B3%E9%94%AE%E5%AD%97%E6%9F%A5%E6%89%BE.command/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E4%BE%9D%E6%8D%AE%E6%8F%90%E4%BA%A4%E6%97%A5%E5%BF%97%E5%85%B3%E9%94%AE%E5%AD%97%E6%9F%A5%E6%89%BE.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 按提交说明关键词定位历史记录。

- 确定目标 Git 仓库并输入搜索关键词。
- 筛选提交记录，在列表中选择要查看的提交。
- 显示提交号、作者、时间与标题，按提示继续查询。


### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【MacOS】🔍Git寻找分支最近的一次原始切点.command](./%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E5%AF%BB%E6%89%BE%E5%88%86%E6%94%AF%E6%9C%80%E8%BF%91%E7%9A%84%E4%B8%80%E6%AC%A1%E5%8E%9F%E5%A7%8B%E5%88%87%E7%82%B9.command/%E3%80%90MacOS%E3%80%91%F0%9F%94%8DGit%E5%AF%BB%E6%89%BE%E5%88%86%E6%94%AF%E6%9C%80%E8%BF%91%E7%9A%84%E4%B8%80%E6%AC%A1%E5%8E%9F%E5%A7%8B%E5%88%87%E7%82%B9.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 找出两条分支最近的共同历史起点。

- 确定 Git 仓库并列出可比较的分支。
- 选择两条分支，计算共同祖先或分叉起点。
- 输出提交信息，并按提示继续下一轮比较。


### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.Flutter.command](./%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.Flutter.command/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.Flutter.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。


### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](./%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.JobsOCBaseConfigDemo.command/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.JobsOCBaseConfigDemo.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。


### <span id="jobs-toc-heading-21" data-jobs-toc="v2">[【MacOS】🚪双击打开Github.JobsOCKit.command](./%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.JobsOCKit.command/%E3%80%90MacOS%E3%80%91%F0%9F%9A%AA%E5%8F%8C%E5%87%BB%E6%89%93%E5%BC%80Github.JobsOCKit.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开脚本预设的 GitHub 项目主页。

- 阅读入口自述并继续。
- 读取脚本内固定的项目 URL。
- 使用默认浏览器打开该主页。


### <span id="jobs-toc-heading-22" data-jobs-toc="v2">[【MacOS】🧮双击统计MD文件的有效行数.command](./%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E5%8F%8C%E5%87%BB%E7%BB%9F%E8%AE%A1MD%E6%96%87%E4%BB%B6%E7%9A%84%E6%9C%89%E6%95%88%E8%A1%8C%E6%95%B0.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%AE%E5%8F%8C%E5%87%BB%E7%BB%9F%E8%AE%A1MD%E6%96%87%E4%BB%B6%E7%9A%84%E6%9C%89%E6%95%88%E8%A1%8C%E6%95%B0.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装统计 Markdown 有效行数的提交钩子。

- 确认脚本位于目标 Git 项目，检查 .git。
- 写入 pre-commit：提交时扫描 Markdown、计算有效行数并更新统计内容。
- 给钩子补执行权限并显示安装结果；后续提交会触发该钩子。


### <span id="jobs-toc-heading-23" data-jobs-toc="v2">[【MacOS】🧹清理Git子仓运行态记录.command](./%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E6%B8%85%E7%90%86Git%E5%AD%90%E4%BB%93%E8%BF%90%E8%A1%8C%E6%80%81%E8%AE%B0%E5%BD%95.command/%E3%80%90MacOS%E3%80%91%F0%9F%A7%B9%E6%B8%85%E7%90%86Git%E5%AD%90%E4%BB%93%E8%BF%90%E8%A1%8C%E6%80%81%E8%AE%B0%E5%BD%95.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 让运行态记录退出 Git 跟踪，同时保留本机文件。

- 定位外层仓库及 .gitmodules 中的子仓，确认待处理范围。
- 输入 YES 后，为各仓补齐运行态忽略规则。
- 将匹配的已跟踪运行态路径从索引移除，真实文件不删除；完成后检查各仓差异。


<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
