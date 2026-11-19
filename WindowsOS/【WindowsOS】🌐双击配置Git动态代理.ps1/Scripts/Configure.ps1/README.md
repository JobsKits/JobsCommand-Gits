# `Configure.ps1`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、源码与运行态](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

管理用户显式选择的代理配置流程，复用平台根的安装与恢复实现。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、源码与运行态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 源码通过[本包脚本](<./Configure.ps1>)加载；用户应从[代理配置入口](<../../【WindowsOS】🌐双击配置Git动态代理.ps1>)操作，不直接调用私有回调。
- `Configure.ps1` 按源码父层寻找配套模块；`Policy.ps1` 是安装器输入，发布时仍以原文件名放在 `git.exe`、`NetworkPolicy.psm1`、`real-git.path` 旁，满足原生 Shim 的固定调用契约。源码包装不改变产物 ABI。
- 来源摘要与复制使用同一资源定位函数，保留已有备份、归属与精确恢复边界；本次未执行真实安装或修改用户 PATH。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

PowerShell AST 与隔离配置回归分别验收；MacOS 的 pwsh 不替代 Windows 5.1 或 Sourcetree 原生连接验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
