#requires -Version 5.1
<#
.SYNOPSIS
  MALOVISKY IT TOOLS - Inventario de Hardware (Windows)
.DESCRIPTION
  Diagnostico local somente leitura. Exibe e exporta dados de hardware obtidos
  das interfaces CIM/WMI e Storage do Windows. Nao instala programas.
.EXAMPLE
  .\Malovisky_Hardware_Inventory.ps1
.EXAMPLE
  .\Malovisky_Hardware_Inventory.ps1 -AutoExport
.EXAMPLE
  .\Malovisky_Hardware_Inventory.ps1 -AutoExport -Formato TXT
.NOTES
  Powered by Thomaz J | Versao 1.0 | 13/11/2026
  Nao coleta senhas, seriais de dispositivos nem enderecos MAC.
  Informacoes dependem do firmware, drivers e provedores do Windows.
#>
[CmdletBinding()]
param(
    [switch]$AutoExport,
    [ValidateSet('TXT', 'JSON', 'AMBOS')]
    [string]$Formato = 'AMBOS',
    [string]$PastaRelatorios
)

$ErrorActionPreference = 'Stop'
$script:Linhas = New-Object 'System.Collections.Generic.List[string]'
$script:Avisos = New-Object 'System.Collections.Generic.List[string]'

function Escrever-Linha {
    param([AllowEmptyString()][string]$Texto = '', [string]$Cor = 'Green')
    $script:Linhas.Add($Texto)
    Write-Host $Texto -ForegroundColor $Cor
}
function Titulo-Secao {
    param([string]$Texto)
    Escrever-Linha ''
    Escrever-Linha ('=' * 72)
    Escrever-Linha (' {0}' -f $Texto.ToUpperInvariant())
    Escrever-Linha ('=' * 72)
}
function Campo {
    param([string]$Nome, [AllowNull()][object]$Valor)
    if ($null -eq $Valor -or [string]::IsNullOrWhiteSpace([string]$Valor)) {
        $Valor = 'Nao informado'
    }
    Escrever-Linha (' {0,-22}: {1}' -f $Nome, [string]$Valor)
}
function Limpar-Valor {
    param([AllowNull()][object]$Valor, [string]$Padrao = 'Nao informado')
    if ($null -eq $Valor) { return $Padrao }
    $texto = ([string]$Valor).Trim()
    if ($texto -eq '' -or $texto -match '(?i)^(unknown|not available|to be filled|default string|system product name|none|n/a)$') {
        return $Padrao
    }
    return $texto
}
function Obter-Cim {
    param([string]$Classe)
    try { return @(Get-CimInstance -ClassName $Classe -ErrorAction Stop) }
    catch {
        $script:Avisos.Add(('Consulta {0}: {1}' -f $Classe, $_.Exception.Message))
        return @()
    }
}
function Tamanho-Disco {
    param([AllowNull()][object]$Bytes)
    if ($null -eq $Bytes -or [double]$Bytes -le 0) { return 'Nao informado' }
    $valor = [double]$Bytes
    return ('{0:N1} GB ({1:N1} GiB)' -f ($valor / 1e9), ($valor / 1GB))
}
function Tamanho-Ram {
    param([AllowNull()][object]$Bytes)
    if ($null -eq $Bytes -or [double]$Bytes -le 0) { return 'Nao informado' }
    return ('{0:N1} GiB' -f ([double]$Bytes / 1GB))
}
function Tipo-Memoria {
    param($Memoria)
    # DMTF SMBIOS Type 17; valores 34=DDR5, 35=LPDDR5.
    $mapaSMBIOS = @{
        18='DDR'; 19='DDR2'; 20='DDR2 FB-DIMM'; 24='DDR3'; 25='FBD2';
        26='DDR4'; 27='LPDDR'; 28='LPDDR2'; 29='LPDDR3'; 30='LPDDR4';
        32='HBM'; 33='HBM2'; 34='DDR5'; 35='LPDDR5'; 36='HBM3'; 37='MRDIMM'
    }
    $codigo = [int]$Memoria.SMBIOSMemoryType
    if ($mapaSMBIOS.ContainsKey($codigo)) { return $mapaSMBIOS[$codigo] }
    $mapaCIM = @{ 20='DDR'; 21='DDR2'; 22='DDR2 FB-DIMM'; 24='DDR3'; 26='DDR4' }
    $codigoCim = [int]$Memoria.MemoryType
    if ($mapaCIM.ContainsKey($codigoCim)) { return $mapaCIM[$codigoCim] }
    return 'Nao identificado'
}
function Formato-Memoria {
    param([int]$Codigo)
    switch ($Codigo) {
        8  { 'DIMM'; break }
        12 { 'SODIMM'; break }
        13 { 'SRIMM'; break }
        9  { 'TSOP'; break }
        15 { 'FB-DIMM'; break }
        16 { 'Die / soldada'; break }
        default { 'Nao informado' }
    }
}
function Normalizar-Id {
    param([AllowNull()][object]$Valor)
    if ($null -eq $Valor) { return '' }
    return (([string]$Valor).ToUpperInvariant() -replace '[^A-Z0-9]', '')
}
function Comparar-DiscoFisico {
    param($DiscoWmi, [array]$DiscosStorage)
    # A associacao por DeviceId/Index nao e garantida entre provedores.
    # So usa serial exato ou combinacao inequivoca modelo + capacidade.
    $serial = Normalizar-Id $DiscoWmi.SerialNumber
    if ($serial.Length -ge 5 -and $serial -notmatch '^0+$') {
        $iguais = @($DiscosStorage | Where-Object {
            (Normalizar-Id $_.SerialNumber) -eq $serial
        })
        if ($iguais.Count -eq 1) { return $iguais[0] }
    }
    $modelo = Normalizar-Id $DiscoWmi.Model
    if ($modelo.Length -lt 5 -or [double]$DiscoWmi.Size -le 0) { return $null }
    $compativeis = @($DiscosStorage | Where-Object {
        $nome = Normalizar-Id $_.FriendlyName
        $tam = [double]$_.Size
        $diferenca = [math]::Abs($tam - [double]$DiscoWmi.Size)
        ($nome.Length -ge 5) -and
        (($nome.Contains($modelo)) -or ($modelo.Contains($nome))) -and
        ($diferenca -le ([double]$DiscoWmi.Size * 0.03))
    })
    if ($compativeis.Count -eq 1) { return $compativeis[0] }
    return $null
}
function Tipo-Disco {
    param($DiscoWmi, $DiscoStorage)
    if ($null -ne $DiscoStorage) {
        $meio = [string]$DiscoStorage.MediaType
        if ($meio -eq 'SSD' -or $meio -eq '4') { return 'SSD' }
        if ($meio -eq 'HDD' -or $meio -eq '3') { return 'HDD' }
        if ($meio -eq 'SCM' -or $meio -eq '5') { return 'SCM (memoria persistente)' }
    }
    # NVMe e um protocolo de armazenamento nao mecanico.
    if ([string]$DiscoWmi.InterfaceType -match 'NVMe' -or
        [string]$DiscoWmi.PNPDeviceID -match 'NVME') { return 'SSD (NVMe)' }
    return 'Nao identificado pelo Windows'
}
function Exportar-Relatorio {
    param([ValidateSet('TXT', 'JSON', 'AMBOS')][string]$Tipo)
    if ([string]::IsNullOrWhiteSpace($PastaRelatorios)) {
        $base = [Environment]::GetFolderPath('MyDocuments')
        if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
        $destino = Join-Path $base 'Malovisky IT Tools\Relatorios'
    }
    else { $destino = $PastaRelatorios }
    try {
        if (-not (Test-Path -LiteralPath $destino)) {
            New-Item -Path $destino -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        $nome = 'Hardware_{0}_{1}' -f ($env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss')
        if ($Tipo -eq 'TXT' -or $Tipo -eq 'AMBOS') {
            $txt = Join-Path $destino ($nome + '.txt')
            $script:Linhas | Out-File -FilePath $txt -Encoding utf8 -ErrorAction Stop
            Write-Host (' TXT : {0}' -f $txt) -ForegroundColor Green
        }
        if ($Tipo -eq 'JSON' -or $Tipo -eq 'AMBOS') {
            $json = Join-Path $destino ($nome + '.json')
            $script:Relatorio | ConvertTo-Json -Depth 8 | Out-File -FilePath $json -Encoding utf8 -ErrorAction Stop
            Write-Host (' JSON: {0}' -f $json) -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Host (' ERRO ao exportar: {0}' -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

try { $Host.UI.RawUI.BackgroundColor = 'Black' } catch { }
try { $Host.UI.RawUI.ForegroundColor = 'Green' } catch { }
try { Clear-Host } catch { }
Escrever-Linha ('=' * 72)
Escrever-Linha '             MALOVISKY IT TOOLS - POWERED BY THOMAZ J'
Escrever-Linha '                     INVENTARIO DE HARDWARE'
Escrever-Linha ('=' * 72)
Escrever-Linha ' MODO CONSULTA - NAO REALIZA ALTERACOES NO COMPUTADOR.'
Escrever-Linha ' USE POR SUA CONTA E RISCO - SOMENTE EM EQUIPAMENTOS AUTORIZADOS.'
Escrever-Linha ('=' * 72)
Escrever-Linha (' Coleta iniciada: {0}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))

$computadores = Obter-Cim 'Win32_ComputerSystem'
$placas = Obter-Cim 'Win32_BaseBoard'
$bioses = Obter-Cim 'Win32_BIOS'
$cpus = Obter-Cim 'Win32_Processor'
$memorias = @(Obter-Cim 'Win32_PhysicalMemory' | Where-Object { [double]$_.Capacity -gt 0 })
$arraysMemoria = @(Obter-Cim 'Win32_PhysicalMemoryArray' | Where-Object { $_.Use -eq 3 })
$gpus = Obter-Cim 'Win32_VideoController'
$discos = Obter-Cim 'Win32_DiskDrive'
$volumes = @(Obter-Cim 'Win32_LogicalDisk' | Where-Object { $_.DriveType -eq 3 })
$sistemas = Obter-Cim 'Win32_OperatingSystem'
$redes = @(Obter-Cim 'Win32_NetworkAdapter' | Where-Object { $_.PhysicalAdapter -eq $true })
$discosStorage = @()
if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
    try { $discosStorage = @(Get-PhysicalDisk -ErrorAction Stop) }
    catch { $script:Avisos.Add(('Get-PhysicalDisk: {0}' -f $_.Exception.Message)) }
}
else { $script:Avisos.Add('Modulo Storage/Get-PhysicalDisk nao disponivel; SSD/HDD pode aparecer como desconhecido.') }

$pc = $computadores | Select-Object -First 1
$placa = $placas | Select-Object -First 1
$bios = $bioses | Select-Object -First 1
$so = $sistemas | Select-Object -First 1
$cpuDados = @()
$ramDados = @()
$gpuDados = @()
$discoDados = @()
$volumeDados = @()
$redeDados = @()

Titulo-Secao 'Computador e sistema operacional'
Campo 'Computador' $env:COMPUTERNAME
Campo 'Fabricante' (Limpar-Valor $pc.Manufacturer)
Campo 'Modelo' (Limpar-Valor $pc.Model)
Campo 'Sistema' (Limpar-Valor $so.Caption)
Campo 'Versao / build' ('{0} / {1}' -f (Limpar-Valor $so.Version), (Limpar-Valor $so.BuildNumber))
Campo 'Arquitetura' (Limpar-Valor $so.OSArchitecture)

Titulo-Secao 'Placa-mae e BIOS/UEFI'
Campo 'Fabricante' (Limpar-Valor $placa.Manufacturer)
Campo 'Modelo da placa' (Limpar-Valor $placa.Product)
Campo 'Revisao' (Limpar-Valor $placa.Version)
Campo 'BIOS/UEFI' (Limpar-Valor $bios.SMBIOSBIOSVersion)
if ($bios -and $bios.ReleaseDate) {
    try { Campo 'Data do BIOS' (([datetime]$bios.ReleaseDate).ToString('dd/MM/yyyy')) }
    catch { Campo 'Data do BIOS' (Limpar-Valor $bios.ReleaseDate) }
}

Titulo-Secao 'Processador'
if ($cpus.Count -eq 0) { Escrever-Linha ' Nao identificado.' }
foreach ($cpu in $cpus) {
    $freq = if ([int]$cpu.MaxClockSpeed -gt 0) { '{0} MHz (max. reportado)' -f $cpu.MaxClockSpeed } else { 'Nao informado' }
    $item = [pscustomobject]@{
        Modelo = Limpar-Valor $cpu.Name
        Nucleos = [int]$cpu.NumberOfCores
        Threads = [int]$cpu.NumberOfLogicalProcessors
        FrequenciaMaximaMHz = [int]$cpu.MaxClockSpeed
        Soquete = Limpar-Valor $cpu.SocketDesignation
    }
    $cpuDados += $item
    Campo 'Modelo' $item.Modelo
    Campo 'Nucleos / threads' ('{0} / {1}' -f $item.Nucleos, $item.Threads)
    Campo 'Frequencia' $freq
    Campo 'Soquete' $item.Soquete
}

Titulo-Secao 'Memoria RAM'
$memInstaladas = $memorias.Count
$totalRamBytes = [double](($memorias | Measure-Object -Property Capacity -Sum).Sum)
$slotInfo = 'Nao informado pela BIOS'
if ($arraysMemoria.Count -gt 0) {
    $slots = [int](($arraysMemoria | Measure-Object -Property MemoryDevices -Sum).Sum)
    if ($slots -ge $memInstaladas -and $slots -gt 0) {
        $slotInfo = ('{0} reportados ({1} em uso, {2} livres)' -f $slots, $memInstaladas, ($slots - $memInstaladas))
    }
}
Campo 'Total instalado' (Tamanho-Ram $totalRamBytes)
Campo 'Pentes/modulos detectados' $memInstaladas
Campo 'Slots de memoria' $slotInfo
if ($memInstaladas -eq 0) { Escrever-Linha ' Nenhuma informacao de modulos retornada pelo Windows.' }
$numero = 0
foreach ($m in $memorias) {
    $numero++
    $tipo = Tipo-Memoria $m
    $forma = Formato-Memoria ([int]$m.FormFactor)
    $freq = if ([int]$m.ConfiguredClockSpeed -gt 0) { [int]$m.ConfiguredClockSpeed } else { [int]$m.Speed }
    $item = [pscustomobject]@{
        Modulo = $numero
        Local = Limpar-Valor $m.DeviceLocator
        Banco = Limpar-Valor $m.BankLabel
        CapacidadeGiB = [math]::Round(([double]$m.Capacity / 1GB), 2)
        Tipo = $tipo
        Formato = $forma
        VelocidadeReportadaMHz = $freq
        Fabricante = Limpar-Valor $m.Manufacturer
        Peca = Limpar-Valor $m.PartNumber
    }
    $ramDados += $item
    Escrever-Linha (' - MODULO {0} -' -f $numero)
    Campo 'Local / banco' ('{0} / {1}' -f $item.Local, $item.Banco)
    Campo 'Capacidade' ('{0} GiB' -f $item.CapacidadeGiB)
    Campo 'Tecnologia / formato' ('{0} / {1}' -f $tipo, $forma)
    Campo 'Velocidade reportada' $(if ($freq -gt 0) { '{0} MHz' -f $freq } else { 'Nao informado' })
    Campo 'Fabricante' $item.Fabricante
    Campo 'Part number' $item.Peca
}

Titulo-Secao 'Placa de video'
if ($gpus.Count -eq 0) { Escrever-Linha ' Nao identificada.' }
foreach ($gpu in $gpus) {
    $vram = 'Nao confiavel / nao informada'
    # Win32_VideoController.AdapterRAM usa UInt32 e pode limitar placas com mais de 4 GiB.
    if ([double]$gpu.AdapterRAM -gt 0) {
        $vram = ('{0:N1} GiB (estimativa WMI)' -f ([double]$gpu.AdapterRAM / 1GB))
    }
    $item = [pscustomobject]@{
        Modelo = Limpar-Valor $gpu.Name
        Driver = Limpar-Valor $gpu.DriverVersion
        MemoriaVideoEstimativa = $vram
        ResolucaoAtual = $(if ([int]$gpu.CurrentHorizontalResolution -gt 0) {
            '{0}x{1}' -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution
        } else { 'Nao informada' })
    }
    $gpuDados += $item
    Campo 'Modelo' $item.Modelo
    Campo 'VRAM' $item.MemoriaVideoEstimativa
    Campo 'Driver' $item.Driver
    Campo 'Resolucao' $item.ResolucaoAtual
    Escrever-Linha ''
}

Titulo-Secao 'Discos fisicos (SSD / HDD / NVMe)'
if ($discos.Count -eq 0) { Escrever-Linha ' Nenhum disco fisico retornado pelo Windows.' }
foreach ($d in $discos) {
    $ds = Comparar-DiscoFisico -DiscoWmi $d -DiscosStorage $discosStorage
    $tipo = Tipo-Disco -DiscoWmi $d -DiscoStorage $ds
    $interface = Limpar-Valor $d.InterfaceType
    if ($null -ne $ds -and -not [string]::IsNullOrWhiteSpace([string]$ds.BusType)) {
        $b = [string]$ds.BusType
        if ($b -ne 'Unknown' -and $b -ne '0') { $interface = $b }
    }
    $item = [pscustomobject]@{
        Numero = [int]$d.Index
        Modelo = Limpar-Valor $d.Model
        Tipo = $tipo
        Interface = $interface
        CapacidadeGB = [math]::Round(([double]$d.Size / 1e9), 2)
        CapacidadeGiB = [math]::Round(([double]$d.Size / 1GB), 2)
        EstadoStorage = $(if ($null -ne $ds) { Limpar-Valor $ds.HealthStatus } else { 'Nao informado' })
    }
    $discoDados += $item
    Escrever-Linha (' - DISCO {0} -' -f $item.Numero)
    Campo 'Modelo' $item.Modelo
    Campo 'Tipo' $item.Tipo
    Campo 'Interface' $item.Interface
    Campo 'Capacidade' (Tamanho-Disco $d.Size)
    Campo 'Saude informada' $item.EstadoStorage
}

Titulo-Secao 'Volumes locais'
if ($volumes.Count -eq 0) { Escrever-Linha ' Nenhum volume local informado.' }
foreach ($v in $volumes) {
    $livre = if ($null -ne $v.FreeSpace -and [double]$v.Size -gt 0) {
        '{0} livres' -f (Tamanho-Disco $v.FreeSpace)
    } else { 'Livre: nao informado' }
    $item = [pscustomobject]@{
        Unidade = Limpar-Valor $v.DeviceID
        Rotulo = Limpar-Valor $v.VolumeName
        SistemaArquivos = Limpar-Valor $v.FileSystem
        CapacidadeGB = [math]::Round(([double]$v.Size / 1e9), 2)
        LivreGB = [math]::Round(([double]$v.FreeSpace / 1e9), 2)
    }
    $volumeDados += $item
    Campo ('Unidade {0}' -f $item.Unidade) ('{0} | {1} | {2}' -f $item.Rotulo, (Tamanho-Disco $v.Size), $livre)
}

Titulo-Secao 'Adaptadores de rede fisicos'
if ($redes.Count -eq 0) { Escrever-Linha ' Nao informados ou nao ativos.' }
foreach ($r in $redes) {
    $item = [pscustomobject]@{
        Modelo = Limpar-Valor $r.Name
        Tipo = Limpar-Valor $r.AdapterType
        VelocidadeBitsPorSegundo = [double]$r.Speed
        Habilitado = ($r.NetEnabled -eq $true)
    }
    $redeDados += $item
    Campo 'Adaptador' $item.Modelo
    Campo 'Conectado/habilitado' $(if ($item.Habilitado) { 'Sim' } else { 'Nao ou nao informado' })
    if ($item.VelocidadeBitsPorSegundo -gt 0) {
        Campo 'Velocidade (WMI)' ('{0:N0} Mbps' -f ($item.VelocidadeBitsPorSegundo / 1e6))
    }
}

Titulo-Secao 'Observacoes tecnicas'
Escrever-Linha ' Dados baseados no Windows/BIOS; podem existir campos nao informados.'
Escrever-Linha ' Slots de RAM sao informados pelo firmware e podem estar incorretos.'
Escrever-Linha ' Em notebooks, modulos LPDDR podem ser soldados, nao pentes removiveis.'
Escrever-Linha ' Dois modulos detectados nao garantem operacao em dual-channel.'
Escrever-Linha ' Tipo SSD/HDD so e afirmado quando o provedor o identifica ou e NVMe.'
Escrever-Linha ' Estado de saude nao substitui analise SMART do fabricante.'
Escrever-Linha ' VRAM via WMI pode ser inexata, especialmente acima de 4 GiB.'
Escrever-Linha ' Nao inclui sensores de temperatura, voltagem ou potencia da fonte.'
if ($script:Avisos.Count -gt 0) {
    Escrever-Linha (' Consultas com restricao: {0}' -f $script:Avisos.Count) Yellow
    foreach ($a in $script:Avisos) { Escrever-Linha ('  - {0}' -f $a) Yellow }
}

$script:Relatorio = [pscustomobject][ordered]@{
    Aplicativo = 'Malovisky IT Tools - Inventario de Hardware'
    VersaoScript = '1.0'
    ColetadoEm = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    Computador = $env:COMPUTERNAME
    Fabricante = Limpar-Valor $pc.Manufacturer
    ModeloComputador = Limpar-Valor $pc.Model
    SistemaOperacional = Limpar-Valor $so.Caption
    VersaoSistema = Limpar-Valor $so.Version
    BuildSistema = Limpar-Valor $so.BuildNumber
    PlacaMae = [pscustomobject]@{
        Fabricante = Limpar-Valor $placa.Manufacturer
        Modelo = Limpar-Valor $placa.Product
        Revisao = Limpar-Valor $placa.Version
        BIOS = Limpar-Valor $bios.SMBIOSBIOSVersion
    }
    Processadores = @($cpuDados)
    RAM = [pscustomobject]@{
        TotalGiB = [math]::Round(($totalRamBytes / 1GB), 2)
        QuantidadeModulos = $memInstaladas
        SlotsInformados = $slotInfo
        Modulos = @($ramDados)
    }
    PlacasVideo = @($gpuDados)
    DiscosFisicos = @($discoDados)
    VolumesLocais = @($volumeDados)
    RedesFisicas = @($redeDados)
    ObservacoesColeta = @($script:Avisos.ToArray())
}
Escrever-Linha ''
Escrever-Linha ('=' * 72)
Escrever-Linha '                   INVENTARIO CONCLUIDO'
Escrever-Linha ('=' * 72)
Escrever-Linha (' CPUs: {0} | RAM: {1} modulo(s) | GPUs: {2} | Discos: {3}' -f $cpus.Count, $memInstaladas, $gpus.Count, $discos.Count)
Escrever-Linha ''

if ($AutoExport) {
    [void](Exportar-Relatorio -Tipo $Formato)
}
else {
    Write-Host ' Exportar relatorio? [1] TXT  [2] JSON  [3] AMBOS  [0] Sair' -ForegroundColor Green
    try {
        $escolha = Read-Host ' Opcao'
        switch ($escolha.Trim().ToUpperInvariant()) {
            '1' { [void](Exportar-Relatorio -Tipo 'TXT') }
            '2' { [void](Exportar-Relatorio -Tipo 'JSON') }
            '3' { [void](Exportar-Relatorio -Tipo 'AMBOS') }
            'TXT' { [void](Exportar-Relatorio -Tipo 'TXT') }
            'JSON' { [void](Exportar-Relatorio -Tipo 'JSON') }
            'AMBOS' { [void](Exportar-Relatorio -Tipo 'AMBOS') }
            default { Write-Host ' Relatorio nao exportado.' -ForegroundColor Green }
        }
    }
    catch { Write-Host ' Sem entrada interativa; exportacao ignorada.' -ForegroundColor Yellow }
}