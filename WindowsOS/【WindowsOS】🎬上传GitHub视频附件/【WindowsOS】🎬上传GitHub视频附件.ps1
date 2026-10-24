# 【WindowsOS】🎬上传GitHub视频附件.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 上传 MP4/MOV/WEBM 到 GitHub 附件并复制 URL；不修改 README、不提交。
[CmdletBinding()]
param([string]$Repository,[switch]$DryRun,[switch]$DirectOnly)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -DisableNameChecking
    Invoke-JobsGitTool -Action 'video' -Title '【WindowsOS】🎬上传GitHub视频附件' -Description '上传 MP4/MOV/WEBM 到 GitHub 附件并复制 URL；不修改 README、不提交。' -EntryDirectory $PSScriptRoot -Repository $Repository -DryRun:$DryRun -DirectOnly:$DirectOnly
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
