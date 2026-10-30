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
| [test_download_resume.py](./test_download_resume.py) | 持久对象缓存跨失败复用、远端 SHA 与完成标记失效 / 跳过、父仓标记后的后代检查、重试 / 认证 / 超时 / 信号 / 脱敏及锁生命周期。 |
| [test_download_transport_tty.py](./test_download_transport_tty.py) | 两项真实隔离 PTY 测试：认证交互、`Ctrl+C` 后进程清理与终端恢复。 |
| [test_download_audit.py](./test_download_audit.py) | 中断后补齐登记、首次检出失败重跑、索引隐藏内容保护、分支未变时的 tags 同步及空缓存恢复。 |
| [test_download_transport_audit.py](./test_download_transport_audit.py) | 查询重试丢弃失败部分输出、一次查询解析分支与 SHA、歧义拒绝、真实入口锁释放 / 竞争。 |
| [test_downloader_blueprint.py](./test_downloader_blueprint.py) | 父仓一次精确 fetch 后本地 rebase、失败 / 冲突即停、健康 Brew 复用、共享引擎白名单导出、未完成 Git 与隐藏索引内容保护。 |

按需检查下载缓存、完成标记和传输边界，在本目录运行；下面的选择不会启动真实下载：

```shell
python3 -B \
  -m unittest \
  test_download_resume \
  test_download_transport_tty \
  test_download_audit \
  test_download_transport_audit
```

这些测试使用临时 Git 仓、file 传输或本地命令替身；PTY 只负责真实终端交互，不接触真实远端。测试成功仅覆盖指定边界，不能代替目标电脑的实际网络下载或托管平台验收。

只检查蓝本的父仓、依赖和共享引擎边界，在本目录运行：

```shell
python3 -B -m unittest test_downloader_blueprint
```

`test_downloader_blueprint.py` 不执行真实 Brew 更新或业务仓拉取：父仓获取与 rebase 使用隔离远端 / 命令替身，冲突用例保留两端历史；共享渲染器测试检查只导出所需函数，不混入外层维护状态。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录过滤器验收边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`test_markdown_toc_checkout.py` 从 7 份真实下载入口加载内嵌流程与白名单共用函数，使用两层子模块、本地 bare 远端、精确 `includeIf hasconfig:remote.*.url` 和隔离可信转换器。过滤器事件记录首次 smudge 的真实来源地址、调用位置及文件是否尚未写入，避免事后恢复掩盖首次检出漏用过滤器。

测试还覆盖无更新时旧生成态恢复、未提交正文与既有索引保护、无过滤器时缺少 Node 也直接跳过、有过滤器但工具缺失或 process 冲突时停止。整次测试不自动安装过滤器，检查 HEAD 与索引仍为发布目录、本地为 `[toc]`，并核对隔离配置未被同步代码改写。

所有测试只在临时目录产生仓库、工具副本与日志。目录过滤器测试保留原 `HOME`，使用 `GIT_CONFIG_GLOBAL`、禁用系统配置及本地协议重定向隔离，不访问真实远端，不修改用户全局 Git 配置。临时目录由测试结束时回收；失败详情保留在测试输出中。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
