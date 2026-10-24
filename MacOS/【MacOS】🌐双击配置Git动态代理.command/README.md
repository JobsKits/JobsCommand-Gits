# [**Git**](https://git-scm.com/) 动态代理双击配置工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、配置结果速览](#result)
- [二、运行方式](#usage)
- [三、每次 Git 操作如何选路](#routing)
- [四、适用边界](#scope)
- [五、备份、日志与恢复](#restore)
- [六、目录与隔离验证](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

双击同目录的 `【MacOS】🌐双击配置Git动态代理.command`，先阅读脚本内置自述，再按回车配置当前用户的终端与已安装的 [**Sourcetree**](https://www.sourcetreeapp.com/)。普通 HTTP / HTTPS Git 命令默认优先使用当前系统中可达的代理；代理未启用或不可达时，再短时探测直连，不绑定某个 VPN 软件或固定端口。

主脚本内嵌运行态代码，复制这一个 `.command` 文件即可运行，不依赖 `JobsMacEnv`、相邻仓库或在线下载。此 README 是运行前说明；脚本头部注释负责源码自述，运行时内置自述直接写在脚本内，三层说明相互配合，脚本不会读取 README 代替内置自述。

## 一、<span id="result">配置结果速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 项目 | 实际范围 |
| --- | --- |
| 运行环境 | [**macOS**](https://www.apple.com/macos/) 自带的 `zsh`、[**Perl**](https://www.perl.org/)、Git 与 [**curl**](https://curl.se/) 等工具；系统 Git 必须已可用，脚本不安装依赖。 |
| 运行态入口 | 当前用户 `Library/Application Support/JobsGitNetworkStrategy/runtime/bin/git`。 |
| 终端配置 | 仅在当前用户 `.zshrc` 末尾写入 `JOBS_GIT_DYNAMIC_PROXY_BEGIN` / `JOBS_GIT_DYNAMIC_PROXY_END` 受控 PATH 块，保留已有 `JobsMacEnv`、Git 函数与其它内容。 |
| Sourcetree 配置 | 检测到应用时，仅将 `gitWhichOne` 设为整数 `1`、`gitCustomPath` 设为运行态路径字符串。 |
| 网络选择 | 每次网络操作读取当前系统代理，代理可达优先；不可用时回到可达直连。 |
| 原始 Git 业务 | 选路完成后最多执行一次，不因实际业务失败重放克隆或推送。 |
| 安装状态 | 保存精确备份和脱敏审计；重复安装幂等，支持检查与恢复。 |

配置操作不修改系统代理、`.gitconfig` 或项目 remote，不创建提交、不推送远端。运行时选中的代理只影响该次 Git 进程及其适用的子进程，不写入持久 Git 代理配置。

## 二、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令均在本 README 所在目录运行。

| 入口 | 用途 |
| --- | --- |
| 直接双击主脚本，或不带参数运行 | 展示自述与菜单；直接回车配置，输入 `C` 检查、`R` 恢复，其它输入取消；`Ctrl+C` 随时取消。 |
| `--install` | 显式授权无交互配置；仍打印用途、修改范围与日志位置。 |
| `--check` | 无交互检查运行态、终端挂载与 Sourcetree 偏好，不创建目录、日志或快照，不修改配置。 |
| `--restore` | 按回车确认后，恢复最新一次安装前或升级前的精确状态；`Ctrl+C` 取消。 |

```zsh
/bin/zsh './【MacOS】🌐双击配置Git动态代理.command' --install
/bin/zsh './【MacOS】🌐双击配置Git动态代理.command' --check
```

无交互环境中，不带参数与 `--restore` 会停止；只有明确的 `--install` 配置授权或只读 `--check` 才能连续执行。

配置后新开终端使用普通 `git clone`、`git fetch`、`git pull`、`git ls-remote`、`git push`。当前已打开的终端需要重新载入用户配置，才能读到新 PATH 挂载。

Sourcetree 正在运行时，脚本不会强制结束应用或中断在途任务。请先保存工作、等待 Git 操作结束，再正常退出并重新打开 Sourcetree，使新的 Git 入口偏好生效；只看到配置已写入，不代表既有进程已切换。

## 三、<span id="routing">每次 Git 操作如何选路</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 对可明确识别的单目标 HTTP / HTTPS `clone`、`fetch`、`pull`、`ls-remote`、`push`，先保留用户已有的代理与旁路选择。
  - 显式 Git 代理、环境代理以及显式空代理优先，不自动覆盖；`NO_PROXY` / `no_proxy`、系统例外及简单主机旁路规则保持有效。
- 默认通过 `scutil --proxy` 实时读取当前已启用的 HTTPS、HTTP、SOCKS 代理，去重后逐个探测到目标站点的完整链路。
  - 探测使用无凭据 HEAD 请求；只检测本地端口监听不足以判定代理可用。候选返回 `407` 时继续检查其它候选。
  - 代理预检出现 TLS / 证书差异时，选定该候选，交给原始 Git 使用其 CA / 客户端证书配置验证一次，不关闭证书验证，也不继续换路。
- 没有启用代理、候选均不可达或命中旁路时，短时探测直连；直连可达后执行原始 Git。代理与直连均明确失败时，报告失败，业务命令不执行。
- 选中代理后，仅向本次 Git 注入目标站点范围的 `http.<url>.proxy`；原始命令开始后不再因错误切换线路或重放业务。

“代理失败再直连”发生在预检阶段。它不能保证当前网络在 VPN 关闭时仍能直连 [**GitHub**](https://github.com)；两条线路都不可达时，需要恢复可用网络。

## 四、<span id="scope">适用边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 情况 | 处理方式 |
| --- | --- |
| SSH、本地仓库与本地命令 | 原生透传，不进入 HTTP 动态代理策略。 |
| PAC 自动代理脚本 | 不执行 PAC；只读取系统中已启用、可直接使用的代理地址。 |
| 多 remote、多 URL、未知参数及不能可靠识别的调用 | 保守透传，不猜测或改写目标。 |
| 递归子模块及配置驱动的多目标操作 | 保留原生行为，不把一个站点的代理强加给其它站点。 |
| 认证、权限、证书、分支冲突与非快进拒绝 | 保留原始 Git 校验与退出结果，不以重试掩盖错误。 |

动态选路覆盖的是已挂载入口实际调用的 HTTP / HTTPS Git 命令。其它客户端、未重新载入配置的终端，以及直接调用其它 Git 可执行文件的工具，应分别核对实际入口，不能据此认定全系统网络已改变。

## 五、<span id="restore">备份、日志与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

当前用户 `Library/Application Support/JobsGitNetworkStrategy/` 下的文件按用途分开：

| 相对该目录的位置 | 用途 |
| --- | --- |
| `runtime/bin/git` | 安装后的独立 Git 入口，不需要保留原安装包才能运行。 |
| `installer/snapshots/` | 按时间与随机值区分的精确恢复快照，目录权限 `0700`、快照文件 `0600`。 |
| `installer/active` | 最新安装记录的快照指向。 |
| `installer/install.log` | 安装与恢复审计，权限 `0600`，仅记录 UTC 时间、动作与结果。 |

Git 动态选路审计另存于当前用户 `Library/Logs/JobsGitNetworkStrategy/push.log`；只记录脱敏的模式、主机、端口与退出码。快照区分偏好原本未设置、空值与已有值，并保留原类型；日志不记录凭据、完整命令参数或 Git 输出。

重复安装同一版本与配置不重复追加 PATH 块，也不新建快照；升级会保存上一有效版本。恢复前核对当前状态仍与工具写入值相符；发现用户或其它进程的后续修改时保留新状态并报告冲突，不用旧快照覆盖。未知的同名运行文件或不可信快照也会停止覆盖。

先保存工作并正常退出 Sourcetree，再执行恢复入口；脚本不会替用户强杀应用：

```zsh
/bin/zsh './【MacOS】🌐双击配置Git动态代理.command' --check
/bin/zsh './【MacOS】🌐双击配置Git动态代理.command' --restore
```

按回车确认后，只恢复最新一次安装涉及的运行文件、精确挂载块与两项偏好，保留后续无关的 shell 配置。首次安装可恢复安装前状态，升级可回到上一有效版本；同一记录重复恢复不会继续卸载更早版本。恢复完成后重新打开终端与 Sourcetree，核对原 Git 入口已生效。日常关闭代理不需要执行恢复，下一次 Git 操作会重新判断当前线路。

## 六、<span id="validation">目录与隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `./【MacOS】🌐双击配置Git动态代理.command` | 双击配置入口，内嵌 Git 动态网络运行态。 |
| `./README.md` | 使用、作用范围、恢复与验证说明；不是运行时依赖。 |
| `./tests/run.zsh` | 隔离用户目录中的配置、检查、重复安装与恢复回归。 |

```zsh
/bin/zsh -n './【MacOS】🌐双击配置Git动态代理.command'
/bin/zsh './tests/run.zsh'
```

安装器回归使用专属临时用户目录和真实测试文件，Sourcetree 应用检测及偏好读写由夹具替代，不对用户真实偏好或系统代理执行写操作。隔离测试通过说明安装与恢复边界符合断言，不能代替真实公网仓库和已重启 Sourcetree 的连接验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
