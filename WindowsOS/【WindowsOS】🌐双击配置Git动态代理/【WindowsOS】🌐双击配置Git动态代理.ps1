# 【WindowsOS】🌐双击配置Git动态代理.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 配置当前用户 Git 动态入口；系统代理可达优先、不可达再直连，支持检查与精确恢复。
[CmdletBinding()]
param([ValidateSet('Menu','Install','Check','Restore')][string]$Mode='Menu')
& (Join-Path $PSScriptRoot 'Scripts/Configure.ps1') -Mode $Mode
exit $LASTEXITCODE
