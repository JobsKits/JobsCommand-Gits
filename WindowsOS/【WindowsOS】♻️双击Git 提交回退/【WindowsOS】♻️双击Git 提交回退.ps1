# 【WindowsOS】♻️双击Git 提交回退.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 选择上一提交、tag 或 reflog，soft/hard 回退；先创建原 HEAD 恢复分支。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'reset' -Title '【WindowsOS】♻️双击Git 提交回退' -Description '选择上一提交、tag 或 reflog，soft/hard 回退；先创建原 HEAD 恢复分支。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
