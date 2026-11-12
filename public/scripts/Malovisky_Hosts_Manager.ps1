#Requires -Version 5.1
# MALOVISKY IT TOOLS - Powered by Thomaz J
# Gerenciador de HOSTS - consulta, remocao de linha, redefinicao e restauracao.
# Uso exclusivo em maquinas sob sua administracao.

$ErrorActionPreference = 'Stop'

# Sysnative evita redirecionamento de System32 em PowerShell de 32 bits.
$System32 = Join-Path $env:WINDIR 'System32'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $System32 = Join-Path $env:WINDIR 'Sysnative'
}
$HostsPath = Join-Path $System32 'drivers\etc\hosts'
$BackupPath = "$HostsPath.bkp"

function Set-MatrixVisual {
    try {
        $Host.UI.RawUI.BackgroundColor = 'Black'
        $Host.UI.RawUI.ForegroundColor = 'Green'
        $Host.UI.RawUI.WindowTitle = 'MALOVISKY IT TOOLS - GERENCIADOR DE HOSTS'
    } catch { }
}

function Show-Header([string]$Section) {
    Set-MatrixVisual
    Clear-Host
    Write-Host '=======================================================================' -ForegroundColor DarkGreen
    Write-Host '             MALOVISKY IT TOOLS - POWERED BY THOMAZ J' -ForegroundColor Green
    Write-Host '=======================================================================' -ForegroundColor DarkGreen
    Write-Host (' ' + $Section) -ForegroundColor Green
    Write-Host ' USE POR SUA CONTA E RISCO - SOMENTE EM EQUIPAMENTOS AUTORIZADOS.' -ForegroundColor DarkGreen
    Write-Host '=======================================================================' -ForegroundColor DarkGreen
    Write-Host ''
}

function Pause-Malovisky {
    Write-Host ''
    [void](Read-Host 'Pressione ENTER para continuar')
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Esta operacao exige Windows PowerShell executado como ADMINISTRADOR.'
    }
}

function Get-HostsDocument {
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        return @{ Lines = [string[]]@(); Encoding = ([System.Text.UTF8Encoding]::new($false)); Newline = "`r`n"; FinalNewline = $true }
    }

    $bytes = [IO.File]::ReadAllBytes($HostsPath)
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $encoding = [System.Text.UTF8Encoding]::new($true)
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $encoding = [Text.Encoding]::Unicode
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        $encoding = [Text.Encoding]::BigEndianUnicode
    }

    try {
        $text = $encoding.GetString($bytes)
    } catch [Text.DecoderFallbackException] {
        # Arquivos antigos podem conter comentarios ANSI/Windows-1252.
        $encoding = [Text.Encoding]::Default
        $text = $encoding.GetString($bytes)
    }
    if ($text.StartsWith([string][char]0xFEFF)) { $text = $text.Substring(1) }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } elseif ($text.Contains("`r")) { "`r" } else { "`r`n" }
    $finalNewline = $text.EndsWith("`n") -or $text.EndsWith("`r")
    $lines = [string[]]@()
    if ($text.Length -gt 0) {
        $lines = [string[]]([regex]::Split($text, "`r`n|`n|`r"))
        if ($finalNewline -and $lines.Length -gt 0) {
            $lines = [string[]]@($lines | Select-Object -SkipLast 1)
        }
    }
    return @{ Lines = $lines; Encoding = $encoding; Newline = $newline; FinalNewline = $finalNewline }
}

