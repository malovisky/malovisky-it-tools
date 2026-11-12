#requires -Version 5.1
<#
  Malovisky IT Tools - Bloqueio de fabricantes no Firewall do Windows
  - Selecoes multiplas: 2,3,5,6
  - Bloqueia entrada e saida para executaveis .exe encontrados em pastas
    identificadas por fabricante, inclusive nas subpastas.
  - Escaneia ProgramData, Program Files, Program Files (x86), Common Files,
    AppData (Local, Roaming e LocalLow) dos perfis locais.
  - SIMULAR nao modifica o Firewall.
  - REMOVER apaga somente as regras criadas por ESTE script (versao 2).
  - Nao apaga arquivos e nao impede a abertura de programas.
  - Executar no Windows PowerShell como administrador para aplicar/remover.
#>

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Green' } catch { }
$ruleGroup  = 'MALOVISKY_FABLOCK_V2'
$rulePrefix = 'MALOVISKY-FABLOCK-V2-'

# Mantenha os numeros 1 a 6 conforme a solicitacao.
$catalog = [ordered]@{
    '2'  = @{ Id = 'autodesk';  Label = 'AutoCAD / Autodesk'; Pattern = '^(Autodesk|AutoCAD)' }
    '3'  = @{ Id = 'graphisoft'; Label = 'ArchiCAD / Graphisoft'; Pattern = '^(Graphisoft|ArchiCAD)' }
    '4'  = @{ Id = 'corel';     Label = 'Corel'; Pattern = '^Corel' }
    '5'  = @{ Id = 'flexnet';   Label = 'FlexNet / Flexera'; Pattern = '^(FlexNet|Flexera|FLEXlm)' }
    '6'  = @{ Id = 'sketchup';  Label = 'SketchUp'; Pattern = '^SketchUp' }
    '7'  = @{ Id = 'adobe';     Label = 'Adobe'; Pattern = '^Adobe' }
    '8'  = @{ Id = 'trimble';   Label = 'Trimble'; Pattern = '^Trimble' }
    '9'  = @{ Id = 'enscape';   Label = 'Enscape'; Pattern = '^Enscape' }
    '10' = @{ Id = 'chaos';     Label = 'Chaos / V-Ray'; Pattern = '^(Chaos|V-Ray)' }
    '11' = @{ Id = 'codemeter'; Label = 'CodeMeter'; Pattern = '^CodeMeter' }
}

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

function Show-Header {
    Show-MaloviskyHeader -Section 'MENU 2 - FIREWALL DOS FABRICANTES'
    Write-Host ' Selecione os fabricantes para bloquear:'
    Write-Host ' [1] TODOS OS FABRICANTES'
    foreach ($n in $catalog.Keys) { Write-Host (' [{0}] {1}' -f $n, $catalog[$n].Label) }
    Write-Host ''
    Write-Host ' [0] Voltar'
    Write-Host ' Exemplo: 2,3,5,6'
}

