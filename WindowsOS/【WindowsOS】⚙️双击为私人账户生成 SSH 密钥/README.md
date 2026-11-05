# `【WindowsOS】⚙️双击为私人账户生成 SSH 密钥`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#jobs-toc-heading-2)
- [二、执行流程](#jobs-toc-heading-3)
- [三、依赖、日志与风险](#jobs-toc-heading-4)
- [四、验证边界](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

黑窗终端入口：通过 fzf 选择 ED25519 或 RSA 4096，填写一次个人邮箱后，自动生成或复用个人密钥、配置 OpenSSH、尝试加载 agent 和登记 GitHub 公钥。

对应 [MacOS 原入口](<../../MacOS/【MacOS】⚙️双击为私人账户生成 SSH 密钥.command/README.md>)。最低支持系统为 [**Windows**](https://www.microsoft.com/windows) 10，使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1+、[**fzf**](https://github.com/junegunn/fzf) 与 Windows 原生 OpenSSH；最低 build 和不同架构实机兼容性未锁定。默认邮箱为 `295060456@qq.com`，可在输入时替换；可选 [**GitHub CLI**](https://cli.github.com/) 用于自动登记。算法选择必须使用可正常运行的 fzf；缺失时停止并显示 `winget install --id junegunn.fzf -e` 和官方发布入口，不退回手输数字。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `【WindowsOS】⚙️双击为私人账户生成 SSH 密钥.cmd`，或在 PowerShell 中执行：

```powershell
powershell.exe -NoLogo -NoProfile -File '.\【WindowsOS】⚙️双击为私人账户生成 SSH 密钥.ps1'
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 首先显示内置自述，回车继续，其它输入取消；没有可交互终端时停止。随后使用 fzf：方向键或 Tab 选择，回车确认，列表提供“取消本轮”，Esc / Ctrl+C 也可取消；空选和选择器失败均不生成密钥。默认高亮“ED25519（推荐）”，可选择 RSA 4096。根菜单还可打开 GitHub 公钥网页、[GitHub Token 网页](https://github.com/settings/tokens)或本机密钥文件夹，操作后回到算法选择；仅显式打开文件夹时可创建尚不存在的 `.ssh`，重解析点仍停止。
- 算法建议：ED25519 是现代算法，密钥更短、签名通常更快，适合新环境；RSA 4096 用于不支持 ED25519 的旧系统。[GitHub 官方密钥生成说明](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)默认使用 ED25519，并给出旧系统采用 RSA 4096 的方式。
- 邮箱只收集一次；提示中的默认值固定为 `295060456@qq.com`，直接回车复用，也可输入其它邮箱替换，不会被全局 Git 邮箱覆盖。输入结束或邮箱无效立即停止。算法与邮箱确定后直接执行，不再询问保存路径、口令或重复生成确认。终端逐项显示结果、错误与待完成项。
- 在当前用户 `.ssh` 中寻找同算法、同邮箱且能非交互验证私钥与公钥一致的个人密钥，符合才复用。新建默认命名为 `id_ed25519_personal` 或 `id_rsa_personal`；已有文件不匹配时追加邮箱摘要及必要序号，绝不覆盖。新私钥使用空口令，并限制为当前 Windows 用户访问。
- 生成或复用后、配置 SSH 前，在密钥目录仅首次创建 `README.md`，说明 `config`、个人私钥、`.pub` 公钥、`known_hosts`、公私钥区别、安全保管和登记后的测试步骤；写明实际私钥 / 公钥文件名，涵盖 RSA 4096 及冲突后缀。正文直接内嵌，不依赖工程中的 README，不包含私钥正文、Token 或密码。已有任何同名文件、有效 / 悬空链接或目录都视作占用，保留原内容，不覆盖、不追加、不更新；`FileMode.CreateNew` 独占创建保护并发，写失败只警告并继续，单独连接测试不创建说明。
- 将实际 `IdentityFile` 写到 `config` 开头的 Jobs 托管块，同时配置 `github.com` 与 `github-personal`；原正文保留，发生变更前完整备份原配置。重复执行同一配置不重复备份；异常托管标记停止写入。
- 尝试将私钥加入已运行的 ssh-agent；服务不可用时明确显示未加载，仍可用已配置的空口令 `IdentityFile`。不提权、不改变服务启动类型、不写 MacOS Keychain 配置。
- 公钥复制到剪贴板。GitHub CLI 的已登录账号具有公钥管理权限，且输入邮箱属于该账号的已验证邮箱时，自动登记或识别已登记公钥；认证、邮箱或权限无法验证时明确显示“公钥未自动登记”，打开官方密钥网页供处理，不自动登录或扩大 Token 权限。
- `gh` 的未检测到、尚未登录、当前凭据被拒绝（HTTP 401）、请求被拒绝（HTTP 403）、网络 / 证书失败、检测超时及未知检测失败分别显示。仅解析 `github.com` 活跃账号的结构化状态，不以命令退出 0 代替授权有效，也不因非活跃账号错误而阻断当前有效账号。旧版本或无法解析的响应只提示“无法确认登录状态”，不误报未安装或授权失效；原始授权响应与令牌不进入日志。状态检测子进程移除 `GH_HOST` 并显式指定 `--hostname github.com`，避免未登录被合成为空账号 401；父进程环境保持原样。
- 首次连接没有 GitHub `known_hosts` 条目时，从 [**GitHub 官方 HTTPS 元数据**](https://api.github.com/meta) 取得并校验主机公钥后追加；已有条目保留并严格校验，不使用盲目信任的扫描结果。网络、元数据或旧主机指纹异常会明确显示待完成。
- 连接测试强制使用本次私钥并禁用其它 agent 身份、密码提示与未知主机自动信任；同时检查退出码和认证成功文字，避免旧密钥造成成功误报。
- 仅退出码 1 且完整 GitHub 成功行包含合法实际用户名时，才在同目录建立 `<实际用户名>-GitHub` 与 `<实际用户名>-GitHub.pub` 普通硬链接，供 Sourcetree 识别；不从邮箱或缓存 gh 账号猜测。原 `id_..._personal` 文件名保持，硬链接不复制私钥正文、无需符号链接权限或管理员权限。先核对两源文件及两个目标，任何冲突、目录或重解析点都保留，正确硬链接按文件身份幂等；不提权、不覆盖默认 `id_rsa`，创建失败只提示而不改变 SSH 认证成功结论。
- 网页手动登记公钥后，使用原邮箱与原算法重新运行终端入口，会优先复用原密钥、再认证并补齐别名，无须删除重来。Sourcetree 账户用户名应与认证返回的 GitHub 用户名一致；脚本不自动修改账户或 Token。
- [**SourceTree**](https://www.sourcetreeapp.com/) 的 OpenSSH 配置已准备；Windows 中仍需在“工具 → 选项 → 一般”选择 OpenSSH。脚本不自动修改未公开稳定的 GUI 设置，也不把 PuTTY/Pageant 或界面图标当成已经配置成功。
- 终端打印本次私钥、公钥与日志位置；未自动登记时打开官方 GitHub 密钥网页，公钥已复制到剪贴板。完成后可在资源管理器打开当前用户 `.ssh` 查看文件。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、日志与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

内置自述说明用途和影响，只确认一次；算法用 fzf 选择，邮箱只输入一次，生成步骤不再重复文字确认。新密钥为空口令，应妥善保护本机账户与私钥文件。选择和邮箱校验通过后，日志位于系统临时目录 `JobsGit-ssh-时间-进程号.log`，终端显示实际位置；不记录私钥、Token 或密码。关键本地步骤失败停止后续业务，目录 README 生成失败仅警告继续；远端登记、agent 和连接验证分别显示实际结果，不把部分完成写成全部成功。

只调用系统已安装工具，不自动安装、升级或改全局 Git 设置。私钥、SSH 配置、known_hosts 与硬链接源文件不跟随重解析点；本入口不提交或推送仓库、不修改远端 URL、不覆盖已有密钥。原生进程参数按 Win32 规则逐项引用，空口令、中文、空格、括号和尾部反斜杠均按独立参数传递，不通过字符串代码执行。硬链接通过 Windows 原生文件身份与 CreateHardLink API 完成，权限或文件系统不支持时只提示，不回退为复制私钥或请求管理员权限。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

已通过本机 PowerShell 7 Parser 静态检查、UTF-8 BOM/CRLF 检查及 SSH 专用隔离模拟验证，覆盖密钥复用/冲突避让、配置保留和幂等、账号邮箱校验、登记失败兜底、官方主机元数据和强制本次身份认证；gh 分类另覆盖缺工具、未登录、401 / 403、网络、两类超时、无效响应、活跃账号选择与不误上传。没有运行真实用户的密钥生成、认证配置、远端登记、安装、提交或推送。Windows PowerShell 5.1、fzf 原生终端、资源管理器双击、OpenSSH 服务与 SourceTree 的实际行为仍需 Windows 实机验收；本机 PowerShell Parser 不替代这些验收。

目录 README 在本机 PowerShell 7 的隔离夹具中另验首次生成、RSA 后缀文件名、已有文件字节与修改时间不变、有效 / 悬空 / 目录链接及同名目录保留、创建失败继续，以及 12 个并发创建者通过共同检查后仅一个成功写入完整说明。没有修改真实用户的 `.ssh/README.md`；这些夹具仍不替代 Windows 原生文件系统验收。

Sourcetree 补齐另验临时空主目录从未登记失败到登记后复用、按实际账号建立硬链接、重复幂等、原密钥 / 公钥 / config / known_hosts / README 字节和修改时间不变，以及错误退出码、非法用户名、冲突、重解析点和硬链接不可用时无提权 / 复制降级。Win32 API 声明已实际编译；本机 PowerShell 7 夹具用 POSIX 文件身份和硬链接替代 Windows 原语验证其余真实源码，未声称 Windows 原生文件系统或 Sourcetree UI 已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
