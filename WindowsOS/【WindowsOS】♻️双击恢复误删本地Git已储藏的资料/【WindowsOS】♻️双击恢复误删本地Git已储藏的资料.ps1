# 【WindowsOS】♻️双击恢复误删本地Git已储藏的资料.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 检查悬空 commit/tree/blob，按选择恢复为独立分支或二进制文件。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'recover' -Title '【WindowsOS】♻️双击恢复误删本地Git已储藏的资料' -Description '检查悬空 commit/tree/blob，按选择恢复为独立分支或二进制文件。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
