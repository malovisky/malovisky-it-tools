#requires -Version 5.1
<#
.SYNOPSIS
    MALOVISKY IT TOOLS - DESINSTALACAO PROFUNDA AUTODESK
.DESCRIPTION
    Limpeza de residuos Autodesk, Autodesk Shared e arquivos de licenca Autodesk
    em FLEXnet. Use APOS desinstalar os programas pelo desinstalador oficial.
    Por padrao, apenas simula. NAO remove produtos instalados pelo Windows Installer.
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1 -Executar
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1 -Executar -IncluirFlexNetCompartilhado
.NOTES
    PowerShell 5.1 x64, Windows 10/11, sessao interativa com elevacao.
    O parametro IncluirFlexNetCompartilhado pode afetar outros fabricantes.
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$IncluirFlexNetCompartilhado
)

$ErrorActionPreference = 'Continue'

# ----------------- APARENCIA -----------------
try {
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $Host.UI.RawUI.ForegroundColor = 'Green'
    Clear-Host
} catch { }

Write-Host '================================================================' -ForegroundColor Green
Write-Host '                       MALOVISKY IT TOOLS' -ForegroundColor Green
Write-Host '                      POWERED BY THOMAZ J' -ForegroundColor Green
Write-Host '               DESINSTALACAO PROFUNDA AUTODESK' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
Write-Host ''
Write-Host '   AUTODESK  |  AUTODESK SHARED  |  FLEXNET (ADSK)' -ForegroundColor DarkGreen
Write-Host ''

$Script:Resumo = [ordered]@{
    PastasIdentificadas   = 0
    ArquivosIdentificados = 0
    PastasExcluidas       = 0
    ArquivosExcluidos     = 0
    ChavesIdentificadas   = 0
    ChavesExcluidas       = 0
    ServicosIdentificados = 0
    ServicosParados       = 0
    ProcessosIdentificados= 0
    ProcessosEncerrados   = 0
    Erros                 = 0
}
$Script:DetalhesErros = New-Object 'System.Collections.Generic.List[string]'
$Script:ExplorerParado = $false
$Script:Modalidade = if ($Executar) { 'EXECUCAO' } else { 'SIMULACAO' }
$Script:IniciadoEm = Get-Date

