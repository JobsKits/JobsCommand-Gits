# 【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 按登记逐层拉取目标分支最新，恢复本地跟踪分支；默认不提交、不推送。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'download' -Title '【WindowsOS】⏬下载配置当前Git子模块（可向下同步递归）' -Description '按登记逐层拉取目标分支最新，恢复本地跟踪分支；默认不提交、不推送。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
