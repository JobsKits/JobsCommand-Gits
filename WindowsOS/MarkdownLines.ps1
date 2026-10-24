# MarkdownLines.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# Git pre-commit 工作脚本：只改完整暂存的含统计标记 Markdown。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
try {
    $root=(& git rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0) { throw '无法确定 Git 根目录。' }
    $names=(& git -c core.quotepath=false diff --cached --name-only --diff-filter=ACM -z)
    if ($LASTEXITCODE -ne 0) { throw '无法读取暂存清单。' }
    foreach ($name in (($names -join "`n") -split "`0")) {
        if (-not $name -or [IO.Path]::GetExtension($name) -ne '.md') { continue }
        $file=Join-Path $root $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $item=Get-Item -LiteralPath $file -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "统计目标为链接：$name" }
        $bytes=[IO.File]::ReadAllBytes($file)
        $hasBom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
        $text=[IO.File]::ReadAllText($file,(New-Object Text.UTF8Encoding($false,$true)))
        if ($text -notmatch '(?m)^当前总行数：[0-9]+ 行\r?$') { continue }
        & git diff --quiet -- $name
        if ($LASTEXITCODE -ne 0) { throw "Markdown 为部分暂存或含未暂存修改，保留原状：$name" }
        $count=@($text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*$|^\s*#|^```' }).Count
        $updated=[regex]::Replace($text,'(?m)^当前总行数：[0-9]+ 行(?=\r?$)',('当前总行数：'+$count+' 行'))
        if ($updated -cne $text) {
            [IO.File]::WriteAllText($file,$updated,(New-Object Text.UTF8Encoding($hasBom)))
            & git --literal-pathspecs add -- $name
            if ($LASTEXITCODE -ne 0) { throw "暂存统计文件失败：$name" }
            Write-Host "统计已更新：$name；有效行数 $count"
        }
    }
} catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
