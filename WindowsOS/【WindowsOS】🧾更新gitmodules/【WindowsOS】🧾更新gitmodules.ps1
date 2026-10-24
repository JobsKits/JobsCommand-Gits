# 【WindowsOS】🧾更新gitmodules.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 增量登记现有直属独立子仓，保留已有 URL/branch/扩展字段和 gitlink。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'associate' -Title '【WindowsOS】🧾更新gitmodules' -Description '增量登记现有直属独立子仓，保留已有 URL/branch/扩展字段和 gitlink。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
