# ============================================================
# TjTech - MANUTENÇÃO E OTIMIZAÇÃO DO WINDOWS
# Desenvolvido por Thomaz Jefferson - TjTech
# Execute o PowerShell como Administrador
# ============================================================

$Host.UI.RawUI.WindowTitle = "TjTech | Manutenção e Otimização do Windows | Desenvolvido por Thomaz Jefferson"

# ------------------------------------------------------------
# FUNÇÃO: Cabeçalho padrão
# ------------------------------------------------------------

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

function Mostrar-Cabecalho {
    Show-MaloviskyHeader -Section 'MENU 3 - OTIMIZACAO DO WINDOWS'
}

function Mostrar-Etapa {

    param(
        [int]$Numero,
        [int]$Total,
        [string]$Texto
    )

    $Percentual = [int](($Numero / $Total) * 100)

    Write-Progress `
        -Activity "MALOVISKY IT TOOLS | Manutencao do Windows" `
        -Status "Etapa $Numero de $Total - $Texto" `
        -PercentComplete $Percentual

    Mostrar-Cabecalho

    Write-Host " Computador : $env:COMPUTERNAME" -ForegroundColor Green
    Write-Host " Etapa      : $Numero de $Total" -ForegroundColor Green
    Write-Host " Progresso  : $Percentual%" -ForegroundColor Green
    Write-Host ""
    Write-Host " >> $Texto" -ForegroundColor Green
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host ""
}

# ------------------------------------------------------------
# VERIFICA SE É ADMINISTRADOR
# ------------------------------------------------------------

$Administrador = (
    New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $Administrador) {

    Mostrar-Cabecalho

    Write-Host "ERRO: Este script precisa ser executado como Administrador." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Clique com o botão direito no PowerShell e escolha:" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "    Executar como administrador" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Desenvolvido por Thomaz Jefferson - TjTech" `
        -ForegroundColor Green

    Write-Host ""

    Read-Host "Pressione Enter para fechar"

    exit
}

# ------------------------------------------------------------
# CONFIGURAÇÕES INICIAIS
# ------------------------------------------------------------

Mostrar-Cabecalho
Write-Host 'ATENCAO: a rotina habilita TRIM, otimiza C:, apaga TEMP e esvazia a Lixeira.'
Write-Host 'Tambem executa DISM, SFC e altera o plano para Alto Desempenho.'
Write-Host 'A limpeza da Lixeira e de temporarios pode ser irreversivel.'
Write-Host ''
$Confirmacao = Read-Host 'Digite EXECUTAR para iniciar, ou qualquer outra coisa para cancelar'
if ($Confirmacao -cne 'EXECUTAR') { Write-Host 'Cancelado.'; return }

$TotalEtapas = 10
$Inicio = Get-Date

Mostrar-Cabecalho

Write-Host "Iniciando manutenção preventiva do Windows..." `
    -ForegroundColor Green

Write-Host ""

Write-Host "O AnyDesk e os programas de inicialização NÃO serão alterados." `
    -ForegroundColor Green

Write-Host ""

Start-Sleep -Seconds 2

# ============================================================
# 1. INFORMAÇÕES DO COMPUTADOR
# ============================================================

Mostrar-Etapa 1 $TotalEtapas "Coletando informações do computador"

$Sistema = Get-CimInstance Win32_OperatingSystem
$Computador = Get-CimInstance Win32_ComputerSystem
$DiscoC = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

$RAMTotalGB = [math]::Round(
    $Computador.TotalPhysicalMemory / 1GB,
    2
)

$DiscoTotalGB = [math]::Round(
    $DiscoC.Size / 1GB,
    2
)

$DiscoLivreInicialGB = [math]::Round(
    $DiscoC.FreeSpace / 1GB,
    2
)

$PercentualLivre = [math]::Round(
    ($DiscoC.FreeSpace / $DiscoC.Size) * 100,
    2
)

Write-Host "Computador     : $env:COMPUTERNAME"
Write-Host "Windows        : $($Sistema.Caption)"
Write-Host "Versão         : $($Sistema.Version)"
Write-Host "Build          : $($Sistema.BuildNumber)"
Write-Host "Arquitetura    : $($Sistema.OSArchitecture)"
Write-Host "Memória RAM    : $RAMTotalGB GB"
Write-Host ""
Write-Host "Disco C:"
Write-Host "  Capacidade   : $DiscoTotalGB GB"
Write-Host "  Espaço livre : $DiscoLivreInicialGB GB"
Write-Host "  Livre        : $PercentualLivre%"