# Log fora dos caminhos de limpeza.
$PastaLog = Join-Path $env:ProgramData 'Malovisky-IT-Tools\Logs'
try {
    New-Item -ItemType Directory -Path $PastaLog -Force -ErrorAction Stop | Out-Null
} catch {
    $PastaLog = Join-Path $env:TEMP 'Malovisky-IT-Tools-Logs'
    try { New-Item -ItemType Directory -Path $PastaLog -Force -ErrorAction Stop | Out-Null }
    catch {
        Write-Host "FALHA: nao foi possivel criar a pasta de logs: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
}
$Script:ExecId = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
$Script:LogArquivo = Join-Path $PastaLog ("AutodeskDeepClean_{0}_{1}.log" -f $Script:ExecId, $PID)

function Write-Log {
    param([string]$Mensagem, [string]$Cor = 'Green')
    Write-Host $Mensagem -ForegroundColor $Cor
    try {
        $Linha = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Script:Modalidade, $Mensagem
        Add-Content -LiteralPath $Script:LogArquivo -Value $Linha -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host '[AVISO] Nao foi possivel escrever no log.' -ForegroundColor Yellow
    }
}

function Add-Falha {
    param([string]$Operacao, [string]$Mensagem)
    $Script:Resumo.Erros++
    $Texto = "$Operacao :: $Mensagem"
    $Script:DetalhesErros.Add($Texto)
    Write-Log "[ERRO] $Texto" 'Red'
}

function Test-Elevado {
    $Id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Id)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProdutosInstalados {
    $Raizes = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($Raiz in $Raizes) {
        if (-not (Test-Path -LiteralPath $Raiz)) { continue }
        Get-ChildItem -LiteralPath $Raiz -ErrorAction SilentlyContinue | ForEach-Object {
            $P = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ($P -and $P.DisplayName -and
                $P.DisplayName -match '(?i)(Autodesk|AutoCAD|Revit|Civil 3D|3ds Max|Navisworks|Inventor|AutoCAD LT)' -and
                $P.DisplayName -notmatch '(?i)^Autodesk Genuine Service$') {
                [pscustomobject]@{ Nome = [string]$P.DisplayName; Chave = $_.PSPath }
            }
        }
    }
}

function Get-PerfisLocais {
    try {
        @(Get-CimInstance Win32_UserProfile -ErrorAction Stop |
            Where-Object { $_.LocalPath -and -not $_.Special -and (Test-Path -LiteralPath $_.LocalPath) })
    } catch {
        Add-Falha 'ENUMERAR PERFIS' $_.Exception.Message
        @()
    }
}

function Get-PastasAlvo {
    $Bases = New-Object 'System.Collections.Generic.List[string]'
    $PF = [Environment]::GetEnvironmentVariable('ProgramFiles')
    $PF86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    foreach ($Base in @($env:ProgramData, $PF, $PF86)) {
        if (-not [string]::IsNullOrWhiteSpace($Base)) { $Bases.Add($Base) }
    }
    foreach ($Base in @($PF, $PF86)) {
        if (-not [string]::IsNullOrWhiteSpace($Base)) {
            $Bases.Add((Join-Path $Base 'Common Files'))
        }
    }
    foreach ($Perfil in @(Get-PerfisLocais)) {
        foreach ($Sub in @('AppData','AppData\Local','AppData\Roaming','AppData\LocalLow')) {
            $Bases.Add((Join-Path $Perfil.LocalPath $Sub))
        }
    }
    # Pasta publica de conteudo Autodesk.
    if (-not [string]::IsNullOrWhiteSpace($env:PUBLIC)) {
        $Bases.Add((Join-Path $env:PUBLIC 'Documents'))
    }

    $Vistos = @{}
    foreach ($Base in @($Bases | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $Base -PathType Container)) { continue }
        # Apenas pastas IMEDIATAMENTE dentro das raizes explicitamente permitidas.
        $SubPastas = @(Get-ChildItem -LiteralPath $Base -Directory -Force -ErrorAction SilentlyContinue)
        foreach ($Pasta in $SubPastas) {
            $Nome = $Pasta.Name
            $Autodesk = $Nome -match '^(?i:Autodesk(?:[ _.-].*)?|AutoCAD(?:[ _.-].*)?)$'
            $FlexNet = $Nome -match '^(?i:FlexNet(?:[ _.-].*)?|FLEXnet)$'
            if ($Autodesk -or ($FlexNet -and $IncluirFlexNetCompartilhado)) {
                $Caminho = $Pasta.FullName
                if (-not $Vistos.ContainsKey($Caminho.ToLowerInvariant())) {
                    $Vistos[$Caminho.ToLowerInvariant()] = $true
                    [pscustomobject]@{ Caminho = $Caminho; Compartilhada = [bool]$FlexNet }
                }
            }
        }
    }
}

function Get-ArquivosFlexnetAutodesk {
    $FlexNet = Join-Path $env:ProgramData 'FLEXnet'
    if (-not (Test-Path -LiteralPath $FlexNet -PathType Container)) { return }
    # Conforme procedimento oficial Autodesk: somente arquivos de licenca Autodesk.
    Get-ChildItem -LiteralPath $FlexNet -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(?i:adsk|autodesk)' }
}

function Get-ChavesAlvo {
    $Candidatas = @(
        [pscustomobject]@{ Ps='Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk'; Native='HKLM\SOFTWARE\Autodesk' },
        [pscustomobject]@{ Ps='Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Autodesk'; Native='HKLM\SOFTWARE\WOW6432Node\Autodesk' },
        [pscustomobject]@{ Ps='Registry::HKEY_CURRENT_USER\SOFTWARE\Autodesk'; Native='HKCU\SOFTWARE\Autodesk' }
    )
    $SidAtual = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $Usuarios = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-(\d+-){3}\d+$' -and $_.PSChildName -ne $SidAtual })
    foreach ($Usuario in $Usuarios) {
        $SID = $Usuario.PSChildName
        $Candidatas += [pscustomobject]@{
            Ps = "Registry::HKEY_USERS\$SID\Software\Autodesk"
            Native = "HKU\$SID\Software\Autodesk"
        }
    }
    foreach ($Chave in $Candidatas) {
        if (Test-Path -LiteralPath $Chave.Ps) { $Chave }
    }
}

