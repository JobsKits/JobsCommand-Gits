# `MacOS`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行与路径](#jobs-toc-heading-2)
- [二、入口清单](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本目录保留原有 20 个 MacOS 脚本包及各自资源、测试和 README。统计依据为当前目录内同名 `.command` 主脚本，时间为 2026-10-23。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与路径 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击各包中的同名 `.command`，用途和风险见包内 README。需要 macOS、zsh 及各脚本声明的工具。原脚本相对资源随包迁移；需要仓根的关联、下载与清理入口会识别本平台层，定位实际 Git 工作树。引用修复入口名中的 `>` 使用全角 `＞`，兼容 Windows 检出文件名。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、入口清单 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](<./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command/README.md>)：逐层查询目标分支最新，完成标记匹配时跳过该仓下载但继续检查后代；持久对象缓存、限时重试及临时工作树核验后发布，默认不提交、不推送。
- [【MacOS】⏬双击下载SourceTree效率脚本.command](<./【MacOS】⏬双击下载SourceTree效率脚本.command/README.md>)：删除当前用户既有 SourceTree.command 目录后浅克隆，添加脚本执行权限并打开目录；没有自动备份。
- [【MacOS】♻️双击Git 提交回退.command](<./【MacOS】♻️双击Git 提交回退.command/README.md>)：选择上一提交 / tag 的 soft 或 hard，或 reflog soft 回退；不创建恢复分支，hard 无额外 YES 门禁。
- [【MacOS】♻️双击恢复误删本地Git已储藏的资料.command](<./【MacOS】♻️双击恢复误删本地Git已储藏的资料.command/README.md>)：批量恢复 dangling commit/tree，尝试合入当前分支，并导出、暂存 blob；可能产生冲突。
- [【MacOS】♻️批量Git提交（不含推送）.command](<./【MacOS】♻️批量Git提交（不含推送）.command/README.md>)：扫描实体 .git 目录并排序，自动 add/commit，有改动才提交；不保证子仓先于父仓，不推送。
- [【MacOS】♻️检测并转换为子Git.command](<./【MacOS】♻️检测并转换为子Git.command/README.md>)：扫描独立嵌套 Git，逐仓预检、备份、登记并使用 Git 官方命令归集元数据。
- [【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command](<./【MacOS】⚙️双击为私人账户生成 SSH 密钥（加密手段：RSA 4096 + ED25519 二选一）.command/README.md>)：默认 ED25519 / 可选 RSA4096，生成 id_rsa_personal、加载 agent、复制公钥并打开设置页；须核对 Host 的 IdentityFile。
- [【MacOS】⚙️双击生成Github远程仓库URL.command](<./【MacOS】⚙️双击生成Github远程仓库URL.command/README.md>)：输入令牌与仓名，通过 curl 调用 GitHub 创建 API，仅提交 name；输出并打开返回 URL。
- [【MacOS】⬆️Git添加子模块.command](<./【MacOS】⬆️Git添加子模块.command/README.md>)：直接删除旧子模块与关联，按五仓清单重建并自动创建本地提交；不推送，无自动备份。
- [【MacOS】🌐双击配置Git动态代理.command](<./【MacOS】🌐双击配置Git动态代理.command/README.md>)：配置当前用户 Git 动态入口；系统代理可达优先、不可达再直连，支持检查与精确恢复。
- [【MacOS】🎬上传GitHub视频附件.command](<./【MacOS】🎬上传GitHub视频附件.command/README.md>)：上传 MP4/MOV/WEBM 到 GitHub 附件并复制 URL；不修改 README、不提交。
- [【MacOS】🔍Git依据提交日志关键字查找.command](<./【MacOS】🔍Git依据提交日志关键字查找.command/README.md>)：从当前分支合并描述推断来源，未命中时用关键词搜索 HEAD 第一父链 / 全历史并展示锚点。
- [【MacOS】🔍Git寻找分支最近的一次原始切点.command](<./【MacOS】🔍Git寻找分支最近的一次原始切点.command/README.md>)：选择目标分支，结合 reflog、fork-point / merge-base 与候选排名输出推测父分支和分叉证据。
- [【MacOS】🚪双击打开Github.Flutter.command](<./【MacOS】🚪双击打开Github.Flutter.command/README.md>)：使用 macOS 默认浏览器打开 Flutter 官方源码仓库。
- [【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command](<./【MacOS】🚪双击打开Github.JobsOCBaseConfigDemo.command/README.md>)：使用 macOS 默认浏览器打开 JobsOCBaseConfigDemo 仓库。
- [【MacOS】🚪双击打开Github.JobsOCKit.command](<./【MacOS】🚪双击打开Github.JobsOCKit.command/README.md>)：使用 macOS 默认浏览器打开 JobsOCKit 仓库。
- [【MacOS】🧭更新引用Git父仓=＞子仓.command](<./【MacOS】🧭更新引用Git父仓%3D＞子仓.command/README.md>)：依据磁盘现存子仓对齐登记和 gitlink，备份配置与索引，保留源码与远端。
- [【MacOS】🧮双击统计MD文件的有效行数.command](<./【MacOS】🧮双击统计MD文件的有效行数.command/README.md>)：安装 pre-commit 有效行数钩子，已有钩子停止；提交时会更新标记并整文件暂存，部分暂存需自行核查。
- [【MacOS】🧹清理Git子仓运行态记录.command](<./【MacOS】🧹清理Git子仓运行态记录.command/README.md>)：为登记子仓补运行态忽略规则，并移除运行态索引记录，保留真实文件。
- [【MacOS】🧾更新gitmodules.command](<./【MacOS】🧾更新gitmodules.command/README.md>)：增量登记现有直属独立子仓，保留已有 URL/branch/扩展字段和 gitlink。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
