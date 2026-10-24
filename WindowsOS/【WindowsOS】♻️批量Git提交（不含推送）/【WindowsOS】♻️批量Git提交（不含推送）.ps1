# 【WindowsOS】♻️批量Git提交（不含推送）.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 扫描指定目录内 Git 工作树，后代先于父仓逐仓提交；不推送。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'batch' -Title '【WindowsOS】♻️批量Git提交（不含推送）' -Description '扫描指定目录内 Git 工作树，后代先于父仓逐仓提交；不推送。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