function Read-Selection {
    while ($true) {
        $raw = Read-Host 'Digite os numeros separados por virgula'
        if ($null -eq $raw) { continue }
        $raw = $raw.Trim()
        if ($raw -eq '0') { return $null }
        if ($raw -eq '1') { return @($catalog.Keys) }

        $tokens = @($raw -split '[,;\s]+' | Where-Object { $_ -ne '' })
        $bad = @($tokens | Where-Object { -not $catalog.Contains($_) })
        if ($tokens.Count -eq 0 -or $bad.Count -gt 0 -or $tokens -contains '1' -or $tokens -contains '0') {
            Write-Host 'Selecao invalida. Use 1 para todos ou numeros como 2,3,5,6.' -ForegroundColor Green
            continue
        }
        # Mantem a ordem do menu e remove duplicatas.
        return @($catalog.Keys | Where-Object { $tokens -contains $_ })
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Retorna os diretorios pedidos; inclui perfis locais registrados e C:\Users.
function Get-ScanRoots {
    $dirs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    function Add-Dir([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        try {
            $expanded = [Environment]::ExpandEnvironmentVariables($p)
            if ([IO.Directory]::Exists($expanded)) {
                [void]$dirs.Add([IO.Path]::GetFullPath($expanded).TrimEnd('\'))
            }
        } catch {
            Write-Warning ('Caminho ignorado: ' + $p)
        }
    }

    $systemDrive = $env:SystemDrive
    if (-not $systemDrive) { $systemDrive = 'C:' }
    # Diretorios C:\ solicitados, mesmo se Windows estiver em outra unidade.
    Add-Dir 'C:\ProgramData'
    Add-Dir 'C:\Program Files'
    Add-Dir 'C:\Program Files (x86)'
    Add-Dir 'C:\Program Files\Common Files'
    Add-Dir 'C:\Program Files (x86)\Common Files'
    Add-Dir (Join-Path $systemDrive 'ProgramData')
    Add-Dir (Join-Path $systemDrive 'Program Files')
    Add-Dir (Join-Path $systemDrive 'Program Files (x86)')
    Add-Dir (Join-Path $systemDrive 'Program Files\Common Files')
    Add-Dir (Join-Path $systemDrive 'Program Files (x86)\Common Files')
    Add-Dir $env:ProgramData
    Add-Dir $env:ProgramFiles
    Add-Dir ${env:ProgramFiles(x86)}
    Add-Dir $env:CommonProgramFiles
    Add-Dir ${env:CommonProgramFiles(x86)}
    Add-Dir $env:APPDATA
    Add-Dir $env:LOCALAPPDATA
    if ($env:USERPROFILE) { Add-Dir (Join-Path $env:USERPROFILE 'AppData') }

    $profiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $profileKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    try {
        foreach ($key in @(Get-ChildItem -LiteralPath $profileKey -ErrorAction Stop)) {
            $p = (Get-ItemProperty -LiteralPath $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
            if (-not $p) { continue }
            $p = [Environment]::ExpandEnvironmentVariables($p)
            if ($p -match '^[A-Za-z]:\\' -and [IO.Directory]::Exists($p)) {
                [void]$profiles.Add($p)
            }
        }
    } catch {
        Write-Warning ('Nao foi possivel ler ProfileList: ' + $_.Exception.Message)
    }

    foreach ($usersDir in @('C:\Users', (Join-Path $systemDrive 'Users'))) {
        if ([IO.Directory]::Exists($usersDir)) {
            foreach ($profileDir in @(Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue)) {
                if (($profileDir.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                    [void]$profiles.Add($profileDir.FullName)
                }
            }
        }
    }
    foreach ($p in $profiles) {
        Add-Dir (Join-Path $p 'AppData')
        Add-Dir (Join-Path $p 'AppData\Local')
        Add-Dir (Join-Path $p 'AppData\Roaming')
    }

    # Se uma raiz ja esta contida em outra, percorremos so a raiz maior.
    $sorted = @($dirs | Sort-Object Length)
    $distinct = New-Object 'System.Collections.Generic.List[string]'
    foreach ($d in $sorted) {
        $nested = $false
        foreach ($parent in $distinct) {
            if ($d.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $d.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) {
                $nested = $true
                break
            }
        }
        if (-not $nested) { [void]$distinct.Add($d) }
    }
    return @($distinct.ToArray())
}

# Encontra as pastas pertencentes aos fabricantes e coleta todos os EXEs
# contidos nelas (inclusive nas subpastas). Nao segue junctions/symlinks.
function Find-SelectedExecutables([string[]]$selectedNumbers, [string[]]$roots) {
    $selected = @($selectedNumbers | ForEach-Object { $catalog[$_] })
    $found = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    $visitedFolders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $errors = 0
    $matched = 0

    foreach ($root in $roots) {
        Write-Host ('Verificando: ' + $root) -ForegroundColor Green
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($root)
        while ($pending.Count -gt 0) {
            $current = $pending.Pop()
            if (-not $visitedFolders.Add($current)) { continue }

            $folderName = [IO.Path]::GetFileName($current.TrimEnd('\'))
            $vendor = $null
            foreach ($entry in $selected) {
                if ($folderName -match $entry.Pattern) { $vendor = $entry; break }
            }
            if ($null -ne $vendor) {
                $matched++
                $inside = New-Object 'System.Collections.Generic.Stack[string]'
                $inside.Push($current)
                while ($inside.Count -gt 0) {
                    $dir = $inside.Pop()
                    try {
                        foreach ($exe in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.exe' -Force -ErrorAction Stop)) {
                            if (($exe.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                                -not $found.ContainsKey($exe.FullName)) {
                                $found.Add($exe.FullName, [pscustomobject]@{
                                    Path = $exe.FullName
                                    VendorId = $vendor.Id
                                    VendorLabel = $vendor.Label
                                })
                            }
                        }
                    } catch { $errors++ }
                    try {
                        foreach ($sub in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction Stop)) {
                            if (($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                                $inside.Push($sub.FullName)
                            }
                        }
                    } catch { $errors++ }
                }
                continue
            }

            try {
                foreach ($sub in @(Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction Stop)) {
                    if (($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $pending.Push($sub.FullName)
                    }
                }
            } catch { $errors++ }
        }
    }

    return [pscustomobject]@{
        Executables = @($found.Values | Sort-Object Path)
        MatchedFolders = $matched
        ScanErrors = $errors
    }
}

function Get-ManagedRules {
    $all = @(Get-NetFirewallRule -PolicyStore PersistentStore -Group $ruleGroup -ErrorAction SilentlyContinue)
    return @($all | Where-Object { $_.Name.StartsWith($rulePrefix, [StringComparison]::OrdinalIgnoreCase) })
}

function Get-RuleName([string]$vendorId, [string]$path, [string]$suffix, $sha) {
    $data = [Text.Encoding]::UTF8.GetBytes($path.ToLowerInvariant())
    $hash = [BitConverter]::ToString($sha.ComputeHash($data)).Replace('-', '').Substring(0, 24)
    return ('{0}{1}-{2}-{3}' -f $rulePrefix, $vendorId, $hash, $suffix)
}

Show-Header
$numbers = @(Read-Selection)
if ($numbers.Count -eq 0) { Write-Host 'Operacao cancelada.'; return }

Write-Host ''
Write-Host ('Fabricantes escolhidos: ' + (($numbers | ForEach-Object { $catalog[$_].Label }) -join ', ')) -ForegroundColor Green
Write-Host ''
Write-Host 'O que deseja fazer?'
Write-Host '   1 - APLICAR bloqueios (entrada e saida)'
Write-Host '   2 - SIMULAR (so listar os executaveis)'
Write-Host '   3 - REMOVER bloqueios destes fabricantes'
Write-Host '   0 - Cancelar'
$operation = Read-Host 'Escolha a acao [Enter = 2 (SIMULAR)]'
if ([string]::IsNullOrWhiteSpace($operation)) { $operation = '2' }
if ($operation -eq '0') { Write-Host 'Operacao cancelada.'; return }
if ($operation -notin @('1', '2', '3')) { Write-Host 'Acao invalida.' -ForegroundColor Green; return }

$mode = @{ '1' = 'APLICAR'; '2' = 'SIMULAR'; '3' = 'REMOVER' }[$operation]
if ($mode -ne 'SIMULAR') {
    Write-Host 'ATENCAO: o Firewall sera alterado. Programas podem perder conectividade.'
    $token = if ($mode -eq 'APLICAR') { 'BLOQUEAR' } else { 'REMOVER' }
    $answer = Read-Host ("Digite $token para confirmar")
    if ($answer -cne $token) { Write-Host 'Operacao cancelada.'; return }
}

if ($mode -ne 'SIMULAR' -and -not (Test-IsAdmin)) {
    Write-Host 'ERRO: abra o PowerShell com Executar como administrador.' -ForegroundColor Green
    return
}

try { Import-Module NetSecurity -ErrorAction Stop }
catch {
    Write-Host ('Modulo NetSecurity indisponivel: ' + $_.Exception.Message) -ForegroundColor Green
    return
}

$selectedIds = @($numbers | ForEach-Object { $catalog[$_].Id })

if ($mode -eq 'REMOVER') {
    $rules = @(Get-ManagedRules | Where-Object {
        $ruleName = $_.Name
        @($selectedIds | Where-Object {
            $ruleName.StartsWith(($rulePrefix + $_ + '-'), [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
    })
    if ($rules.Count -eq 0) {
        Write-Host 'Nenhuma regra deste script encontrada para os fabricantes selecionados.' -ForegroundColor Green
    } else {
        Write-Host ('Removendo {0} regras deste script...' -f $rules.Count) -ForegroundColor Green
        $removed = 0
        $failed = 0
        foreach ($rule in $rules) {
            try { Remove-NetFirewallRule -Name $rule.Name -PolicyStore PersistentStore -ErrorAction Stop; $removed++ }
            catch { $failed++; Write-Warning $_.Exception.Message }
        }
        Write-Host ('Regras removidas: {0} | Falhas: {1}' -f $removed, $failed)
    }
    Write-Host 'Regras de outros scripts e fabricantes nao selecionados foram preservadas.'
    return
}

$roots = @(Get-ScanRoots)
Write-Host ''
Write-Host ('Pastas-raiz localizadas: {0}' -f $roots.Count)
Write-Host 'Buscando executaveis. A varredura pode demorar em equipamentos com muitos programas...' -ForegroundColor Green
$result = Find-SelectedExecutables -selectedNumbers $numbers -roots $roots
$items = @($result.Executables)
Write-Host ''
Write-Host ('Pastas de fabricantes encontradas: {0}' -f $result.MatchedFolders)
Write-Host ('Executaveis .exe encontrados: {0}' -f $items.Count) -ForegroundColor Green
if ($result.ScanErrors -gt 0) {
    Write-Warning ('Diretorios sem acesso ou falhas de leitura: {0}. Alguns arquivos podem nao ter sido localizados.' -f $result.ScanErrors)
}

# Gera um CSV com a lista completa para auditoria.
$logDir = Join-Path $env:TEMP 'MaloviskyFirewall'
try {
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $report = Join-Path $logDir ('Fabricantes_{0}_{1}.csv' -f $mode, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if ($items.Count -gt 0) {
        $items | Select-Object VendorLabel, Path | Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8
    } else {
        '"VendorLabel","Path"' | Set-Content -LiteralPath $report -Encoding UTF8
    }
    Write-Host ('Relatorio CSV: ' + $report)
} catch { Write-Warning ('Falha ao gravar relatorio: ' + $_.Exception.Message) }

if ($mode -eq 'SIMULAR') {
    $items | Select-Object -First 50 | ForEach-Object {
        Write-Host ('  [{0}] {1}' -f $_.VendorLabel, $_.Path)
    }
    if ($items.Count -gt 50) { Write-Host ('... e mais {0} executaveis no CSV.' -f ($items.Count - 50)) }
    Write-Host 'SIMULACAO concluida. Nenhuma regra foi alterada.' -ForegroundColor Green
    return
}

if ($items.Count -eq 0) {
    Write-Host 'Nenhum .exe encontrado nas pastas dos fabricantes selecionados.' -ForegroundColor Green
    return
}

$existing = @{}
foreach ($r in @(Get-ManagedRules)) { $existing[$r.Name] = $r }
$sha = [Security.Cryptography.SHA256]::Create()
$created = 0
$already = 0
$reactivated = 0
$failed = 0
$consecutiveFailures = 0
$stoppedEarly = $false

try {
    foreach ($item in $items) {
        foreach ($directionInfo in @(
            @{ Suffix = 'OUT'; Direction = 'Outbound'; Label = 'Saida' },
            @{ Suffix = 'IN'; Direction = 'Inbound'; Label = 'Entrada' }
        )) {
            $name = Get-RuleName -vendorId $item.VendorId -path $item.Path -suffix $directionInfo.Suffix -sha $sha
            try {
                if ($existing.ContainsKey($name)) {
                    $r = $existing[$name]
                    if ($r.Enabled.ToString() -ne 'True' -or $r.Action.ToString() -ne 'Block') {
                        Set-NetFirewallRule -Name $name -PolicyStore PersistentStore -Action Block -Enabled True -ErrorAction Stop
                        $reactivated++
                    } else { $already++ }
                    $consecutiveFailures = 0
                    continue
                }
                # Evita caracteres proibidos no nome amigavel da regra do Firewall.
                $exeName = [IO.Path]::GetFileName($item.Path)
                $exeName = [regex]::Replace($exeName, '[^a-zA-Z0-9._ -]', '_')
                if ($exeName.Length -gt 70) { $exeName = $exeName.Substring(0, 70) }
                $displayName = 'Malovisky - {0} - {1} - {2}' -f $item.VendorId, $directionInfo.Suffix, $exeName

                New-NetFirewallRule -Name $name `
                    -DisplayName $displayName `
                    -Group $ruleGroup `
                    -Description 'Regra criada e gerenciada pelo Malovisky IT Tools Firewall.' `
                    -Direction $directionInfo.Direction -Action Block -Program $item.Path `
                    -Profile Any -Enabled True -PolicyStore PersistentStore -ErrorAction Stop | Out-Null
                $created++
                $consecutiveFailures = 0
            } catch {
                $failed++
                $consecutiveFailures++
                Write-Warning ('Erro: {0} ({1}): {2}' -f $item.Path, $directionInfo.Suffix, $_.Exception.Message)
                if ($consecutiveFailures -ge 6) {
                    Write-Host 'Seis falhas consecutivas: interrompendo para evitar centenas de erros iguais.' -ForegroundColor Green
                    $stoppedEarly = $true
                    break
                }
            }
        }
        if ($stoppedEarly) { break }
    }
} finally { $sha.Dispose() }

Write-Host ''
Write-Host '================= RESUMO =================' -ForegroundColor Green
Write-Host ('Regras novas:             {0}' -f $created) -ForegroundColor Green
Write-Host ('Regras ja existentes:     {0}' -f $already)
Write-Host ('Regras reativadas:        {0}' -f $reactivated)
Write-Host ('Falhas:                  {0}' -f $failed)
if ($stoppedEarly) { Write-Host 'Execucao interrompida por falhas repetidas. Consulte a primeira mensagem de erro.' -ForegroundColor Green }
Write-Host '==========================================' -ForegroundColor Green
Write-Host 'Para desfazer, execute novamente e escolha a opcao 3 (REMOVER).'