function Show-HostsContent {
    Show-Header 'CONSULTAR ARQUIVO HOSTS ATUAL'
    Write-Host (' Caminho: ' + $HostsPath) -ForegroundColor Green
    Write-Host (' Backup:  ' + $BackupPath) -ForegroundColor DarkGreen
    Write-Host ''
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        Write-Host ' O arquivo hosts nao existe neste equipamento.' -ForegroundColor Green
        return
    }
    $doc = Get-HostsDocument
    $active = 0
    if ($doc.Lines.Length -eq 0) {
        Write-Host ' (Arquivo vazio)' -ForegroundColor Green
    } else {
        for ($i = 0; $i -lt $doc.Lines.Length; $i++) {
            $line = $doc.Lines[$i]
            $isActive = -not ($line -match '^\s*(#|$)')
            if ($isActive) { $active++ }
            $color = if ($isActive) { 'Green' } else { 'DarkGreen' }
            $flag = if ($isActive) { 'ATIVA     ' } else { 'COMENTARIO' }
            Write-Host (' [{0,3}] {1} | {2}' -f ($i + 1), $flag, $line) -ForegroundColor $color
        }
    }
    Write-Host ''
    Write-Host (' Total de linhas: {0} | Entradas ativas: {1}' -f $doc.Lines.Length, $active) -ForegroundColor Green
    Write-Host (' Backup disponivel: ' + $(if (Test-Path -LiteralPath $BackupPath -PathType Leaf) { 'SIM' } else { 'NAO' })) -ForegroundColor Green
}

function New-HostsBackup {
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        Write-Host ' Hosts anterior inexistente; nao ha arquivo original para backup.' -ForegroundColor DarkGreen
        return
    }
    $archive = $null
    if (Test-Path -LiteralPath $BackupPath) {
        $archive = "$BackupPath.$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
        Move-Item -LiteralPath $BackupPath -Destination $archive -ErrorAction Stop
        Write-Host (' Backup anterior preservado em: ' + $archive) -ForegroundColor Green
    }
    try {
        Copy-Item -LiteralPath $HostsPath -Destination $BackupPath -ErrorAction Stop
        $sourceHash = (Get-FileHash -LiteralPath $HostsPath -Algorithm SHA256).Hash
        $backupHash = (Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $backupHash) { throw 'A copia do backup nao passou na verificacao SHA-256.' }
        Write-Host (' Backup atual criado e verificado: ' + $BackupPath) -ForegroundColor Green
    } catch {
        if (Test-Path -LiteralPath $BackupPath) { Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue }
        if ($archive -and (Test-Path -LiteralPath $archive)) {
            Move-Item -LiteralPath $archive -Destination $BackupPath -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Save-HostsContent {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory = $true)][System.Text.Encoding]$Encoding,
        [Parameter(Mandatory = $true)][string]$Newline,
        [bool]$FinalNewline = $true
    )
    Assert-Administrator
    $content = [string]::Join($Newline, $Lines)
    if ($FinalNewline -and $Lines.Length -gt 0) { $content += $Newline }

    # Sobrescreve o conteudo diretamente, preservando as permissoes do hosts existente.
    # O backup verificado e criado por New-HostsBackup ANTES desta funcao.
    # Evita File.Replace(..., $null), que falhou em alguns ambientes Windows.
    if ((Test-Path -LiteralPath $HostsPath -PathType Leaf) -and
        -not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw 'Backup hosts.bkp ausente. Gravacao bloqueada para proteger o arquivo atual.'
    }
    try {
        [IO.File]::WriteAllText($HostsPath, $content, $Encoding)
        $saved = [IO.File]::ReadAllText($HostsPath, $Encoding)
        if ($saved -cne $content) { throw 'O conteudo gravado nao corresponde ao esperado.' }
    } catch {
        throw ('Falha na gravacao/verificacao do hosts: ' + $_.Exception.Message +
               '. O backup hosts.bkp foi preservado.')
    }
    Write-Host (' Hosts gravado e verificado: ' + $HostsPath) -ForegroundColor Green
    Clear-HostsDnsCache
}

function Clear-HostsDnsCache {
    Write-Host ' Solicitando limpeza do cache DNS...' -ForegroundColor DarkGreen
    try {
        $exe = Join-Path $System32 'ipconfig.exe'
        & $exe /flushdns | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('ipconfig retornou codigo ' + $LASTEXITCODE) }
        Write-Host ' Cache DNS limpo com sucesso.' -ForegroundColor Green
    } catch {
        Write-Host (' AVISO: nao foi possivel limpar o cache DNS: ' + $_.Exception.Message) -ForegroundColor Green
    }
}

