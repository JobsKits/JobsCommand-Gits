# 【WindowsOS】🧹清理Git子仓运行态记录.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 为登记子仓补运行态忽略规则，并移除运行态索引记录，保留真实文件。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'runtime' -Title '【WindowsOS】🧹清理Git子仓运行态记录' -Description '为登记子仓补运行态忽略规则，并移除运行态索引记录，保留真实文件。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
