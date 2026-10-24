# 【WindowsOS】⏬双击下载SourceTree效率脚本.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 下载或安全快进 SourceTree 脚本库；保留非空目标与已有修改。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'sourcetree' -Title '【WindowsOS】⏬双击下载SourceTree效率脚本' -Description '下载或安全快进 SourceTree 脚本库；保留非空目标与已有修改。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
