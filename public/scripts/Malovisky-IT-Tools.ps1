#Requires -Version 5.1
# MALOVISKY IT TOOLS - Powered by Thomaz J
$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Green' } catch { }
$Base = Join-Path $env:ProgramData 'MaloviskyITTools'
try { New-Item -ItemType Directory -Path $Base -Force -ErrorAction Stop | Out-Null } catch { $Base = Join-Path $env:TEMP 'MaloviskyITTools'; New-Item -ItemType Directory -Path $Base -Force | Out-Null }
$Log = Join-Path $Base ('AnyDesk_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
function Msg([string]$Text,[string]$Color='Gray') { Write-Host $Text -ForegroundColor $Color; Add-Content -LiteralPath $Log -Value ('[{0}] {1}' -f (Get-Date -Format s),$Text) }
function Admin { $p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent(); if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){ throw 'Abra o PowerShell como Administrador.' } }
function Pause-Menu { [void](Read-Host 'Pressione ENTER para continuar') }
function Download-AnyDesk {
    $out=Join-Path $Base 'AnyDesk-Official.exe'
    Msg 'Baixando do site oficial...' Cyan
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://download.anydesk.com/AnyDesk.exe' -OutFile $out -UseBasicParsing
    $sig=Get-AuthenticodeSignature -FilePath $out
    if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'AnyDesk'){ throw 'Assinatura digital nao validada como AnyDesk. Instalacao cancelada.' }
    Msg 'Assinatura digital validada.' Green
    return $out
}
function Stop-AnyDesk {
    Msg 'Encerrando processos e servicos AnyDesk...' Cyan
    Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'AnyDesk' -or $_.DisplayName -match 'AnyDesk' } | ForEach-Object {
        try { if($_.State -eq 'Running'){ Stop-Service -Name $_.Name -Force -ErrorAction Stop }; Msg ('Servico parado: '+$_.Name) } catch { Msg ('Falha ao parar servico: '+$_.Name+' - '+$_) Yellow }
    }
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^AnyDesk' } | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { Msg ('Falha ao encerrar processo '+$_.Id+': '+$_) Yellow }
    }
    Start-Sleep -Seconds 2
}
function Backup-AnyDesk {
    Admin
    Stop-AnyDesk
    $stamp=Get-Date -Format 'ddMMyy'
    $roots=@($env:ProgramData,$env:ProgramFiles,${env:ProgramFiles(x86)},(Join-Path $env:ProgramFiles 'Common Files'))
    if(${env:ProgramFiles(x86)}){ $roots+=Join-Path ${env:ProgramFiles(x86)} 'Common Files' }
    Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) } | ForEach-Object {
        $roots+=Join-Path $_.LocalPath 'AppData'
        $roots+=Join-Path $_.LocalPath 'AppData\Local'
        $roots+=Join-Path $_.LocalPath 'AppData\Roaming'
    }
    $fail=0; $count=0
    foreach($root in ($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)){
        foreach($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^AnyDesk($|[._-])' -and $_.Name -notmatch '_old_\d{6}' })){
            $new=$item.Name+'_old_'+$stamp
            if(Test-Path -LiteralPath (Join-Path $root $new)){ $new+='_'+(Get-Date -Format 'HHmmssfff') }
            try { Rename-Item -LiteralPath $item.FullName -NewName $new -ErrorAction Stop; $count++; Msg ($item.FullName+' -> '+$new) Green }
            catch { $fail++; Msg ('Falha em '+$item.FullName+': '+$_) Yellow }
        }
    }
    $regdir=Join-Path $Base ('Registro_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $regdir -Force | Out-Null
    $keys=@('Registry::HKEY_LOCAL_MACHINE\SOFTWARE\AnyDesk','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\AnyDesk','Registry::HKEY_CURRENT_USER\Software\AnyDesk')
    Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-(\d+-){3}\d+$' } | ForEach-Object { $keys+='Registry::HKEY_USERS\'+$_.PSChildName+'\Software\AnyDesk' }
    foreach($key in ($keys | Select-Object -Unique)){
        if(-not (Test-Path -LiteralPath $key)){ continue }
        $regkey=$key -replace '^Registry::',''
        $export=Join-Path $regdir (('key_'+$count+'_'+[guid]::NewGuid().ToString('N'))+'.reg')
        & reg.exe export $regkey $export /y | Out-Null
        if($LASTEXITCODE -ne 0){ $fail++; Msg ('Backup do registro falhou: '+$regkey) Yellow; continue }
        $new='AnyDesk_old_'+$stamp
        $parent=Split-Path $key -Parent
        if(Test-Path -LiteralPath ($parent+'\'+$new)){ $new+='_'+(Get-Date -Format 'HHmmssfff') }
        try { Rename-Item -LiteralPath $key -NewName $new -ErrorAction Stop; $count++; Msg ('Registro: '+$regkey+' -> '+$new) Green }
        catch { $fail++; Msg ('Falha no registro: '+$regkey+' - '+$_) Yellow }
    }
    Msg ('Renomeados: '+$count+' | Falhas: '+$fail) Cyan
    if($fail -gt 0){ throw 'Limpeza parcial. Revise o log antes de instalar.' }
}
function Install-AnyDesk([string]$installer) {
    Admin
    if(-not $installer){ $installer=Download-AnyDesk }
    $target=Join-Path $env:ProgramFiles 'AnyDesk'
    if(Test-Path -LiteralPath $target){
        $existing=Join-Path $target 'AnyDesk.exe'
        if(Test-Path -LiteralPath $existing){ Msg 'AnyDesk ja esta instalado neste caminho. Use a reinstalacao limpa para substituir.' Yellow; return }
        throw 'Pasta de destino ocupada. Verifique antes de instalar.'
    }
    Msg 'Instalando o AnyDesk e registrando o servico...' Cyan
    $args='--install "'+$target+'" --start-with-win --create-shortcuts --create-desktop-icon --silent'
    $proc=Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
    if($proc.ExitCode -ne 0){ throw ('Instalador retornou codigo '+$proc.ExitCode) }
    $exe=Join-Path $target 'AnyDesk.exe'; $svc=$null
    for($i=0;$i -lt 15;$i++){ $svc=Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^AnyDesk' } | Select-Object -First 1; if((Test-Path -LiteralPath $exe) -and $svc){ break }; Start-Sleep -Seconds 2 }
    if(-not (Test-Path -LiteralPath $exe) -or -not $svc){ throw 'Instalacao nao validada: executavel ou servico ausente.' }
    if($svc.Status -ne 'Running'){ Start-Service -Name $svc.Name -ErrorAction Stop }
    Msg ('Instalado com sucesso: '+$exe) Green
}
function Full-Reinstall {
    Admin
    $installer=Download-AnyDesk
    $answer=Read-Host 'ATENCAO: a sessao AnyDesk sera encerrada e o ID/configuracoes podem mudar. Digite SIM para continuar'
    if($answer -cne 'SIM'){ Msg 'Cancelado.' Yellow; return }
    Stop-AnyDesk
    $paths=@((Join-Path $env:ProgramFiles 'AnyDesk\AnyDesk.exe'))
    if(${env:ProgramFiles(x86)}){ $paths+=Join-Path ${env:ProgramFiles(x86)} 'AnyDesk\AnyDesk.exe' }
    foreach($path in $paths){
        if(Test-Path -LiteralPath $path){
            Msg ('Desinstalando via '+$path) Cyan
            $p=Start-Process -FilePath $path -ArgumentList '--remove --silent' -Wait -PassThru
            Msg ('Retorno do desinstalador: '+$p.ExitCode)
            if($p.ExitCode -ne 0){ throw 'Desinstalacao anterior falhou. Interrompido para preservar a instalacao.' }
        }
    }
    Backup-AnyDesk
    Install-AnyDesk $installer
}
function Diagnose-AnyDesk {
    Msg 'Diagnostico AnyDesk' Cyan
    Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'AnyDesk' } | Format-Table Name,State,StartMode -AutoSize
    Get-Process -Name '*AnyDesk*' -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,Path | Format-Table -AutoSize
    foreach($path in @((Join-Path $env:ProgramFiles 'AnyDesk\AnyDesk.exe'),(Join-Path ${env:ProgramFiles(x86)} 'AnyDesk\AnyDesk.exe'))){ if(Test-Path -LiteralPath $path){ Msg ('Executavel: '+$path) Green } }
    Msg ('Log: '+$Log) Cyan
}
function Execute-Task([scriptblock]$task){ try { & $task } catch { Msg ('ERRO: '+$_) Red }; Pause-Menu }
function Show-MaloviskyHeader {
    param([string]$Section = 'MANUTENCAO')
    try { $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Green'; $Host.UI.RawUI.WindowTitle = 'MALOVISKY IT TOOLS - Powered by Thomaz J' } catch { }
    Clear-Host
    Write-Host '================================================================' -ForegroundColor DarkGreen
    Write-Host ' MALOVISKY IT TOOLS - Powered by Thomaz J' -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor DarkGreen
    Write-Host (' ' + $Section) -ForegroundColor Green
    Write-Host ' USE POR SUA CONTA E RISCO. FACA BACKUP ANTES DE ALTERAR O SISTEMA.' -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor DarkGreen
    Write-Host ''
}

function AnyDesk-Menu {
    do {
        Show-MaloviskyHeader -Section 'MENU 1 - ANYDESK'
        Write-Host '[1] Reinstalacao limpa completa'
        Write-Host '[2] Limpeza com backup (sem reinstalar)'
        Write-Host '[3] Instalar AnyDesk'
        Write-Host '[4] Diagnostico'
        Write-Host '[0] Voltar'
        $choice=Read-Host 'Escolha'
        switch($choice){
            '1' { Execute-Task { Full-Reinstall } }
            '2' { Execute-Task { $a=Read-Host 'Vai encerrar o AnyDesk e renomear configuracoes. Digite SIM'; if($a -ceq 'SIM'){ Backup-AnyDesk } } }
            '3' { Execute-Task { Install-AnyDesk } }
            '4' { Execute-Task { Diagnose-AnyDesk } }
        }
    } until($choice -eq '0')
}
AnyDesk-Menu
