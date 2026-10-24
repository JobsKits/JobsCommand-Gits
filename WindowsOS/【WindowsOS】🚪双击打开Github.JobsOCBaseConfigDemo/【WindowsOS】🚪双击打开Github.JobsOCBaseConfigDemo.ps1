# 【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 使用 Windows 默认浏览器打开 JobsOCBaseConfigDemo 仓库。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'open-oc' -Title '【WindowsOS】🚪双击打开Github.JobsOCBaseConfigDemo' -Description '使用 Windows 默认浏览器打开 JobsOCBaseConfigDemo 仓库。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