function Remove-HostsLine {
    Show-HostsContent
    Assert-Administrator
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) { throw 'Arquivo hosts inexistente.' }
    $doc = Get-HostsDocument
    if ($doc.Lines.Length -eq 0) { Write-Host ' Nao ha linhas para remover.' -ForegroundColor Green; return }
    Write-Host ''
    $choice = (Read-Host 'Numero da linha para remover [ENTER cancela]').Trim()
    if ($choice -eq '') { Write-Host ' Operacao cancelada.' -ForegroundColor Green; return }
    if ($choice -notmatch '^\d+$') { throw 'Informe somente o numero da linha.' }
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number)) { throw 'Numero invalido.' }
    if ($number -lt 1 -or $number -gt $doc.Lines.Length) { throw 'Numero fora da lista apresentada.' }

    $line = $doc.Lines[$number - 1]
    Write-Host (' Linha selecionada [{0}]: {1}' -f $number, $line) -ForegroundColor Green
    Write-Host ' ATENCAO: remover esta linha pode afetar acessos que usam resolucao local.' -ForegroundColor Green
    $confirm = Read-Host 'Digite REMOVER para confirmar'
    if ($confirm -cne 'REMOVER') { Write-Host ' Operacao cancelada.' -ForegroundColor Green; return }

    # Verifica se outro processo alterou o arquivo entre a consulta e a exclusao.
    $current = Get-HostsDocument
    if ($current.Lines.Length -ne $doc.Lines.Length -or $current.Lines[$number - 1] -cne $line) {
        throw 'O hosts foi alterado durante a operacao. Consulte novamente.'
    }
    $newLines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $current.Lines.Length; $i++) {
        if ($i -ne ($number - 1)) { $newLines.Add($current.Lines[$i]) }
    }
    New-HostsBackup
    Save-HostsContent -Lines ([string[]]$newLines.ToArray()) -Encoding $current.Encoding -Newline $current.Newline -FinalNewline $current.FinalNewline
    Write-Host ' Linha removida. Backup do arquivo anterior preservado.' -ForegroundColor Green
}

function Reset-HostsToDefault {
    Show-Header 'REDEFINIR HOSTS - PADRAO MICROSOFT WINDOWS'
    Assert-Administrator
    Write-Host ' Esta operacao remove TODAS as entradas personalizadas do hosts.' -ForegroundColor Green
    Write-Host ' Pode afetar sistemas internos, VPN, desenvolvimento e bloqueios locais.' -ForegroundColor Green
    Write-Host ' Antes de substituir, o arquivo atual sera salvo como hosts.bkp.' -ForegroundColor Green
    Write-Host ' Se ja existir hosts.bkp, ele sera arquivado com data e hora.' -ForegroundColor Green
    Write-Host ''
    $confirm = Read-Host 'Digite REDEFINIR para continuar'
    if ($confirm -cne 'REDEFINIR') { Write-Host ' Operacao cancelada.' -ForegroundColor Green; return }

    $default = @(
        '# Copyright (c) 1993-2009 Microsoft Corp.'
        '#'
        '# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.'
        '#'
        '# This file contains the mappings of IP addresses to host names. Each'
        '# entry should be kept on an individual line. The IP address should'
        '# be placed in the first column followed by the corresponding host name.'
        '# The IP address and the host name should be separated by at least one'
        '# space.'
        '#'
        '# Additionally, comments (such as these) may be inserted on individual'
        "# lines or following the machine name denoted by a '#' symbol."
        '#'
        '# For example:'
        '#'
        '#      102.54.94.97     rhino.acme.com          # source server'
        '#       38.25.63.10     x.acme.com              # x client host'
        '#'
        '# localhost name resolution is handled within DNS itself.'
        '#   127.0.0.1       localhost'
        '#   ::1             localhost'
        '#'
        '#REDEFINIDO COM MALOVISKY IT TOOLS'
    )
    New-HostsBackup
    Save-HostsContent -Lines ([string[]]$default) -Encoding ([System.Text.UTF8Encoding]::new($false)) -Newline "`r`n" -FinalNewline $true
    Write-Host ''
    Write-Host ' HOSTS REDEFINIDO COM MALOVISKY IT TOOLS.' -ForegroundColor Green
    Write-Host ' Entradas personalizadas ativas: 0.' -ForegroundColor Green
    Write-Host (' Arquivo de backup: ' + $BackupPath) -ForegroundColor Green
}

