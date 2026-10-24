# `WindowsOS Tests`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、回归入口](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

这里验证 Windows 原生实现的路径、Git 安全边界与动态代理策略。使用系统临时目录、隔离 Git 配置、测试身份和 file 传输；不访问业务远端，不修改真实项目索引、用户 PATH 或真实代理配置。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、回归入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录执行：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File '.\Regression.ps1'
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File '.\GitProxyConfigurator.Tests.ps1'
```

- `Regression.ps1`：38 项断言，覆盖 HTTPS/SCP/带端口 SSH 相对 URL、Windows 非法路径、缺命令停止、预览无写入、增量关联与现有字段/gitlink保留、官方元数据归集、分支最新与游离恢复、首次下载、普通文件跟踪冲突、独有提交及缺分支保护，以及五仓重建与原始工作树/元数据备份，以及游离入口尊重父仓显式分支。测试临时目录保留并在末尾打印，便于排查。
- `GitProxyConfigurator.Tests.ps1`：76 项断言，覆盖 argv 编解码、系统代理优先与直连回退、原始业务最多一次、私有运行态安装幂等、精确恢复、并发 PATH/文件冲突和失败回滚。HKCU PATH 读写、shim 编译等均由夹具替代；运行态只落临时目录，测试结束清理本夹具。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

2026-10-23 已在 macOS 的 PowerShell 7.6.8 运行通过；源码采用 PowerShell 5.1 语法，并执行全量 Parser/BOM 静态检查。这里不代表 Windows 桌面、CMD 双击、真实 GitHub 上传与认证、OpenSSH 服务或真实用户代理安装已经实机验收。测试不执行真实安装、业务提交或推送；夹具提交只属于临时仓库。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
