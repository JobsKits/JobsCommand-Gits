# 【WindowsOS】⚙️双击为私人账户生成 SSH 密钥.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 黑窗 CLI：fzf 选择算法，一次邮箱输入后生成或复用个人密钥并配置 SSH。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    if ($DryRun) { throw 'SSH 入口不支持 DryRun，未执行。' }
    Invoke-JobsSshKey
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