function Get-ContagemPasta {
    param([string]$Caminho)
    # Contagem em streaming, sem carregar milhares de objetos na memoria.
    $Arquivos = 0
    $Pastas = 1
    $Links = 0
    Get-ChildItem -LiteralPath $Caminho -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.PSIsContainer) { $Pastas++ } else { $Arquivos++ }
            if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $Links++ }
        }
    [pscustomobject]@{ Arquivos = $Arquivos; Pastas = $Pastas; Links = $Links }
}

function Stop-ProcessosAutodesk {
    $Candidatos = @()
    try {
        $Candidatos = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $N = [string]$_.Name
            $C = [string]$_.ExecutablePath
            ($N -match '^(?i:(acad|acadlt|accoreconsole|autocad|autodesk.*|adsk.*|adodis.*|adappmgr.*|revit.*|inventor.*|3dsmax|maya|navisworks.*|adss.*)\.exe)$') -or
            ($C -match '(?i)\\(Autodesk|Autodesk Shared|AdODIS)\\') -or
            ($IncluirFlexNetCompartilhado -and $N -match '^(?i:(fnls.*|flexnet.*|lmgrd)\.exe)$')
        } | Where-Object { $_.ProcessId -ne $PID } | Sort-Object ProcessId -Unique)
    } catch { Add-Falha 'LISTAR PROCESSOS' $_.Exception.Message }
    $Script:Resumo.ProcessosIdentificados = @($Candidatos).Count
    foreach ($P in $Candidatos) {
        Write-Log ("[PROCESSO] {0} (PID {1})" -f $P.Name, $P.ProcessId) 'DarkGreen'
        try {
            Stop-Process -Id $P.ProcessId -Force -ErrorAction Stop
            $Script:Resumo.ProcessosEncerrados++
        } catch {
            # O processo pode ter encerrado naturalmente no intervalo.
            if (-not (Get-Process -Id $P.ProcessId -ErrorAction SilentlyContinue)) {
                $Script:Resumo.ProcessosEncerrados++
            } else {
                Add-Falha 'ENCERRAR PROCESSO' ("{0} ({1}): {2}" -f $P.Name, $P.ProcessId, $_.Exception.Message)
            }
        }
    }
}

function Stop-ServicosAutodesk {
    $Servicos = @()
    try {
        $Servicos = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            $Nome = [string]$_.Name
            $Titulo = [string]$_.DisplayName
            $Binario = [string]$_.PathName
            ($Nome -match '(?i)(autodesk|adsk|autocad)') -or
            ($Titulo -match '(?i)(autodesk|adsk|autocad)') -or
            ($Binario -match '(?i)\\(Autodesk|Autodesk Shared|AdODIS)\\') -or
            ($IncluirFlexNetCompartilhado -and
                (($Nome -match '(?i)(flexnet|fnls|flexlm)') -or
                 ($Titulo -match '(?i)(flexnet|fnls|flexlm)')))
        } | Sort-Object Name -Unique)
    } catch { Add-Falha 'LISTAR SERVICOS' $_.Exception.Message }
    $Script:Resumo.ServicosIdentificados = @($Servicos).Count
    foreach ($S in $Servicos) {
        if ($S.State -ne 'Running') {
            Write-Log ("[SERVICO] Ja parado: {0}" -f $S.Name) 'DarkGreen'
            continue
        }
        Write-Log ("[SERVICO] Parando: {0}" -f $S.Name) 'DarkGreen'
        try {
            Stop-Service -Name $S.Name -ErrorAction Stop
            $Ctrl = Get-Service -Name $S.Name -ErrorAction Stop
            $Ctrl.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(15))
            $Script:Resumo.ServicosParados++
        } catch {
            Add-Falha 'PARAR SERVICO' ("{0}: {1}" -f $S.Name, $_.Exception.Message)
        }
    }
}

