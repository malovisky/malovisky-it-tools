#requires -Version 5.1
# MALOVISKY IT TOOLS - Powered by Thomaz J
# Codigo publico. Inspecione o codigo antes de executar.
$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://scripts.malovisky.com.br'
$ScriptHashes = @{
    'Malovisky-IT-Tools.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'
    'Bloquear_Fabricantes_Firewall_Menu.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'
    'Otimizacao_windows.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'
    'Malovisky_Autodesk_DeepClean.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'
}
$Tools = @{
    '1' = @{ Label = 'AnyDesk - instalacao, limpeza e diagnostico'; File = 'Malovisky-IT-Tools.ps1' }
    '2' = @{ Label = 'Bloqueio de fabricantes no Firewall'; File = 'Bloquear_Fabricantes_Firewall_Menu.ps1' }
    '3' = @{ Label = 'Otimizacao e reparacao do Windows'; File = 'Otimizacao_windows.ps1' }
    '4' = @{ Label = 'Autodesk Deep Clean - limpeza profunda de residuos'; File = 'Malovisky_Autodesk_DeepClean.ps1' }
}
function Set-MatrixConsole {
    try {
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Green'
        $Host.UI.RawUI.WindowTitle = 'MALOVISKY IT TOOLS - Powered by Thomaz J'
    } catch { }
}
function Show-Header([string]$Title) {
    Set-MatrixConsole
    Clear-Host
    Write-Host '=================================================================' -ForegroundColor DarkGreen
    Write-Host '   MALOVISKY IT TOOLS - Powered by Thomaz J' -ForegroundColor Green
    Write-Host '=================================================================' -ForegroundColor DarkGreen
    Write-Host (' ' + $Title) -ForegroundColor Green
    Write-Host ' USE POR SUA CONTA E RISCO.' -ForegroundColor Green
    Write-Host ' Faca backup e confirme que possui autorizacao para alterar este PC.' -ForegroundColor Green
    Write-Host '=================================================================' -ForegroundColor DarkGreen
    Write-Host ''
}
function Invoke-Tool {
    param([string]$FileName, [string[]]$ScriptArguments = @())
    if (-not $ScriptHashes.ContainsKey($FileName)) { throw 'Ferramenta nao registrada.' }
    $working = Join-Path $env:TEMP 'MaloviskyITTools\Modulos'
    if (-not (Test-Path -LiteralPath $working)) {
        New-Item -ItemType Directory -Path $working -Force | Out-Null
    }
    $target = Join-Path $working $FileName
    $uri = $BaseUrl + '/scripts/' + $FileName
    Write-Host ('Baixando modulo: ' + $FileName) -ForegroundColor Green
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $uri -OutFile $target -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($actual -ne $ScriptHashes[$FileName]) {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            throw ('Integridade SHA256 invalida em: ' + $FileName + '. Nenhum codigo foi executado.')
        }
        Write-Host 'Verificacao SHA256 OK.' -ForegroundColor Green
        Write-Host ''
        $psExe = Join-Path $PSHOME 'powershell.exe'
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
        & $psExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $target @ScriptArguments
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { Write-Host ('Modulo retornou codigo: ' + $rc) -ForegroundColor Green }
    } finally {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        }
    }
}
Set-MatrixConsole
do {
    Show-Header 'MENU PRINCIPAL - V1.3.0'
    foreach ($n in @('1','2','3','4')) {
        Write-Host (' [' + $n + '] ' + $Tools[$n].Label) -ForegroundColor Green
    }
    Write-Host ''
    Write-Host ' [0] Sair' -ForegroundColor Green
    Write-Host ''
    $choice = (Read-Host 'Escolha uma opcao').Trim()
    if ($choice -eq '0') { break }
    if (-not $Tools.ContainsKey($choice)) {
        Write-Host 'Opcao invalida.' -ForegroundColor Green
        [void](Read-Host 'Pressione ENTER')
        continue
    }
    $extraArgs = @()
    if ($choice -eq '4') {
        Show-Header 'AUTODESK DEEP CLEAN - V1.3.0'
        Write-Host ' [1] SIMULAR limpeza (padrao, sem alterar o Windows)' -ForegroundColor Green
        Write-Host ' [2] EXECUTAR limpeza de residuos Autodesk' -ForegroundColor Green
        Write-Host ' [3] EXECUTAR incluindo FlexNet compartilhado (ALTO RISCO)' -ForegroundColor Green
        Write-Host ' [0] Voltar ao menu' -ForegroundColor Green
        Write-Host ''
        Write-Host ' IMPORTANTE: desinstale primeiro os produtos Autodesk oficialmente.' -ForegroundColor Green
        Write-Host ' A limpeza executada pode apagar configuracoes e arquivos personalizados.' -ForegroundColor Green
        Write-Host ''
        $deepChoice = (Read-Host 'Escolha [Enter = 1 (SIMULAR)]').Trim()
        if (-not $deepChoice) { $deepChoice = '1' }
        if ($deepChoice -notin @('1','2','3')) {
            if ($deepChoice -ne '0') {
                Write-Host 'Opcao invalida ou cancelada.' -ForegroundColor Green
                [void](Read-Host 'Pressione ENTER')
            }
            continue
        }
        if ($deepChoice -eq '2') {
            $extraArgs = @('-Executar')
        }
        if ($deepChoice -eq '3') {
            Write-Host 'ATENCAO: incluir FlexNet compartilhado pode afetar outros fabricantes.' -ForegroundColor Green
            $confirmacao = Read-Host 'Digite FLEXNET para confirmar esta opcao de alto risco'
            if ($confirmacao -cne 'FLEXNET') {
                Write-Host 'Operacao cancelada.' -ForegroundColor Green
                [void](Read-Host 'Pressione ENTER')
                continue
            }
            $extraArgs = @('-Executar', '-IncluirFlexNetCompartilhado')
        }
    }
    try {
        Show-Header ('EXECUTANDO: ' + $Tools[$choice].Label)
        Invoke-Tool -FileName $Tools[$choice].File -ScriptArguments $extraArgs
    } catch {
        Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Green
    }
    Write-Host ''
    [void](Read-Host 'Pressione ENTER para retornar ao menu')
} while ($true)
Write-Host 'Malovisky IT Tools encerrado.' -ForegroundColor Green
