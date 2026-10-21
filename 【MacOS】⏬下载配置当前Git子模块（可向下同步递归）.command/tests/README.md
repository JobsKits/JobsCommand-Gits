# 子模块下载入口隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行目录与依赖](#jobs-toc-heading-2)
- [二、测试文件](#jobs-toc-heading-3)
- [三、目录过滤器验收边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 本目录使用临时仓库验证下载入口，不运行真实业务入口；说明对应上一级 [README](../README.md) 的离线验证。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行目录与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 `python3`、`zsh`、`git`；目录过滤器回归另需 `node`。保留 `JobsGenesis` 与同级 `JobsBaseConfig` 中当前 7 份下载入口的相对位置，以及 `JobsCommand@Gits/.jobs-markdown-toc/MarkdownToc.mjs`。在本目录运行：

```shell
python3 -B -m unittest discover -s . -p 'test_*.py'
```

只检查目录过滤器的同步行为：

```shell
python3 -B -m unittest test_markdown_toc_checkout
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、测试文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 覆盖范围 |
| --- | --- |
| [test_downloaders_latest.py](./test_downloaders_latest.py) | 入口副本清单、定位、菜单与分支最新同步。 |
| [test_recursive_downloads.py](./test_recursive_downloads.py) | 多层分支、相对地址、子树边界与缓存保护。 |
| [test_dirty_confirmation.py](./test_dirty_confirmation.py) | 逐仓确认、已有改动与失败停止。 |
| [test_source_logging.py](./test_source_logging.py) | 来源地址、配置作用域与脱敏日志。 |
| [test_gitee_https_transport.py](./test_gitee_https_transport.py) | 当前进程的 Gitee HTTPS 兼容与配置保留。 |
| [test_markdown_toc_checkout.py](./test_markdown_toc_checkout.py) | 预取对象库克隆后，在真实远端配置生效时首次检出 `[toc]`；无更新恢复与后续分支更新。 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录过滤器验收边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`test_markdown_toc_checkout.py` 从 7 份真实下载入口提取内嵌引擎，使用两层子模块、本地 bare 远端、精确 `includeIf hasconfig:remote.*.url` 和隔离可信转换器。过滤器事件记录首次 smudge 的真实来源地址、调用位置及文件是否尚未写入，避免事后恢复掩盖首次检出漏用过滤器。

测试还覆盖无更新时旧生成态恢复、未提交正文与既有索引保护、无过滤器时缺少 Node 也直接跳过、有过滤器但工具缺失或 process 冲突时停止。整次测试不自动安装过滤器，检查 HEAD 与索引仍为发布目录、本地为 `[toc]`，并核对隔离配置未被同步代码改写。

所有测试只在临时目录产生仓库、工具副本与日志。目录过滤器测试保留原 `HOME`，使用 `GIT_CONFIG_GLOBAL`、禁用系统配置及本地协议重定向隔离，不访问真实远端，不修改用户全局 Git 配置。临时目录由测试结束时回收；失败详情保留在测试输出中。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
