# 【WindowsOS】♻️检测并转换为子Git.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 扫描独立嵌套 Git，逐仓预检、备份、登记并使用 Git 官方命令归集元数据。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'convert' -Title '【WindowsOS】♻️检测并转换为子Git' -Description '扫描独立嵌套 Git，逐仓预检、备份、登记并使用 Git 官方命令归集元数据。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