function Stop-ExplorerSessaoAtual {
    $Sessao = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $Explorers = @(Get-Process explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $Sessao })
    foreach ($Exp in $Explorers) {
        try {
            Write-Log ("[EXPLORER] Encerrando PID {0}, sessao {1}" -f $Exp.Id, $Sessao) 'DarkGreen'
            Stop-Process -Id $Exp.Id -Force -ErrorAction Stop
            $Script:ExplorerParado = $true
        } catch {
            if (-not (Get-Process -Id $Exp.Id -ErrorAction SilentlyContinue)) {
                $Script:ExplorerParado = $true
            } else {
                Add-Falha 'ENCERRAR EXPLORER' $_.Exception.Message
            }
        }
    }
}

function Start-ExplorerSessaoAtual {
    if (-not $Script:ExplorerParado) { return }
    $Sessao = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $Presente = @(Get-Process explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $Sessao }).Count -gt 0
    if (-not $Presente) {
        try {
            Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ErrorAction Stop
            $Restaurado = $false
            for ($Tentativa = 1; $Tentativa -le 5; $Tentativa++) {
                Start-Sleep -Seconds 1
                if (@(Get-Process explorer -ErrorAction SilentlyContinue |
                    Where-Object { $_.SessionId -eq $Sessao }).Count -gt 0) {
                    $Restaurado = $true
                    break
                }
            }
            if (-not $Restaurado) {
                Add-Falha 'REINICIAR EXPLORER' 'Processo nao foi detectado apos iniciar explorer.exe.'
            } else {
                Write-Log '[EXPLORER] explorer.exe reiniciado e confirmado na sessao.'
            }
        } catch {
            Add-Falha 'REINICIAR EXPLORER' $_.Exception.Message
        }
    } else {
        Write-Log '[EXPLORER] Ja reiniciado automaticamente pelo Windows.'
    }
}

function Remove-PastaAlvo {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho -PathType Container)) { return }
    try {
        $Info = Get-Item -LiteralPath $Caminho -Force -ErrorAction Stop
        if (($Info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Falha 'IGNORAR JUNCTION' "Caminho e link/reparse point: $Caminho"
            return
        }
        $N = Get-ContagemPasta -Caminho $Caminho
        $Script:Resumo.PastasIdentificadas += $N.Pastas
        $Script:Resumo.ArquivosIdentificados += $N.Arquivos
        Write-Log ("[PASTA] {0} | pastas: {1} | arquivos: {2}" -f $Caminho, $N.Pastas, $N.Arquivos) 'DarkGreen'
        if ($N.Links -gt 0) {
            Add-Falha 'IGNORAR PASTA COM LINKS' "Foram detectados $($N.Links) links/reparse points em $Caminho. Revisar manualmente."
            return
        }
        if (-not $Executar) { return }
        Remove-Item -LiteralPath $Caminho -Force -Recurse -ErrorAction Stop
        if (Test-Path -LiteralPath $Caminho) {
            throw 'Diretorio permanece no disco apos a exclusao.'
        }
        $Script:Resumo.PastasExcluidas += $N.Pastas
        $Script:Resumo.ArquivosExcluidos += $N.Arquivos
        Write-Log "[OK] Pasta excluida: $Caminho"
    } catch { Add-Falha 'EXCLUIR PASTA' ("{0}: {1}" -f $Caminho, $_.Exception.Message) }
}

function Remove-ArquivoAlvo {
    param([string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) { return }
    $Script:Resumo.ArquivosIdentificados++
    Write-Log "[ARQUIVO ADSK FLEXNET] $Caminho" 'DarkGreen'
    if (-not $Executar) { return }
    try {
        Remove-Item -LiteralPath $Caminho -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Caminho) { throw 'Arquivo permanece no disco.' }
        $Script:Resumo.ArquivosExcluidos++
        Write-Log "[OK] Arquivo excluido: $Caminho"
    } catch { Add-Falha 'EXCLUIR ARQUIVO' ("{0}: {1}" -f $Caminho, $_.Exception.Message) }
}

