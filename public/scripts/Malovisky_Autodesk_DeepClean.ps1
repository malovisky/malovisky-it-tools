#requires -Version 5.1
<#
.SYNOPSIS
    MALOVISKY IT TOOLS - DESINSTALACAO PROFUNDA AUTODESK
.DESCRIPTION
    Limpeza de residuos Autodesk, Autodesk Shared e arquivos de licenca Autodesk
    em FLEXnet. Por padrao apenas simula. Com -Executar permite remover
    residuos mesmo com produtos Autodesk ainda registrados como instalados,
    exigindo confirmacao reforcada. Nao invoca o Windows Installer para
    desinstalar produtos e nao modifica a base MSI (Installer\Products).
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1 -Executar
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1 -Executar -LimparEntradasDesinstalacao
.EXAMPLE
    .\Malovisky_Autodesk_DeepClean.ps1 -Executar -IncluirFlexNetCompartilhado
.NOTES
    PowerShell 5.1 x64, Windows 10/11, sessao interativa com elevacao.
    O parametro IncluirFlexNetCompartilhado pode afetar outros fabricantes.
    LimparEntradasDesinstalacao apaga apenas as entradas Autodesk no painel
    Programas e Recursos, nao desinstala o software nem corrige o banco MSI.
    Versao: 2.0 (limpeza forcada com confirmacao, servicos e backup).
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$IncluirFlexNetCompartilhado,
    [switch]$LimparEntradasDesinstalacao
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
    ServicosRemovidos     = 0
    ServicosPendentes     = 0
    TarefasIdentificadas = 0
    TarefasRemovidas     = 0
    EntradasUninstallDetectadas = 0
    EntradasUninstallRemovidas  = 0
    EntradasUninstallPreservadas = 0
    ProcessosIdentificados= 0
    ProcessosEncerrados   = 0
    Erros                 = 0
}
$Script:DetalhesErros = New-Object 'System.Collections.Generic.List[string]'
$Script:ExplorerParado = $false
$Script:ReinicioPendente = $false
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