if ($PercentualLivre -lt 10) {

    Write-Host ""
    Write-Host "ATENÇÃO: O disco possui menos de 10% de espaço livre." `
        -ForegroundColor Green
}
elseif ($PercentualLivre -lt 20) {

    Write-Host ""
    Write-Host "AVISO: Recomenda-se manter pelo menos 20% do disco livre." `
        -ForegroundColor Green
}

Start-Sleep -Seconds 2

# ============================================================
# 2. VERIFICAÇÃO DO TRIM
# ============================================================

Mostrar-Etapa 2 $TotalEtapas "Verificando o TRIM"

Write-Host "Consultando configuração atual..." `
    -ForegroundColor Green

Write-Host ""

& fsutil.exe behavior query DisableDeleteNotify

Write-Host ""
Write-Host "DisableDeleteNotify = 0 significa que o TRIM está habilitado." `
    -ForegroundColor Green

Start-Sleep -Seconds 2

# ============================================================
# 3. ATIVAÇÃO DO TRIM
# ============================================================

Mostrar-Etapa 3 $TotalEtapas "Habilitando o TRIM"

& fsutil.exe behavior set DisableDeleteNotify 0

if ($LASTEXITCODE -eq 0) {

    Write-Host ""
    Write-Host "TRIM habilitado/verificado com sucesso." `
        -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Não foi possível confirmar a ativação do TRIM." `
        -ForegroundColor Green
}

Start-Sleep -Seconds 2

# ============================================================
# 4. OTIMIZAÇÃO DO DISCO
# ============================================================

Mostrar-Etapa 4 $TotalEtapas "Otimizando o disco C"

Write-Host "O Windows identificará automaticamente o tipo de unidade." `
    -ForegroundColor Green

Write-Host ""
Write-Host "SSD -> TRIM / ReTrim" -ForegroundColor Green
Write-Host "HD  -> Desfragmentação" -ForegroundColor Green

Write-Host ""
Write-Host "Iniciando otimização..." `
    -ForegroundColor Green

Write-Host ""

& defrag.exe C: /O /U /V

$ResultadoDefrag = $LASTEXITCODE

Write-Host ""

if ($ResultadoDefrag -eq 0) {

    Write-Host "Otimização do disco concluída." `
        -ForegroundColor Green
}
else {

    Write-Host "A otimização terminou com o código $ResultadoDefrag." `
        -ForegroundColor Green
}

# ============================================================
# 5. LIMPEZA DE ARQUIVOS TEMPORÁRIOS
# ============================================================

Mostrar-Etapa 5 $TotalEtapas "Limpando arquivos temporários"

$PastasTemporarias = @(
    $env:TEMP,
    "$env:LOCALAPPDATA\Temp",
    "$env:SystemRoot\Temp"
) | Select-Object -Unique

