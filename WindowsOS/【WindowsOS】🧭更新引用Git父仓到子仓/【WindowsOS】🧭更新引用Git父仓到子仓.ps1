# 【WindowsOS】🧭更新引用Git父仓到子仓.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 依据磁盘现存子仓对齐登记和 gitlink，备份配置与索引，保留源码与远端。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'align' -Title '【WindowsOS】🧭更新引用Git父仓到子仓' -Description '依据磁盘现存子仓对齐登记和 gitlink，备份配置与索引，保留源码与远端。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
