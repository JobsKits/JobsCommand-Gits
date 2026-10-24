# 【WindowsOS】🔍Git依据提交日志关键字查找.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 按字面关键词搜索全部引用的提交说明，选择后展示提交详情。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'search' -Title '【WindowsOS】🔍Git依据提交日志关键字查找' -Description '按字面关键词搜索全部引用的提交说明，选择后展示提交详情。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
