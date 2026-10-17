# `【MacOS】🧾更新gitmodules.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

这个脚本把父仓第一层新增的独立 [**Git**](https://git-scm.com/) 仓库登记为子模块，一次运行完成 `.gitmodules`、父仓 gitlink、本地子模块配置与 Git 元数据归集。关联结果留在本地供检查，不创建提交或推送，也不访问远端。

脚本可以直接放在父仓根目录，或放在父仓下一层的同名脚本目录中；目标目录根据脚本自身位置确定，与终端当前目录无关。

<strong id="submodule-quick-look">先看例子：新增关联时，怎样登记成多平台可用的地址</strong>

以下用 `JobsGenesis` 父仓中已有的 `JobsCommand@Flutter` 子模块演示本通用工具的地址规则。以前固定到 [**GitHub**](https://github.com)：

```ini
url = https://github.com/JobsKits/JobsCommand-Flutter.git
```

确认各平台映射满足条件后，共享配置使用相对地址：

```ini
[submodule "JobsCommand@Flutter"]
    path = JobsCommand@Flutter
    url = ../JobsCommand-Flutter.git
    branch = main
```

同一条 `url` 根据父仓默认 remote 地址解析，支持 [**Gitee**](https://gitee.com) 和任意自建平台；自建地址仅作示例：

| 父仓默认 remote 地址 | 子仓实际地址 |
| --- | --- |
| `https://github.com/JobsKits/JobsGenesis.git` | `https://github.com/JobsKits/JobsCommand-Flutter.git` |
| `https://gitee.com/JobsGo/JobsGenesis.git` | `https://gitee.com/JobsGo/JobsCommand-Flutter.git` |
| `ssh://git@git.example.com:2222/team/tools/JobsGenesis.git` | `ssh://git@git.example.com:2222/team/tools/JobsCommand-Flutter.git` |

`path` 是本地目录名，`url` 中必须写真实远端仓名；`JobsCommand@Flutter` 与 `JobsCommand-Flutter.git` 可以不同。目标平台必须已有子仓镜像，并包含父仓 gitlink 指定的提交。

本脚本负责**增补关联**：新增条目只有在父子全部已配置线路逐一同站、同命名空间且子仓名一致时，才登记相对 URL；条件不满足则保留明确原地址。已有 section、URL、branch 和扩展字段保持原样，不会把旧的固定 GitHub URL 批量改成相对地址，也不会把共享相对 URL 写回子仓真实 `origin`。登记过程不联网、不提交、不推送；具体保留范围见后文。

## 一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 已把一个独立 Git 仓库放到父仓第一层，希望父仓通过子模块管理它。
- 已有 `.gitmodules` 登记，但父仓尚未建立对应 gitlink，需要补齐关联。
- 已登记子模块的工作目录仍保留 `.git` 文件夹，需要使用 Git 官方命令归集元数据。
- 希望先预检关联计划，再决定是否执行。

扫描只覆盖目标父仓的第一层真实子 Git 目录，不递归接管孙仓，不把普通目录初始化为仓库。

## 二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 双击同目录的 `【MacOS】🧾更新gitmodules.command`，或从终端运行：

  ```shell
  /bin/zsh './【MacOS】🧾更新gitmodules.command'
  ```

- 只预检并展示计划，兼容非交互环境：

  ```shell
  /bin/zsh './【MacOS】🧾更新gitmodules.command' --dry-run
  ```

  也可以使用环境变量：

  ```shell
  DRY_RUN=1 /bin/zsh './【MacOS】🧾更新gitmodules.command'
  ```

- 查看参数说明：

  ```shell
  /bin/zsh './【MacOS】🧾更新gitmodules.command' --help
  ```

正常执行先展示内置自述，按回车进入预检；展示关联计划后，直接回车跳过，输入任意非空字符后回车执行整套关联。确认前可按 `Ctrl+C` 取消，不需要再手动执行 `git add`、`git submodule init` 或 `git submodule absorbgitdirs`。

普通执行必须在可交互终端中运行；自动检查使用 `--dry-run`。脚本不提供 `--repo` 参数，需要处理哪个父仓，就运行放在该父仓中的脚本副本。

## 三、关联与保留规则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 对象 | 处理规则 |
| --- | --- |
| 新增独立子仓 | 从已有 `origin` 读取明确 URL；只有父子全部已配置线路逐一同站同命名空间、子仓名称一致时，登记为 `../仓库名.git`；仅新 section 跟随当前分支。 |
| 已有 `.gitmodules` | 保留原 section 名、URL、相对 URL、branch 和其它扩展配置；缺 URL 时从子仓 `origin` 补齐，不补加原本缺失的 branch；磁盘上暂缺的目录也保留登记。 |
| 新增或缺失的 gitlink | 将子仓当前 `HEAD` 登记到父仓索引，作为待提交的子模块指针。 |
| 已有 gitlink | 保留原指针，包括用户已经暂存的版本；不会随子仓当前 `HEAD` 自动升级。 |
| 父仓本地配置 | 补齐缺失的子模块初始化登记，保留已有本地配置，不执行会覆盖 URL 的 `git submodule sync`。 |
| 子仓远端与源码 | 保留原远端、分支、提交、工作区和索引，不提交子仓修改。 |
| 子仓 Git 元数据 | 对需要归集的 `.git` 文件夹运行 `git submodule absorbgitdirs`，移入父仓实际 Git 目录下的 `modules/`，子仓根部改为 `.git` 指针文件。 |
| 父仓其它暂存内容 | 原样保留，不进行全仓 `git add`。 |

执行前会在父仓实际 Git 目录内建立独立备份，保存父仓索引、本地配置和 `.gitmodules`；执行后核验登记、gitlink、元数据指针和父子仓状态。备份不包含全部源码或整个子仓历史，不能替代日常仓库备份。

共享相对 URL 会继承父仓默认远端的站点、命名空间和传输方式，适用于 [**GitHub**](https://github.com)、[**Gitee**](https://gitee.com) 或其它已配置托管平台；平台之间的命名空间可以不同，但每个平台上的父子仓必须同命名空间且子仓名称一致。检测支持 HTTPS、scp 风格 SSH 和带端口的 `ssh://`，包括多层命名空间；自定义端口和协议无法证明属于同一服务时不转换。

跨命名空间、某线路缺少映射、两平台子仓异名、本地文件路径或未知协议均保留明确原地址，并在计划日志中提示。脚本不创建镜像仓库，不根据目录名猜远端，也不验证服务端是否保存了父仓 gitlink 对应的提交；受限环境仍需要先把子仓及指定提交同步到可访问的平台。已有绝对 URL 和原本缺失的 branch 保持原样，修改存量登记须单独审查。

`JobsBaseConfig` 根目录保留的旧入口只负责增量写入 `.gitmodules`，不暂存 gitlink、不初始化或归集元数据；同样保留已有 section、URL、branch、扩展字段及暂缺工作目录的登记，并采用上述新增 URL 规则。其只读入口为 `DRY_RUN=1`，不支持这里的 `--dry-run` 参数。

## 四、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 确认脚本位于目标父仓根目录，或其下一层的同名脚本目录中；运行环境需要可用的 `/bin/zsh` 和 `git`。
- 新增子仓必须已有提交和可读取的 `origin` URL。尚未提交的空仓或缺少远端的子仓会阻断执行，应先在子仓中完成配置。
- 待关联目录若已被父仓当作普通文件树跟踪，脚本会停止，不自动移除原索引内容。
- 存在未解决冲突、关联配置不一致、父仓或子仓属于链接工作树、元数据目标被占用时，整次预检失败；子仓 `.git` 指向本父仓 `modules/` 之外的外部元数据也会阻断，不自动搬移、覆盖或合并。
- 已受跟踪的 `.gitmodules` 工作区与暂存区内容不同会阻断执行；已经暂存且工作区内容一致时允许继续。`.gitmodules` 或已有 gitlink 被暂存删除时同样停止，保留用户原有删除选择。其它已有暂存内容保留。
- 已有 gitlink 的版本推进需要自行审查和暂存；运行关联脚本不会把父仓指针自动更新到子仓最新版本。

缺失目录的旧登记不会自动删除。需要移除子模块时，应单独确认目录、配置与索引的清理范围。

## 五、日志、备份与失败处理 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 日志位于系统临时目录中的 `【MacOS】🧾更新gitmodules.<PID>.log`，按进程区分，实际路径会在运行时显示。
- 执行前备份位于父仓实际 Git 目录内，实际备份路径会写入日志。
- 预检发现问题时先处理报告中的冲突，再重跑预检，不要强行删除 `.git` 或 `modules/`。
- 执行中失败会报告失败阶段和备份位置。已完成的本地步骤可能保留，脚本不会自动回滚源码；按日志核对当前状态和备份后再处理。
- 预检模式不改父子仓关联配置、索引或 Git 元数据；`--help` 只显示说明。

## 六、运行后检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在目标父仓中检查：

```shell
git status --short
git diff --cached -- .gitmodules
git submodule status
```

新增关联已经暂存，仍需自行审查后决定是否提交、推送。若子仓有未提交内容，或当前检出提交与父仓保留的既有 gitlink 不同，父仓仍可能显示子模块有改动；关联脚本会保留这些状态。

配套隔离回归使用 [**Python**](https://www.python.org) 标准库创建临时 Git 仓库，不在真实项目中执行关联。在本文目录运行：

```shell
python3 './tests/test_association.py'
```

也可以把其它完整关联脚本副本路径作为参数传入。44 项用例覆盖新增登记、多平台 URL、歧义地址回退、脏工作区和索引保护、重复运行、工作树与元数据冲突、只读预览、失败中断和脚本锁清理；测试日志与临时仓库保留在输出显示的系统临时目录。

以下隔离回归同时核对 6 份登记入口与 5 份引用修复入口的 URL 判断、旧入口增量保留、section 与 URL / branch / 扩展字段保留，以及真实 origin 和共享登记 URL 的边界：

```shell
python3 './tests/test_url_writers.py'
```

## 七、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- **为什么新增子仓没有被关联？** 先看日志确认它在父仓第一层、有独立 `.git`、已有提交且配置了 `origin`，再检查是否存在阻断条件。直接回车会跳过写入，执行时需要在计划确认处输入任意非空字符。
- **为什么重新运行没有更新子仓版本？** 已有 gitlink 刻意保留，版本推进属于另一个待审查的变更；此脚本只补齐新增或缺失的关联。
- **为什么已有相对 URL 没变成 `origin`？** 原 `.gitmodules` URL 会保留，适合同站相对地址或用户已有的克隆策略。
- **为什么子仓 `.git` 变成文件？** 这是官方子模块元数据归集后的正常布局，独立历史、远端与分支仍然存在。
- **能自动提交或推送吗？** 不能。关联只在本地执行，不联网，不创建提交，不推送父仓或子仓。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
