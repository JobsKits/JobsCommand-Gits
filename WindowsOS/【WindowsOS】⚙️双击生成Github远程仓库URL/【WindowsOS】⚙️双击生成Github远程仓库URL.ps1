# 【WindowsOS】⚙️双击生成Github远程仓库URL.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 通过已登录 GitHub CLI 创建 private/public 远端仓库并打开返回 URL。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'create' -Title '【WindowsOS】⚙️双击生成Github远程仓库URL' -Description '通过已登录 GitHub CLI 创建 private/public 远端仓库并打开返回 URL。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
