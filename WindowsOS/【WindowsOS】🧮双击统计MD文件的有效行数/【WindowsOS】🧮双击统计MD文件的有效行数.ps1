# 【WindowsOS】🧮双击统计MD文件的有效行数.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 安装 pre-commit 有效行数钩子；保留已有钩子，部分暂存文档停止。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'hook' -Title '【WindowsOS】🧮双击统计MD文件的有效行数' -Description '安装 pre-commit 有效行数钩子；保留已有钩子，部分暂存文档停止。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
