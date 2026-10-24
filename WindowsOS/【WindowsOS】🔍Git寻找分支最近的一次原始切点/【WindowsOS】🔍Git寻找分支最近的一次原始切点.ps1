# 【WindowsOS】🔍Git寻找分支最近的一次原始切点.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 选择两个分支，通过 fork-point 或 merge-base 计算最近共同祖先。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'forkpoint' -Title '【WindowsOS】🔍Git寻找分支最近的一次原始切点' -Description '选择两个分支，通过 fork-point 或 merge-base 计算最近共同祖先。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
