# 【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 生成个人 ED25519/RSA4096 密钥、增补 github-personal Host，复制公钥并打开设置页。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'ssh' -Title '【WindowsOS】⚙️双击为私人账户生成 SSH 密钥（加密手段_RSA 4096 + ED25519 二选一）' -Description '生成个人 ED25519/RSA4096 密钥、增补 github-personal Host，复制公钥并打开设置页。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
