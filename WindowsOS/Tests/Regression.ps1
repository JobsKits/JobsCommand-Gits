# Regression.ps1 | JobsCommand@Gits
# Created by Jobs on 2026年10月23日，星期五.
# 仅使用临时仓库、file 传输及隔离 Git 配置，不访问真实项目索引。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('Jobs Gits 中文 (fixture) '+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$keys=@('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_ALLOW_PROTOCOL','GIT_TERMINAL_PROMPT','GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')
$saved=@{}
foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=Join-Path $root 'empty-config'
$env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='core.hooksPath';$env:GIT_CONFIG_VALUE_0=Join-Path $root 'no-hooks'
$env:GIT_ALLOW_PROTOCOL='file';$env:GIT_TERMINAL_PROMPT='0'
$env:GIT_AUTHOR_NAME='Isolated Test';$env:GIT_COMMITTER_NAME='Isolated Test';$env:GIT_AUTHOR_EMAIL='test@example.invalid';$env:GIT_COMMITTER_EMAIL='test@example.invalid'
$script:assertions=0
# 比较夹具结果，失败保留临时目录供排查。
function Assert-Equal {
    param($Expected,$Actual,[string]$Message)
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message；期望=$Expected；实际=$Actual" }
}
# 错误分支必须明确抛错，不能静默继续。
function Assert-Throws {
    param([scriptblock]$Body,[string]$Message)
    $script:assertions++
    try { & $Body; throw '未抛出预期错误' } catch { if ($_.Exception.Message -eq '未抛出预期错误') { throw $Message } }
}
# 创建只有测试身份和测试提交的隔离工作树。
function New-FixtureRepository {
    param([string]$Path,[string]$Remote)
    [void][IO.Directory]::CreateDirectory($Path)
    [void](Invoke-JobsGit $Path @('init','-b','main') -Quiet)
    [IO.File]::WriteAllText((Join-Path $Path 'seed.txt'),'seed')
    [void](Invoke-JobsGit $Path @('add','--','seed.txt') -Quiet)
    [void](Invoke-JobsGit $Path @('commit','-m','fixture seed') -Quiet)
    if ($Remote) { [void](Invoke-JobsGit $Path @('remote','add','origin',$Remote) -Quiet) }
    return (Invoke-JobsGit $Path @('rev-parse','--show-toplevel') -Quiet).Text
}
try {
    $module=Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'GitTools.psm1') -Force -PassThru -DisableNameChecking
    & $module {
        function script:Confirm-JobsYes { param([string]$Message) }
        function script:Select-JobsItem { param([string]$Title,[object[]]$Items) return $Items[0] }
    }
    Assert-Equal 'https://code.example/team/Child.git' (Resolve-JobsGitUrl 'https://code.example/team/Parent.git' '../Child.git') 'HTTPS 相对地址'
    Assert-Equal 'ssh://git@code.example:2222/a/b/Child.git' (Resolve-JobsGitUrl 'ssh://git@code.example:2222/a/b/Parent.git' '../Child.git') 'SSH 端口与 namespace'
    Assert-Equal 'git@code.example:team/Child.git' (Resolve-JobsGitUrl 'git@code.example:team/Parent.git' '../Child.git') 'SCP 地址'
    foreach ($path in @('../escape','a/../escape','a//b','/absolute','.git/config','a>z','CON','folder.')) { Assert-Throws { Resolve-JobsChildPath $root $path } ('应拒绝 '+$path) }
    Assert-Throws { Invoke-JobsNative 'jobs-command-that-does-not-exist-fixture' @('--version') -Quiet } '缺少命令不能复用上次成功退出码'
    $parent=New-FixtureRepository (Join-Path $root '父仓 空格') 'https://code.example/team/Parent.git'
    $child=New-FixtureRepository (Join-Path $parent '子仓 (一)') 'https://code.example/team/Child.git'
    $head=(Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text
    $before=Get-JobsAssociationFingerprint $parent
    & $module { $script:DryRun=$true }
    Invoke-JobsAssociate $parent
    Assert-Equal $before (Get-JobsAssociationFingerprint $parent) '只读关联不得改索引/配置'
    & $module { $script:DryRun=$false }
    Invoke-JobsAssociate $parent
    Assert-Equal '../Child.git' (Get-JobsConfig $parent 'submodule.子仓 (一).url' (Join-Path $parent '.gitmodules')) '登记共享相对地址'
    Assert-Equal $head (Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text '归集保留子仓 HEAD'
    Assert-Equal $true (Test-Path -LiteralPath (Join-Path $child '.git') -PathType Leaf) '归集使用 gitdir 指针'
    [void](Invoke-JobsGit $parent @('commit','-m','register fixture child') -Quiet)
    [IO.File]::WriteAllText((Join-Path $child 'later.txt'),'later')
    [void](Invoke-JobsGit $child @('add','--','later.txt') -Quiet);[void](Invoke-JobsGit $child @('commit','-m','later fixture') -Quiet)
    [void](Invoke-JobsGit $parent @('config','--file',(Join-Path $parent '.gitmodules'),'submodule.子仓 (一).custom','keep-me') -Quiet)
    [void](Invoke-JobsGit $parent @('add','--','.gitmodules') -Quiet)
    Invoke-JobsAssociate $parent
    Assert-Equal $head (((Invoke-JobsGit $parent @('ls-files','--stage','--','子仓 (一)') -Quiet).Text -split ' ')[1]) '增量关联保留已有 gitlink'
    Assert-Equal 'keep-me' (Get-JobsConfig $parent 'submodule.子仓 (一).custom' (Join-Path $parent '.gitmodules')) '保留扩展字段'
    Assert-Equal 'https://code.example/team/Child.git' (Get-JobsConfig $child 'remote.origin.url') '真实 origin 不改为相对地址'
    Invoke-JobsAssociate $parent -Align
    Assert-Equal ((Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text) (((Invoke-JobsGit $parent @('ls-files','--stage','--','子仓 (一)') -Quiet).Text -split ' ')[1]) '对齐采用当前 gitlink'
    $bare=Join-Path $root '远端仓.git'; [void](Invoke-JobsGit '' @('init','--bare','--initial-branch=main',$bare) -Quiet)
    $seed=New-FixtureRepository (Join-Path $root '远端种子') $bare
    [void](Invoke-JobsGit $seed @('push','-u','origin','main') -Quiet)
    $sync=New-FixtureRepository (Join-Path $root '同步父仓') 'https://code.example/team/Sync.git'
    [void](Invoke-JobsGit $sync @('submodule','add','--',$bare,'分类/子仓') -Quiet)
    [void](Invoke-JobsGit $sync @('commit','-m','register local fixture') -Quiet)
    [IO.File]::WriteAllText((Join-Path $seed 'remote-later.txt'),'new')
    [void](Invoke-JobsGit $seed @('add','--','remote-later.txt') -Quiet);[void](Invoke-JobsGit $seed @('commit','-m','remote advance') -Quiet)
    [void](Invoke-JobsGit $seed @('push','origin','main') -Quiet)
    $sub=Join-Path $sync '分类/子仓'
    [void](Invoke-JobsGit $sub @('checkout','--detach') -Quiet)
    Sync-JobsModules $sync 'https://code.example/team/Sync.git' $true
    Assert-Equal 'main' (Invoke-JobsGit $sub @('symbolic-ref','--short','HEAD') -Quiet).Text '同步恢复本地分支'
    Assert-Equal ((Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text) (Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text '同步跟随远端最新'
    [IO.File]::WriteAllText((Join-Path $sub 'local-only.txt'),'local')
    [void](Invoke-JobsGit $sub @('add','--','local-only.txt') -Quiet);[void](Invoke-JobsGit $sub @('commit','-m','local only fixture') -Quiet)
    $localHead=(Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text
    Assert-Throws { Update-JobsBranch $sub $bare 'main' } '独有提交必须阻断'
    Assert-Equal $localHead (Invoke-JobsGit $sub @('rev-parse','HEAD') -Quiet).Text '独有提交保留'
    $moduleText=[IO.File]::ReadAllText((Join-Path $sync '.gitmodules'))
    & $module { $script:DryRun=$true }
    Sync-JobsModules $sync 'https://code.example/team/Sync.git' $true
    Assert-Equal $moduleText ([IO.File]::ReadAllText((Join-Path $sync '.gitmodules'))) '下载预览保留清单'
    & $module { $script:DryRun=$false }
    $fresh=New-FixtureRepository (Join-Path $root '首次下载父仓') 'https://code.example/team/Fresh.git'
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.path','新子仓') -Quiet)
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.url',$bare) -Quiet)
    [void](Invoke-JobsGit $fresh @('update-index','--add','--cacheinfo',('160000,'+(Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text+',新子仓')) -Quiet)
    [void](Invoke-JobsGit $fresh @('add','--','.gitmodules') -Quiet);[void](Invoke-JobsGit $fresh @('commit','-m','fixture manifest') -Quiet)
    Sync-JobsModules $fresh 'https://code.example/team/Fresh.git' $true
    $freshChild=Join-Path $fresh '新子仓'
    Assert-Equal 'main' (Invoke-JobsGit $freshChild @('symbolic-ref','--short','HEAD') -Quiet).Text '首次克隆保持本地分支'
    Assert-Equal ((Invoke-JobsGit $seed @('rev-parse','HEAD') -Quiet).Text) (Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text '首次克隆取得分支最新'
    Assert-Equal $true (Test-Path -LiteralPath (Join-Path $freshChild '.git') -PathType Leaf) '首次克隆归集元数据'
    $badParent=New-FixtureRepository (Join-Path $root '普通文件冲突') 'https://code.example/team/Bad.git'
    $badChild=New-FixtureRepository (Join-Path $badParent 'Child') 'https://code.example/team/Child.git'
    [void](Invoke-JobsGit $badParent @('update-index','--add','--cacheinfo',('100644,'+(Invoke-JobsGit $badParent @('hash-object','seed.txt') -Quiet).Text+',Child/seed.txt')) -Quiet)
    $badBefore=Get-JobsAssociationFingerprint $badParent
    Assert-Throws { Invoke-JobsAssociate $badParent } '普通文件跟踪冲突应停止'
    Assert-Equal $badBefore (Get-JobsAssociationFingerprint $badParent) '关联预检失败不改索引'
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.branch','branch-does-not-exist') -Quiet)
    $freshHead=(Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text
    Assert-Throws { Sync-JobsModules $fresh 'https://code.example/team/Fresh.git' $true } '不存在的显式分支应停止'
    Assert-Equal $freshHead (Invoke-JobsGit $freshChild @('rev-parse','HEAD') -Quiet).Text '分支失败保留已有 HEAD'
    $remoteFolder=Join-Path $root '重建远端';[void][IO.Directory]::CreateDirectory($remoteFolder)
    foreach ($name in @('JobsCommand-Flutter','JobsCommand-iOS','JobsCommand-Gits','JobsCommand-Others','JobsSh')) {
        [void](Invoke-JobsGit '' @('clone','--bare','--',$seed,(Join-Path $remoteFolder ($name+'.git'))) -Quiet)
    }
    $rebuild=New-FixtureRepository (Join-Path $root '重建父仓') (Join-Path $remoteFolder 'Parent.git')
    [void](Invoke-JobsGit $rebuild @('submodule','add','--',(Join-Path $remoteFolder 'JobsCommand-Flutter.git'),'JobsGenesis@JobsCommand.Flutter') -Quiet)
    [void](Invoke-JobsGit $rebuild @('commit','-m','old fixture module') -Quiet)
    Invoke-JobsRebuildModules $rebuild
    Assert-Equal 5 @(Get-JobsModules $rebuild).Count '重建五仓关联完整'
    Assert-Equal 'main' (Invoke-JobsGit (Join-Path $rebuild 'JobsGenesis@JobsCommand.Flutter') @('symbolic-ref','--short','HEAD') -Quiet).Text '重建后保持分支'
    $rebuildGit=(Invoke-JobsGit $rebuild @('rev-parse','--absolute-git-dir') -Quiet).Text
    $maps=@(Get-ChildItem -LiteralPath (Join-Path $rebuildGit 'jobs-submodule-backups') -Recurse -Filter 'worktree-metadata-map.json')
    Assert-Equal 1 $maps.Count '重建保留原路径映射'
    $records=Get-Content -LiteralPath $maps[0].FullName -Raw | ConvertFrom-Json
    Assert-Equal $true (Test-Path -LiteralPath $records.MetadataBackup) '重建保留完整旧元数据'
    [void](Invoke-JobsGit $seed @('branch','feature') -Quiet)
    [void](Invoke-JobsGit $seed @('push','origin','feature') -Quiet)
    [void](Invoke-JobsGit $fresh @('config','--file',(Join-Path $fresh '.gitmodules'),'submodule.新子仓.branch','feature') -Quiet)
    [void](Invoke-JobsGit $freshChild @('checkout','--detach') -Quiet)
    Invoke-JobsDownload $freshChild $true
    Assert-Equal 'feature' (Invoke-JobsGit $freshChild @('symbolic-ref','--short','HEAD') -Quiet).Text '游离入口尊重直接父仓显式分支'
    Assert-Equal 'refs/heads/feature' (Get-JobsConfig $freshChild 'branch.feature.merge') '游离入口恢复对应跟踪分支'
    Write-Host "PASS：$script:assertions 项断言；隔离夹具：$root"
} catch { Write-Host "FAIL：隔离夹具保留在 $root"; throw }
finally { foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