function Convert-RegistryNative {
    param([string]$Caminho)
    # Usado SOMENTE com caminhos de chaves obtidos do Registro local.
    if ($Caminho -like 'HKEY_LOCAL_MACHINE\*') { return ('HKLM\' + $Caminho.Substring('HKEY_LOCAL_MACHINE\'.Length)) }
    if ($Caminho -like 'HKEY_CURRENT_USER\*') { return ('HKCU\' + $Caminho.Substring('HKEY_CURRENT_USER\'.Length)) }
    if ($Caminho -like 'HKEY_USERS\*') { return ('HKU\' + $Caminho.Substring('HKEY_USERS\'.Length)) }
    return $null
}

function Get-ProdutosInstalados {
    $Raizes = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($Raiz in $Raizes) {
        if (-not (Test-Path -LiteralPath $Raiz)) { continue }
        foreach ($Item in @(Get-ChildItem -LiteralPath $Raiz -ErrorAction SilentlyContinue)) {
            $P = Get-ItemProperty -LiteralPath $Item.PSPath -ErrorAction SilentlyContinue
            if (-not $P -or [string]::IsNullOrWhiteSpace([string]$P.DisplayName)) { continue }
            $Nome = [string]$P.DisplayName
            $Fornecedor = [string]$P.Publisher
            $Relacionado = ($Nome -match '(?i)(Autodesk|AutoCAD|Revit|Civil 3D|3ds Max|Navisworks|Inventor|AutoCAD LT)')
            if (-not $Relacionado) { continue }

            # Revit plugins de terceiros (ex.: OpenStudio) devem ser listados,
            # mas NUNCA ter a entrada removida apenas porque contem "Revit".
            $Autodesk = ($Fornecedor -match '(?i)^Autodesk(?:,?\s*(?:Inc\.?|Ltd\.?|GmbH|SA))?\s*$') -or
                ($Nome -match '(?i)^(Autodesk\b|AutoCAD\b|Autodesk\s+Genuine\b|Revit\s+\d{4}\b|3ds\s+Max\s+\d{4}\b|Navisworks\s+\d{4}\b|Inventor\s+\d{4}\b)')
            $Nativa = Convert-RegistryNative -Caminho $Item.Name
            if ([string]::IsNullOrWhiteSpace($Nativa)) { continue }
            [pscustomobject]@{
                Nome = $Nome
                Fornecedor = $Fornecedor
                Chave = $Item.PSPath
                Native = $Nativa
                Autodesk = [bool]$Autodesk
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
            $CommonFiles = Join-Path $Base 'Common Files'
            $Bases.Add($CommonFiles)
            if ($IncluirFlexNetCompartilhado) {
                $Bases.Add((Join-Path $CommonFiles 'Macrovision Shared'))
            }
        }
    }
    foreach ($Perfil in @(Get-PerfisLocais)) {
        foreach ($Sub in @('AppData','AppData\Local','AppData\Local\Programs','AppData\Roaming','AppData\LocalLow')) {
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
            $Autodesk = $Nome -match '^(?i:Autodesk(?:[ _.-].*)?|AutoCAD(?:[ _.-].*)?|AdODIS)$'
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

function Get-ServicosAlvo {
    try {
        @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            $Nome = [string]$_.Name
            $Titulo = [string]$_.DisplayName
            $Binario = [string]$_.PathName
            $Autodesk = ($Nome -match '(?i)(autodesk|adsk|autocad|adodis)') -or
                ($Titulo -match '(?i)(autodesk|adsk|autocad)') -or
                ($Binario -match '(?i)\\(Autodesk|Autodesk Shared|AdODIS)\\')
            $Flexnet = ($Nome -match '(?i)(flexnet|fnls|flexlm)') -or
                ($Titulo -match '(?i)(flexnet|fnls|flexlm)') -or
                ($Binario -match '(?i)\\FLEXnet(?: Publisher)?\\')
            $Autodesk -or ($IncluirFlexNetCompartilhado -and $Flexnet)
        } | Sort-Object Name -Unique)
    } catch {
        Add-Falha 'LISTAR SERVICOS' $_.Exception.Message
        @()
    }
}

function Stop-ServicosAutodesk {
    foreach ($S in @($Script:ServicosEncontrados)) {
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
            # O registro ainda sera considerado para exclusao por sc.exe.
            Add-Falha 'PARAR SERVICO' ("{0}: {1}" -f $S.Name, $_.Exception.Message)
        }
    }
}

function Remove-ServicosAutodesk {
    $RegExe = Join-Path $env:WINDIR 'System32\reg.exe'
    $ScExe = Join-Path $env:WINDIR 'System32\sc.exe'
    $Indice = 0
    foreach ($S in @($Script:ServicosEncontrados)) {
        $Indice++
        $ChaveNativa = "HKLM\SYSTEM\CurrentControlSet\Services\$($S.Name)"
        $Backup = Join-Path $PastaLog ('Autodesk_servico_{0}_{1:D3}.reg' -f $Script:ExecId, $Indice)
        if (-not (Test-Path -LiteralPath ("Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\{0}" -f $S.Name))) {
            Write-Log "[SERVICO] Chave ja ausente: $($S.Name)" 'Yellow'
            continue
        }
        try {
            $Saida = & $RegExe export $ChaveNativa $Backup /y 2>&1
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
                throw "Falha no backup do servico (codigo $LASTEXITCODE): $Saida"
            }
            Write-Log "[BACKUP SERVICO] $Backup"
            $Saida = & $ScExe delete $S.Name 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Falha em sc.exe delete (codigo $LASTEXITCODE): $Saida"
            }
            $Script:Resumo.ServicosRemovidos++
            Write-Log "[OK] Exclusao solicitada ao Windows: $($S.Name)"
            # A API pode marcar o servico para exclusao somente apos reboot.
            if (Get-Service -Name $S.Name -ErrorAction SilentlyContinue) {
                $Script:ReinicioPendente = $true
                $Script:Resumo.ServicosPendentes++
                Write-Log "[PENDENTE] Servico $($S.Name) pode requerer reinicializacao." 'Yellow'
            }
        } catch {
            Add-Falha 'REMOVER SERVICO' ("{0}: {1}" -f $S.Name, $_.Exception.Message)
        }
    }
}

function Get-TarefasAutodesk {
    # Inclui apenas tarefas cujo nome, pasta de tarefa ou executavel pertence
    # explicitamente a Autodesk. Nao depende de prefixos vagos como "Revit".
    try {
        @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $T = $_
            $PastaNome = (([string]$T.TaskPath) + ([string]$T.TaskName))
            $AcaoAutodesk = $false
            foreach ($Acao in @($T.Actions)) {
                if ([string]$Acao.Execute -match '(?i)\\(Autodesk|Autodesk Shared|AdODIS)\\') {
                    $AcaoAutodesk = $true
                    break
                }
            }
            ($PastaNome -match '(?i)(autodesk|autocad|adsk|adodis)') -or $AcaoAutodesk
        } | Sort-Object TaskPath, TaskName -Unique)
    } catch {
        Add-Falha 'LISTAR TAREFAS' $_.Exception.Message
        @()
    }
}

function Remove-TarefasAutodesk {
    $Indice = 0
    foreach ($T in @($Script:TarefasEncontradas)) {
        $Indice++
        try {
            $Backup = Join-Path $PastaLog ('Autodesk_tarefa_{0}_{1:D3}.xml' -f $Script:ExecId, $Indice)
            $Xml = Export-ScheduledTask -TaskName $T.TaskName -TaskPath $T.TaskPath -ErrorAction Stop
            Set-Content -LiteralPath $Backup -Value $Xml -Encoding UTF8 -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
                throw "Nao foi possivel salvar o backup XML: $Backup"
            }
            Unregister-ScheduledTask -TaskName $T.TaskName -TaskPath $T.TaskPath -Confirm:$false -ErrorAction Stop
            $Script:Resumo.TarefasRemovidas++
            Write-Log ("[OK] Tarefa removida: {0}{1} | Backup: {2}" -f $T.TaskPath, $T.TaskName, $Backup)
        } catch {
            Add-Falha 'REMOVER TAREFA' ("{0}{1}: {2}" -f $T.TaskPath, $T.TaskName, $_.Exception.Message)
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
    Write-Log ("Servicos removidos:    {0}" -f $R.ServicosRemovidos)
    Write-Log ("Servicos pendentes:    {0}" -f $R.ServicosPendentes)
    Write-Log ("Tarefas identificadas: {0}" -f $R.TarefasIdentificadas)
    Write-Log ("Tarefas removidas:     {0}" -f $R.TarefasRemovidas)
    Write-Log ("Uninstall detectadas:  {0}" -f $R.EntradasUninstallDetectadas)
    Write-Log ("Uninstall removidas:   {0}" -f $R.EntradasUninstallRemovidas)
    Write-Log ("Uninstall preservadas: {0}" -f $R.EntradasUninstallPreservadas)
    Write-Log ("Processos identificados:{0}" -f $R.ProcessosIdentificados)
    Write-Log ("Processos encerrados: {0}" -f $R.ProcessosEncerrados)
    Write-Log ("Erros:                 {0}" -f $R.Erros)
    Write-Log ("Total itens excluidos: {0}" -f ($R.ArquivosExcluidos + $R.PastasExcluidas + $R.ChavesExcluidas + $R.ServicosRemovidos + $R.TarefasRemovidas + $R.EntradasUninstallRemovidas))
    Write-Log ("Reinicio pendente:     {0}" -f $(if ($Script:ReinicioPendente) { 'SIM' } else { 'Nao identificado' }))
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
Servicos removidos: $($R.ServicosRemovidos)
Tarefas removidas: $($R.TarefasRemovidas)
Entradas Autodesk (Uninstall): $($R.EntradasUninstallRemovidas)
Reinicio pendente: $(if ($Script:ReinicioPendente) { 'SIM' } else { 'Nao identificado' })
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

$Instalados = @(Get-ProdutosInstalados | Sort-Object Native -Unique)
$AutodeskRegistrados = @($Instalados | Where-Object { $_.Autodesk })
$AssociadosTerceiros = @($Instalados | Where-Object { -not $_.Autodesk })
if ($Instalados.Count -gt 0) {
    Write-Log '[ATENCAO] Entradas ainda registradas em Programas e Recursos:' 'Yellow'
    foreach ($Programa in $Instalados) {
        $Tipo = if ($Programa.Autodesk) { 'AUTODESK' } else { 'ASSOCIADO/TERCEIRO' }
        Write-Log ("    - [{0}] {1} | fornecedor: {2}" -f $Tipo, $Programa.Nome, $Programa.Fornecedor) 'Yellow'
    }
    Write-Log '[MODO FORCADO] O cadastro desses produtos NAO impede mais a limpeza.' 'Yellow'
    Write-Log '[RISCO] Se algum produto ainda funcionar, a limpeza podera inutiliza-lo.' 'Yellow'
}

$Pastas = @(Get-PastasAlvo | Sort-Object Caminho -Unique)
$ArquivosAdsk = @()
if (-not $IncluirFlexNetCompartilhado) {
    $ArquivosAdsk = @(Get-ArquivosFlexnetAutodesk | Sort-Object FullName -Unique)
}
$Chaves = @(Get-ChavesAlvo)
$Script:ServicosEncontrados = @(Get-ServicosAlvo)
$Script:TarefasEncontradas = @(Get-TarefasAutodesk)
$Script:Resumo.ServicosIdentificados = $Script:ServicosEncontrados.Count
$Script:Resumo.TarefasIdentificadas = $Script:TarefasEncontradas.Count
$Script:Resumo.EntradasUninstallDetectadas = $AutodeskRegistrados.Count
$Script:Resumo.EntradasUninstallPreservadas = $AssociadosTerceiros.Count
if (-not $LimparEntradasDesinstalacao) {
    $Script:Resumo.EntradasUninstallPreservadas += $AutodeskRegistrados.Count
}

Write-Log ("Alvos: {0} pastas raiz, {1} arquivos ADSK/FLEXnet, {2} chaves Autodesk, {3} servicos, {4} tarefas." -f $Pastas.Count, $ArquivosAdsk.Count, $Chaves.Count, $Script:ServicosEncontrados.Count, $Script:TarefasEncontradas.Count)
if ($LimparEntradasDesinstalacao) {
    Write-Log ("[EXTRA] Remocao solicitada de {0} entradas de desinstalacao Autodesk." -f $AutodeskRegistrados.Count) 'Yellow'
    Write-Log '[AVISO] Isso NAO desinstala o MSI e pode prejudicar reparacao/remocao futura.' 'Yellow'
} else {
    Write-Log '[PROTECAO] Entradas de desinstalacao preservadas (use -LimparEntradasDesinstalacao para incluir).'
}
if ($AssociadosTerceiros.Count -gt 0) {
    Write-Log '[PROTECAO] Entradas de plugins/terceiros associadas ao Revit serao preservadas.' 'Yellow'
}
if (-not $Executar) {
    foreach ($S in $Script:ServicosEncontrados) {
        Write-Log ("[SIMULACAO SERVICO] {0}: {1}" -f $S.Name, $S.DisplayName) 'DarkGreen'
    }
    foreach ($T in $Script:TarefasEncontradas) {
        Write-Log ("[SIMULACAO TAREFA] {0}{1}" -f $T.TaskPath, $T.TaskName) 'DarkGreen'
    }
}

if ($Executar) {
    Write-Log ''
    Write-Log '[CONFIRMACAO] A limpeza de pastas, arquivos e servicos e destrutiva.' 'Yellow'
    Write-Log '[CONFIRMACAO] Faca backup de projetos, bibliotecas, familias e configuracoes.' 'Yellow'
    $Frase = if ($Instalados.Count -gt 0) { 'REMOVER INSTALADOS' } else { 'REMOVER' }
    if ($IncluirFlexNetCompartilhado) { $Frase += ' FLEXNET' }
    if ($LimparEntradasDesinstalacao) { $Frase += ' REGISTRO' }
    $Resposta = Read-Host "Digite exatamente '$Frase' para iniciar, ou outra coisa para cancelar"
    if ($Resposta -cne $Frase) {
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
        Write-Log '--- Etapa 3B: remover cadastros de servicos Autodesk/Flexnet selecionados ---'
        Remove-ServicosAutodesk
        Write-Log '--- Etapa 3C: backup e remocao de tarefas agendadas Autodesk ---'
        Remove-TarefasAutodesk
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

    if ($LimparEntradasDesinstalacao) {
        Write-Log '--- Etapa 6: limpar SOMENTE entradas Autodesk de Programas e Recursos ---'
        foreach ($Programa in $AutodeskRegistrados) {
            $Indice++
            $Nativa = $Programa.Native
            $ChaveUninstall = [pscustomobject]@{
                Ps = $Programa.Chave
                Native = $Nativa
            }
            $Antes = $Script:Resumo.ChavesExcluidas
            Remove-ChaveAlvo -Chave $ChaveUninstall -Indice $Indice
            if ($Script:Resumo.ChavesExcluidas -gt $Antes) {
                $Script:Resumo.EntradasUninstallRemovidas++
                # Evitar contar duas vezes a chave Uninstall no total.
                $Script:Resumo.ChavesExcluidas--
            }
        }
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