function Restore-HostsBackup {
    Show-Header 'RESTAURAR HOSTS A PARTIR DE HOSTS.BKP'
    Assert-Administrator
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw ('Nao foi encontrado backup para restauracao: ' + $BackupPath)
    }
    Write-Host (' Origem:  ' + $BackupPath) -ForegroundColor Green
    Write-Host (' Destino: ' + $HostsPath) -ForegroundColor Green
    Write-Host ' O hosts atual sera guardado em arquivo separado antes da restauracao.' -ForegroundColor Green
    Write-Host ' O arquivo hosts.bkp nao sera sobrescrito nesta operacao.' -ForegroundColor Green
    Write-Host ''
    $confirm = Read-Host 'Digite RESTAURAR para continuar'
    if ($confirm -cne 'RESTAURAR') { Write-Host ' Operacao cancelada.' -ForegroundColor Green; return }

    $before = $null
    if (Test-Path -LiteralPath $HostsPath -PathType Leaf) {
        $before = "$HostsPath.antes-restauracao.$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').bkp"
        Copy-Item -LiteralPath $HostsPath -Destination $before -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $HostsPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash) {
            throw 'Copia de seguranca antes da restauracao falhou na verificacao.'
        }
    }
    try {
        # Grava os bytes do backup, sem alterar ou consumir o arquivo hosts.bkp.
        # Mantem as ACLs existentes do hosts ao sobrescrever somente o conteudo.
        $backupBytes = [IO.File]::ReadAllBytes($BackupPath)
        [IO.File]::WriteAllBytes($HostsPath, $backupBytes)
        if ((Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $HostsPath -Algorithm SHA256).Hash) {
            throw 'A verificacao SHA-256 do arquivo restaurado falhou.'
        }
    } catch {
        throw ('Falha ao restaurar/verificar hosts: ' + $_.Exception.Message +
               '. O backup hosts.bkp e a copia antes-restauracao foram preservados.')
    }
    Write-Host ' Backup restaurado com sucesso e validado por SHA-256.' -ForegroundColor Green
    if ($before) { Write-Host (' Hosts anterior a restauracao: ' + $before) -ForegroundColor Green }
    Clear-HostsDnsCache
}

Set-MatrixVisual
do {
    Show-Header 'GERENCIADOR DE HOSTS - V1.4.1'
    Write-Host (' Arquivo: ' + $HostsPath) -ForegroundColor DarkGreen
    Write-Host ''
    Write-Host ' [1] Consultar hosts atual (linhas numeradas e entradas ativas)' -ForegroundColor Green
    Write-Host ' [2] Remover uma linha especifica (com backup)' -ForegroundColor Green
    Write-Host ' [3] Redefinir hosts para o padrao do Windows (com backup)' -ForegroundColor Green
    Write-Host ' [4] Restaurar o ultimo hosts.bkp' -ForegroundColor Green
    Write-Host ' [0] Voltar ao menu principal / Sair' -ForegroundColor Green
    Write-Host ''
    $choice = (Read-Host 'Escolha uma opcao').Trim()
    try {
        switch ($choice) {
            '1' { Show-HostsContent; Pause-Malovisky }
            '2' { Remove-HostsLine; Pause-Malovisky }
            '3' { Reset-HostsToDefault; Pause-Malovisky }
            '4' { Restore-HostsBackup; Pause-Malovisky }
            '0' { }
            default { Write-Host ' Opcao invalida.' -ForegroundColor Green; Pause-Malovisky }
        }
    } catch {
        Write-Host ''
        Write-Host (' ERRO: ' + $_.Exception.Message) -ForegroundColor Green
        Pause-Malovisky
    }
} while ($choice -ne '0')