foreach ($Pasta in $PastasTemporarias) {

    if (Test-Path $Pasta) {

        Write-Host "Limpando: $Pasta" `
            -ForegroundColor Green

        Get-ChildItem `
            -LiteralPath $Pasta `
            -Force `
            -ErrorAction SilentlyContinue |
        Remove-Item `
            -Force `
            -Recurse `
            -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Arquivos temporários em uso foram preservados automaticamente." `
    -ForegroundColor Green

Write-Host ""

try {

    Clear-RecycleBin `
        -Force `
        -ErrorAction Stop

    Write-Host "Lixeira esvaziada." `
        -ForegroundColor Green
}
catch {

    Write-Host "A Lixeira já estava vazia ou não pôde ser esvaziada." `
        -ForegroundColor Green
}

# ============================================================
# 6. REPARAÇÃO DA IMAGEM DO WINDOWS
# ============================================================

Mostrar-Etapa 6 $TotalEtapas "Reparando a imagem do Windows com DISM"

Write-Host "Executando:" -ForegroundColor Green
Write-Host ""
Write-Host "DISM /Online /Cleanup-Image /RestoreHealth" `
    -ForegroundColor Green

Write-Host ""

& DISM.exe /Online /Cleanup-Image /RestoreHealth

$ResultadoDISM = $LASTEXITCODE

Write-Host ""

if ($ResultadoDISM -eq 0) {

    Write-Host "DISM concluído com sucesso." `
        -ForegroundColor Green
}
else {

    Write-Host "O DISM terminou com o código $ResultadoDISM." `
        -ForegroundColor Green
}

# ============================================================
# 7. VERIFICAÇÃO DOS ARQUIVOS DO WINDOWS
# ============================================================

Mostrar-Etapa 7 $TotalEtapas "Verificando arquivos do Windows com SFC"

Write-Host "Executando:" -ForegroundColor Green
Write-Host ""
Write-Host "SFC /SCANNOW" -ForegroundColor Green
Write-Host ""

& sfc.exe /scannow

$ResultadoSFC = $LASTEXITCODE

Write-Host ""

if ($ResultadoSFC -eq 0) {

    Write-Host "SFC finalizado." `
        -ForegroundColor Green
}
else {

    Write-Host "SFC finalizado com código $ResultadoSFC." `
        -ForegroundColor Green
}

# ============================================================
# 8. LIMPEZA DO REPOSITÓRIO DE COMPONENTES
# ============================================================

Mostrar-Etapa 8 $TotalEtapas "Limpando componentes antigos do Windows"

Write-Host "Executando limpeza do WinSxS..." `
    -ForegroundColor Green

Write-Host ""

& DISM.exe /Online /Cleanup-Image /StartComponentCleanup

$ResultadoComponentes = $LASTEXITCODE

Write-Host ""

if ($ResultadoComponentes -eq 0) {

    Write-Host "Limpeza de componentes concluída." `
        -ForegroundColor Green
}
else {

    Write-Host "A limpeza terminou com código $ResultadoComponentes." `
        -ForegroundColor Green
}

# ============================================================
# 9. PLANO DE ENERGIA
# ============================================================

Mostrar-Etapa 9 $TotalEtapas "Ativando o plano de Alto Desempenho"

& powercfg.exe /SetActive SCHEME_MIN

Write-Host ""
Write-Host "Plano de energia atual:" `
    -ForegroundColor Green

Write-Host ""

& powercfg.exe /GetActiveScheme

Write-Host ""
Write-Host "ATENÇÃO: Alto Desempenho pode aumentar o consumo de energia." `
    -ForegroundColor Green

Start-Sleep -Seconds 2

# ============================================================
# 10. DIAGNÓSTICO FINAL
# ============================================================

Mostrar-Etapa 10 $TotalEtapas "Gerando diagnóstico final"

Write-Host "ESTADO DOS DISCOS" `
    -ForegroundColor Green

Write-Host ""

Get-CimInstance Win32_DiskDrive |
    Select-Object `
        Model,
        MediaType,
        Status,
        @{
            Name = "TamanhoGB"
            Expression = {
                [math]::Round($_.Size / 1GB, 2)
            }
        } |
    Format-Table -AutoSize

Write-Host ""
Write-Host "------------------------------------------------------------" `
    -ForegroundColor Green

Write-Host ""
Write-Host "PROGRAMAS CONFIGURADOS PARA INICIAR COM O WINDOWS" `
    -ForegroundColor Green

Write-Host ""
Write-Host "A lista abaixo é somente informativa." `
    -ForegroundColor Green

Write-Host "Nenhum programa será desativado." `
    -ForegroundColor Green

Write-Host ""

Get-CimInstance Win32_StartupCommand |
    Select-Object `
        Name,
        Location,
        Command |
    Sort-Object Name |
    Format-Table -AutoSize -Wrap

# ------------------------------------------------------------
# ANYDESK
# ------------------------------------------------------------

Write-Host ""
Write-Host "------------------------------------------------------------" `
    -ForegroundColor Green

Write-Host ""
Write-Host "VERIFICAÇÃO DO ANYDESK" `
    -ForegroundColor Green

Write-Host ""

$ServicoAnyDesk = Get-Service `
    -Name "AnyDesk" `
    -ErrorAction SilentlyContinue

if ($ServicoAnyDesk) {

    Write-Host "Serviço AnyDesk encontrado." `
        -ForegroundColor Green

    Write-Host "Estado atual: $($ServicoAnyDesk.Status)"

    $ServicoAnyDeskCim = Get-CimInstance Win32_Service `
        -Filter "Name='AnyDesk'" `
        -ErrorAction SilentlyContinue

    if ($ServicoAnyDeskCim) {

        Write-Host "Inicialização: $($ServicoAnyDeskCim.StartMode)"
    }

    Write-Host ""
    Write-Host "Nenhuma configuração do AnyDesk foi alterada." `
        -ForegroundColor Green
}
else {

    Write-Host "Serviço AnyDesk não localizado com o nome 'AnyDesk'." `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Nenhuma configuração relacionada ao AnyDesk foi alterada." `
        -ForegroundColor Green
}

# ============================================================
# FINALIZAÇÃO
# ============================================================

Write-Progress `
    -Activity "MALOVISKY IT TOOLS | Manutencao do Windows" `
    -Completed

$Fim = Get-Date

$Duracao = New-TimeSpan `
    -Start $Inicio `
    -End $Fim

# Atualiza informações do disco depois da manutenção

$DiscoCFinal = Get-CimInstance `
    Win32_LogicalDisk `
    -Filter "DeviceID='C:'"

$DiscoLivreFinalGB = [math]::Round(
    $DiscoCFinal.FreeSpace / 1GB,
    2
)

$EspacoLiberadoGB = [math]::Round(
    $DiscoLivreFinalGB - $DiscoLivreInicialGB,
    2
)

Mostrar-Cabecalho

Write-Host "                 MANUTENÇÃO CONCLUÍDA" `
    -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor DarkGreen

Write-Host ""

Write-Host "Computador:" `
    -NoNewline `
    -ForegroundColor Green

Write-Host " $env:COMPUTERNAME" `
    -ForegroundColor Green

Write-Host ""

Write-Host "[OK] Informações do computador coletadas" `
    -ForegroundColor Green

Write-Host "[OK] TRIM verificado" `
    -ForegroundColor Green

Write-Host "[OK] TRIM habilitado" `
    -ForegroundColor Green

Write-Host "[OK] Disco otimizado" `
    -ForegroundColor Green

Write-Host "[OK] Arquivos temporários processados" `
    -ForegroundColor Green

Write-Host "[OK] DISM executado" `
    -ForegroundColor Green

Write-Host "[OK] SFC executado" `
    -ForegroundColor Green

Write-Host "[OK] Componentes antigos processados" `
    -ForegroundColor Green

Write-Host "[OK] Plano de energia configurado" `
    -ForegroundColor Green

Write-Host "[OK] Diagnóstico final realizado" `
    -ForegroundColor Green

Write-Host ""

Write-Host "------------------------------------------------------------" `
    -ForegroundColor Green

Write-Host ""

Write-Host "Duração da manutenção:" `
    -ForegroundColor Green

Write-Host ("{0:00}h {1:00}min {2:00}s" -f `
        [int]$Duracao.TotalHours,
        $Duracao.Minutes,
        $Duracao.Seconds
    )

Write-Host ""

Write-Host "Espaço livre antes : $DiscoLivreInicialGB GB"
Write-Host "Espaço livre depois: $DiscoLivreFinalGB GB"

if ($EspacoLiberadoGB -gt 0) {

    Write-Host "Espaço recuperado   : $EspacoLiberadoGB GB" `
        -ForegroundColor Green
}
elseif ($EspacoLiberadoGB -lt 0) {

    Write-Host "Variação do disco   : $EspacoLiberadoGB GB" `
        -ForegroundColor Green
}
else {

    Write-Host "Espaço recuperado   : Sem alteração significativa" `
        -ForegroundColor Green
}

Write-Host ""

Write-Host "Resultado DISM: $ResultadoDISM"
Write-Host "Resultado SFC : $ResultadoSFC"

Write-Host ""
Write-Host "------------------------------------------------------------" `
    -ForegroundColor Green

Write-Host ""

Write-Host "O AnyDesk e os programas de inicialização NÃO foram desativados." `
    -ForegroundColor Green

Write-Host ""

Write-Host "Recomenda-se reiniciar o computador após a manutenção." `
    -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor Green

Write-Host "        Desenvolvido por Thomaz Jefferson - TjTech" `
    -ForegroundColor Green

Write-Host "============================================================" `
    -ForegroundColor Green

Write-Host ""

Read-Host "Pressione Enter para finalizar"