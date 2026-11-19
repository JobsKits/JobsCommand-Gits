# `Regression.ps1`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、用途与调用](#jobs-toc-heading-2)
- [二、验证与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

Regression.ps1 | JobsCommand@Gits；仅使用临时仓库、file 传输及隔离 Git 配置，不访问真实项目索引。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、用途与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 实施文件：[同名脚本](<./Regression.ps1>)。保留现有参数、调用协议与失败退出码；由原业务入口或测试协调器通过包内完整路径调用，不因包装新增业务或改变授权。
- Windows 原生实现最低版本以源码 `#requires` 和对应平台说明为准；中文源码保留 UTF-8 BOM，暂未把 MacOS 上的 AST 解析等同于 Windows 5.1 原生执行。
- 资源仍从文件实际位置解析原平台／功能根；整包移动时保留上级业务、依赖与夹具布局，不依赖调用工作目录。
- 运行时自述、交互和日志仍由当前实施层负责；纯载入的函数库不增加阻塞确认，不独立接管终端。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

语法、相对寻址及隔离行为验证结果见[脚本统一审查](<../../../项目相关报告/脚本统一审查.md>)。本包不宣称真实安装、网络下载、服务或系统菜单已验收；失败与取消不得继续下游业务。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