function Remove-ChaveAlvo {
    param([psobject]$Chave, [int]$Indice)
    if (-not (Test-Path -LiteralPath $Chave.Ps)) { return }
    $Script:Resumo.ChavesIdentificadas++
    Write-Log "[REGISTRO] $($Chave.Native)" 'DarkGreen'
    if (-not $Executar) { return }

    # Jamais exclui uma arvore de registro sem um backup exportado com sucesso.
    $NomeBkp = 'Autodesk_reg_{0}_{1:D2}.reg' -f $Script:ExecId, $Indice
    $Backup = Join-Path $PastaLog $NomeBkp
    $RegExe = Join-Path $env:WINDIR 'System32\reg.exe'
    try {
        $Saida = & $RegExe export $Chave.Native $Backup /y 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
            throw "Falha no reg export (codigo $LASTEXITCODE): $Saida"
        }
        Write-Log "[BACKUP REG] $Backup"
        Remove-Item -LiteralPath $Chave.Ps -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Chave.Ps) { throw 'Chave permanece no Registro.' }
        $Script:Resumo.ChavesExcluidas++
        Write-Log "[OK] Chave excluida: $($Chave.Native)"
    } catch { Add-Falha 'REGISTRO' ("{0}: {1}" -f $Chave.Native, $_.Exception.Message) }
}

function Show-Resumo {
    $R = $Script:Resumo
    Write-Log ''
    Write-Log '===================== RESUMO ====================='
    Write-Log ("Modo:                  {0}" -f $Script:Modalidade)
    Write-Log ("Pastas identificadas:  {0}" -f $R.PastasIdentificadas)
    Write-Log ("Arquivos identificados:{0}" -f $R.ArquivosIdentificados)
    Write-Log ("Pastas excluidas:      {0}" -f $R.PastasExcluidas)
    Write-Log ("Arquivos excluidos:    {0}" -f $R.ArquivosExcluidos)
    Write-Log ("Chaves identificadas:  {0}" -f $R.ChavesIdentificadas)
    Write-Log ("Chaves excluidas:      {0}" -f $R.ChavesExcluidas)
    Write-Log ("Servicos identificados:{0}" -f $R.ServicosIdentificados)
    Write-Log ("Servicos parados:      {0}" -f $R.ServicosParados)
    Write-Log ("Processos identificados:{0}" -f $R.ProcessosIdentificados)
    Write-Log ("Processos encerrados: {0}" -f $R.ProcessosEncerrados)
    Write-Log ("Erros:                 {0}" -f $R.Erros)
    Write-Log ("Total itens excluidos: {0}" -f ($R.ArquivosExcluidos + $R.PastasExcluidas + $R.ChavesExcluidas))
    Write-Log ("Tempo:                 {0:N1}s" -f ((Get-Date) - $Script:IniciadoEm).TotalSeconds)
    Write-Log "Log: $Script:LogArquivo"
    if ($R.Erros -gt 0) {
        Write-Log '-------------------- FALHAS ----------------------' 'Red'
        foreach ($Falha in $Script:DetalhesErros) { Write-Log $Falha 'Red' }
    }
    Write-Log '=================================================='
}

function Show-PopupFinal {
    if (-not $Executar) { return }
    $R = $Script:Resumo
    $Texto = @"
MALOVISKY IT TOOLS - THOMAZ J

Limpeza Autodesk finalizada.
Pastas excluidas: $($R.PastasExcluidas)
Arquivos excluidos: $($R.ArquivosExcluidos)
Chaves de registro excluidas: $($R.ChavesExcluidas)
Servicos parados: $($R.ServicosParados)
Processos encerrados: $($R.ProcessosEncerrados)
Erros: $($R.Erros)

Relatorio: $Script:LogArquivo
"@
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $Icone = if ($R.Erros -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [System.Windows.Forms.MessageBox]::Show(
            $Texto, 'MALOVISKY IT TOOLS - AUTODESK',
            [System.Windows.Forms.MessageBoxButtons]::OK, $Icone
        ) | Out-Null
    } catch {
        Write-Log '[AVISO] Popup grafico indisponivel nesta sessao.' 'Yellow'
    }
}

