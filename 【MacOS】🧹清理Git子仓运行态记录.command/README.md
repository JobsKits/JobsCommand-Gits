# `Git` 子仓运行态记录清理工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 一、用途

这个工具用于处理“大 Git 管多个小 Git / 子模块”的仓库结构中，运行态目录被误加入 Git 跟踪的问题。

典型场景：

- 子仓库里出现 `codex配置文件夹/`、`.codex/sessions/`、`.codex/logs*.sqlite` 等运行态文件。
- 提交时出现大量 `D`、`A`、`M`，导致正常配置改动被运行缓存淹没。
- 外层仓库只应该记录子模块指针，但子模块自己的索引里混入了 Codex 缓存、插件缓存、会话记录、sqlite 状态库。

脚本只做两类动作：

1. 给外层仓库和子仓库补齐 `.gitignore` 运行态忽略规则。
2. 对已经被 Git 跟踪的运行态路径执行 `git rm --cached`，只从索引移除，不删除本地真实文件。

---

## 二、运行方式

双击运行：

```shell
【MacOS】🧹清理Git子仓运行态记录.command
```

终端运行：

```shell
./'【MacOS】🧹清理Git子仓运行态记录.command/【MacOS】🧹清理Git子仓运行态记录.command'
```

也可以先只预览，不改索引：

```shell
DRY_RUN=1 ./'【MacOS】🧹清理Git子仓运行态记录.command/【MacOS】🧹清理Git子仓运行态记录.command'
```

---

## 三、注意事项

- 脚本不会创建提交，不会推送远端。
- 脚本不会删除真实文件，只会让 Git 停止跟踪运行态文件。
- 真正提交前建议分别检查外层仓库和被清理的子仓库：

```shell
git status --short
git -C '💻JobsCodexConfigs' status --short
```

<a id="🔚" href="#一用途" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