# ----------------- FLUXO PRINCIPAL -----------------
Write-Log "Modo selecionado: $Script:Modalidade"
Write-Log "Log de execucao: $Script:LogArquivo"
if ($IncluirFlexNetCompartilhado) {
    Write-Log '[ATENCAO] FlexNet compartilhado incluIdo: softwares de outros fornecedores podem ser afetados.' 'Yellow'
} else {
    Write-Log '[PROTECAO] FlexNet compartilhado preservado; somente arquivos adsk*/autodesk* em ProgramData\FLEXnet.'
}

if ($Executar) {
    if (-not (Test-Elevado)) {
        Write-Log '[BLOQUEIO] Execute PowerShell como Administrador.' 'Red'
        return
    }
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Log '[BLOQUEIO] Execute pelo Windows PowerShell x64 (System32), nao SysWOW64.' 'Red'
        return
    }
    if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
        Write-Log '[BLOQUEIO] A execucao exige sessao grafica interativa (nao Session 0).' 'Red'
        return
    }
}

$Instalados = @(Get-ProdutosInstalados | Sort-Object Nome -Unique)
if (@($Instalados).Count -gt 0) {
    Write-Log '[ATENCAO] Produtos Autodesk registrados como instalados:' 'Yellow'
    foreach ($Programa in $Instalados) { Write-Log ("    - {0}" -f $Programa.Nome) 'Yellow' }
    if ($Executar) {
        Write-Log '[BLOQUEIO] Desinstale os produtos oficialmente antes de remover seus residuos.' 'Red'
        Write-Log 'Consulte: https://www.autodesk.com/br/support/technical/article/caas/sfdcarticles/sfdcarticles/PTB/Clean-uninstall.html'
        return
    }
}

$Pastas = @(Get-PastasAlvo | Sort-Object Caminho -Unique)
$ArquivosAdsk = @()
if (-not $IncluirFlexNetCompartilhado) {
    $ArquivosAdsk = @(Get-ArquivosFlexnetAutodesk | Sort-Object FullName -Unique)
}
$Chaves = @(Get-ChavesAlvo)

Write-Log ("Alvos: {0} pastas raiz, {1} arquivos ADSK/FLEXnet, {2} chaves Autodesk." -f $Pastas.Count, $ArquivosAdsk.Count, $Chaves.Count)

if ($Executar) {
    Write-Log ''
    Write-Log '[CONFIRMACAO] A limpeza e IRREVERSIVEL para pastas e arquivos.' 'Yellow'
    Write-Log '[CONFIRMACAO] Faca backup de projetos, familias e modelos personalizados.' 'Yellow'
    $Resposta = Read-Host 'Digite REMOVER para iniciar, ou outra coisa para cancelar'
    if ($Resposta -cne 'REMOVER') {
        Write-Log 'Operacao cancelada. Nada foi excluido.' 'Yellow'
        return
    }
}

try {
    if ($Executar) {
        Write-Log '--- Etapa 1: parar servicos ---'
        Stop-ServicosAutodesk
        Write-Log '--- Etapa 2: encerrar processos ---'
        Stop-ProcessosAutodesk
        Write-Log '--- Etapa 3: encerrar Explorer da sessao atual ---'
        Stop-ExplorerSessaoAtual
    } else {
        Write-Log '[SIMULACAO] Nao serao parados servicos, processos ou Explorer.'
    }

    Write-Log '--- Etapa 4: processar pastas e arquivos ---'
    foreach ($Pasta in $Pastas) { Remove-PastaAlvo -Caminho $Pasta.Caminho }
    foreach ($Arquivo in $ArquivosAdsk) { Remove-ArquivoAlvo -Caminho $Arquivo.FullName }

    Write-Log '--- Etapa 5: backup e limpeza do Registro ---'
    $Indice = 0
    foreach ($Chave in $Chaves) {
        $Indice++
        Remove-ChaveAlvo -Chave $Chave -Indice $Indice
    }
} catch {
    Add-Falha 'FALHA GERAL' $_.Exception.Message
} finally {
    # Mesmo em caso de erro durante a remocao, restaurar o desktop.
    if ($Executar) {
        Write-Log '--- Etapa final: restaurar Explorer ---'
        Start-ExplorerSessaoAtual
    }
    Show-Resumo
    Show-PopupFinal
}