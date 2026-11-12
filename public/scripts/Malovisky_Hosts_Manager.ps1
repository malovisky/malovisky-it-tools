#Requires -Version 5.1
# MALOVISKY IT TOOLS - Powered by Thomaz J
# Gerenciador de HOSTS - consulta, remocao, redefinicao, restauracao e bloqueio por fabricante.
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


# Catalogo incorporado, extraido e validado do arquivo enviado.
function Get-MaloviskyHostsCatalog {
    return @{
        'Adobe' = @'
127.0.0.1 m59b4msyph.adobe.io
127.0.0.1 ic.adobe.io
127.0.0.1 cc-api-data.adobe.io
127.0.0.1 7sj9n87sls.adobe.io
127.0.0.1 p7uxzbht8h.adobe.io
127.0.0.1 dxyeyf6ecy.adobe.io
127.0.0.1 1hzopx6nz7.adobe.io
127.0.0.1 0mo5a70cqa.adobe.io
127.0.0.1 1b9khekel6.adobe.io
127.0.0.1 23ynjitwt5.adobe.io
127.0.0.1 2ftem87osk.adobe.io
127.0.0.1 3ca52znvmj.adobe.io
127.0.0.1 3d3wqt96ht.adobe.io
127.0.0.1 4vzokhpsbs.adobe.io
127.0.0.1 5zgzzv92gn.adobe.io
127.0.0.1 69tu0xswvq.adobe.io
127.0.0.1 7g2gzgk9g1.adobe.io
127.0.0.1 7m31guub0q.adobe.io
127.0.0.1 8ncdzpmmrg.adobe.io
127.0.0.1 jc95y2v12r.adobe.io
127.0.0.1 ph0f2h2csf.adobe.io
127.0.0.1 b5kbg2ggog.adobe.io
127.0.0.1 guzg78logz.adobe.io
127.0.0.1 gw8gfjbs05.adobe.io
127.0.0.1 9ngulmtgqi.adobe.io
127.0.0.1 vcorzsld2a.adobe.io
127.0.0.1 r5hacgq5w6.adobe.io
127.0.0.1 vajcbj9qgq.adobe.io
127.0.0.1 lcs-robs.adobe.io
127.0.0.1 p13n.adobe.io
127.0.0.1 aoorovjtha.adobe.io
127.0.0.1 adobe.com
127.0.0.1 www.adobe.com
127.0.0.1 3dns-1.adobe.com
127.0.0.1 3dns-2.adobe.com
127.0.0.1 3dns-3.adobe.com
127.0.0.1 3dns-4.adobe.com
127.0.0.1 3dns.adobe.com
127.0.0.1 activate-sea.adobe.com
127.0.0.1 activate-sjc0.adobe.com
127.0.0.1 activate.adobe.com
127.0.0.1 activate.wip.adobe.com
127.0.0.1 activate.wip1.adobe.com
127.0.0.1 activate.wip2.adobe.com
127.0.0.1 activate.wip3.adobe.com
127.0.0.1 activate.wip4.adobe.com
127.0.0.1 adminconsole.adobe.com
127.0.0.1 adobe-dns-1.adobe.com
127.0.0.1 adobe-dns-2.adobe.com
127.0.0.1 adobe-dns-3.adobe.com
127.0.0.1 adobe-dns-4.adobe.com
127.0.0.1 adobe-dns.adobe.com
127.0.0.1 adobe.activate.com
127.0.0.1 adobeereg.com
127.0.0.1 api.account.adobe.com
127.0.0.1 assets.adobe.com
127.0.0.1 assets2.adobe.com
127.0.0.1 creative.adobe.com
127.0.0.1 ereg.adobe.com
127.0.0.1 ereg.wip.adobe.com
127.0.0.1 ereg.wip1.adobe.com
127.0.0.1 ereg.wip2.adobe.com
127.0.0.1 ereg.wip3.adobe.com
127.0.0.1 ereg.wip4.adobe.com
127.0.0.1 genuine.adobe.com
127.0.0.1 hl2rcv.adobe.com
127.0.0.1 hlrcv.stage.adobe.com
127.0.0.1 lcs-cops.adobe.io
127.0.0.1 lcs-entitlement.adobe.io
127.0.0.1 lcs-ulecs.adobe.io
127.0.0.1 licensing.adobe.co
127.0.0.1 lm.licenses.adobe.com
127.0.0.1 lmlicenses.wip4.adobe.com
127.0.0.1 na1r.services.adobe.com
127.0.0.1 na2m-pr.licenses.adobe.com
127.0.0.1 practivate.adobe
127.0.0.1 practivate.adobe.com
127.0.0.1 practivate.adobe.ipp
127.0.0.1 practivate.adobe.newoa
127.0.0.1 practivate.adobe.ntp
127.0.0.1 prod.acp.adobeoobe.com
127.0.0.1 prod.adobegenuine.com
127.0.0.1 spark.adobe.com
127.0.0.1 uds.licenses.adobe.com
127.0.0.1 wip.adobe.com
127.0.0.1 wip1.adobe.com
127.0.0.1 wip2.adobe.com
127.0.0.1 wip3.adobe.com
127.0.0.1 wip4.adobe.com
127.0.0.1 wwis-dubc1-vip60.adobe.com
127.0.0.1 www.adobeereg.com
127.0.0.1 www.wip.adobe.com
127.0.0.1 www.wip1.adobe.com
127.0.0.1 www.wip2.adobe.com
127.0.0.1 www.wip3.adobe.com
127.0.0.1 www.wip4.adobe.com
127.0.0.1 adobe-dns-01.adobe.com
127.0.0.1 adobe.demdex.net
127.0.0.1 adobe.tt.omtrdc.net
127.0.0.1 adobedc.demdex.net
127.0.0.1 adobeid-na1.services.adobe.com
127.0.0.1 assets.adobedtm.com
127.0.0.1 auth-cloudfront.prod.ims.adobejanus.com
127.0.0.1 auth.services.adobe.com
127.0.0.1 cai-splunk-proxy.adobe.io
127.0.0.1 cc-cdn.adobe.com
127.0.0.1 cc-cdn.adobe.com.edgekey.net
127.0.0.1 cclibraries-defaults-cdn.adobe.com
127.0.0.1 cclibraries-defaults-cdn.adobe.com.edgekey.net
127.0.0.1 cn-assets.adobedtm.com.edgekey.net
127.0.0.1 crlog-crcn.adobe.com
127.0.0.1 crs.cr.adobe.com
127.0.0.1 edgeproxy-irl1.cloud.adobe.io
127.0.0.1 ethos.ethos02-prod-irl1.ethos.adobe.net
127.0.0.1 geo2.adobe.com
127.0.0.1 pv2bqhsp36w.prod.cloud.adobe.io
127.0.0.1 services.prod.ims.adobejanus.com
127.0.0.1 ssl-delivery.adobe.com.edgekey.net
127.0.0.1 sstats.adobe.com
127.0.0.1 stls.adobe.com-cn.edgesuite.net
127.0.0.1 stls.adobe.com-cn.edgesuite.net.globalredir.akadns.net
127.0.0.1 use-stls.adobe.com.edgesuite.net
127.0.0.1 fqaq3pq1o9.adobe.io
127.0.0.1 dyzt55url8.adobe.io
127.0.0.1 lre1kgz2u4.adobe.io
127.0.0.1 p0bjuoe16a.adobe.io
127.0.0.1 hbrcv.adobe.com
127.0.0.1 p7uxzbnt8h.adobe.io
127.0.0.1 cctypekit.adobe.io
127.0.0.1 pojvrj7ho5.adobe.io
127.0.0.1 adobe.io
127.0.0.1 5amul9liob.adobestats.io
127.0.0.1 36ai1uk1z7.adobestats.io
127.0.0.1 ij0gdyrfka.adobe.io
127.0.0.1 3dns-5.adobe.com
127.0.0.1 activate-sea.adobe.de
127.0.0.1 activate-sjc0.adobe.de
127.0.0.1 activate.adobe.de
127.0.0.1 activate.wip3.adobe.de
127.0.0.1 adobe-dns-2.adobe.de
127.0.0.1 adobe-dns-3.adobe.de
127.0.0.1 adobe-dns.adobe.de
127.0.0.1 cmdls.adobe.com
127.0.0.1 ereg.adobe.de
127.0.0.1 hl2rcv.adobe.de
127.0.0.1 ims-na1-prprod.adobelogin.com
127.0.0.1 na2m-stg2.licenses.adobe.com
127.0.0.1 na4r.services.adobe.com
127.0.0.1 practivate.adobe.de
127.0.0.1 prod-rel-ffc-ccm.oobesaas.adobe.com
127.0.0.1 s-2.adobe.com
127.0.0.1 s-3.adobe.com
127.0.0.1 wwis-dubc1-vip100.adobe.com
127.0.0.1 wwis-dubc1-vip101.adobe.com
127.0.0.1 wwis-dubc1-vip102.adobe.com
127.0.0.1 wwis-dubc1-vip103.adobe.com
127.0.0.1 wwis-dubc1-vip104.adobe.com
127.0.0.1 wwis-dubc1-vip105.adobe.com
127.0.0.1 wwis-dubc1-vip106.adobe.com
127.0.0.1 wwis-dubc1-vip107.adobe.com
127.0.0.1 wwis-dubc1-vip108.adobe.com
127.0.0.1 wwis-dubc1-vip109.adobe.com
127.0.0.1 wwis-dubc1-vip110.adobe.com
127.0.0.1 wwis-dubc1-vip111.adobe.com
127.0.0.1 wwis-dubc1-vip112.adobe.com
127.0.0.1 wwis-dubc1-vip113.adobe.com
127.0.0.1 wwis-dubc1-vip114.adobe.com
127.0.0.1 wwis-dubc1-vip115.adobe.com
127.0.0.1 wwis-dubc1-vip116.adobe.com
127.0.0.1 wwis-dubc1-vip117.adobe.com
127.0.0.1 wwis-dubc1-vip118.adobe.com
127.0.0.1 wwis-dubc1-vip119.adobe.com
127.0.0.1 wwis-dubc1-vip120.adobe.com
127.0.0.1 wwis-dubc1-vip121.adobe.com
127.0.0.1 wwis-dubc1-vip122.adobe.com
127.0.0.1 wwis-dubc1-vip123.adobe.com
127.0.0.1 wwis-dubc1-vip124.adobe.com
127.0.0.1 wwis-dubc1-vip125.adobe.com
127.0.0.1 wwis-dubc1-vip30.adobe.com
127.0.0.1 wwis-dubc1-vip31.adobe.com
127.0.0.1 wwis-dubc1-vip32.adobe.com
127.0.0.1 wwis-dubc1-vip33.adobe.com
127.0.0.1 wwis-dubc1-vip34.adobe.com
127.0.0.1 wwis-dubc1-vip35.adobe.com
127.0.0.1 wwis-dubc1-vip36.adobe.com
127.0.0.1 wwis-dubc1-vip37.adobe.com
127.0.0.1 wwis-dubc1-vip38.adobe.com
127.0.0.1 wwis-dubc1-vip39.adobe.com
127.0.0.1 wwis-dubc1-vip40.adobe.com
127.0.0.1 wwis-dubc1-vip41.adobe.com
127.0.0.1 wwis-dubc1-vip42.adobe.com
127.0.0.1 wwis-dubc1-vip43.adobe.com
127.0.0.1 wwis-dubc1-vip44.adobe.com
127.0.0.1 wwis-dubc1-vip45.adobe.com
127.0.0.1 wwis-dubc1-vip46.adobe.com
127.0.0.1 wwis-dubc1-vip47.adobe.com
127.0.0.1 wwis-dubc1-vip48.adobe.com
127.0.0.1 wwis-dubc1-vip49.adobe.com
127.0.0.1 wwis-dubc1-vip50.adobe.com
127.0.0.1 wwis-dubc1-vip51.adobe.com
127.0.0.1 wwis-dubc1-vip52.adobe.com
127.0.0.1 wwis-dubc1-vip53.adobe.com
127.0.0.1 wwis-dubc1-vip54.adobe.com
127.0.0.1 wwis-dubc1-vip55.adobe.com
127.0.0.1 wwis-dubc1-vip56.adobe.com
127.0.0.1 wwis-dubc1-vip57.adobe.com
127.0.0.1 wwis-dubc1-vip58.adobe.com
127.0.0.1 wwis-dubc1-vip59.adobe.com
127.0.0.1 wwis-dubc1-vip60.adobe.de
127.0.0.1 wwis-dubc1-vip61.adobe.com
127.0.0.1 wwis-dubc1-vip62.adobe.com
127.0.0.1 wwis-dubc1-vip63.adobe.com
127.0.0.1 wwis-dubc1-vip64.adobe.com
127.0.0.1 wwis-dubc1-vip65.adobe.com
127.0.0.1 wwis-dubc1-vip66.adobe.com
127.0.0.1 wwis-dubc1-vip67.adobe.com
127.0.0.1 wwis-dubc1-vip68.adobe.com
127.0.0.1 wwis-dubc1-vip69.adobe.com
127.0.0.1 wwis-dubc1-vip70.adobe.com
127.0.0.1 wwis-dubc1-vip71.adobe.com
127.0.0.1 wwis-dubc1-vip72.adobe.com
127.0.0.1 wwis-dubc1-vip73.adobe.com
127.0.0.1 wwis-dubc1-vip74.adobe.com
127.0.0.1 wwis-dubc1-vip75.adobe.com
127.0.0.1 wwis-dubc1-vip76.adobe.com
127.0.0.1 wwis-dubc1-vip77.adobe.com
127.0.0.1 wwis-dubc1-vip78.adobe.com
127.0.0.1 wwis-dubc1-vip79.adobe.com
127.0.0.1 wwis-dubc1-vip80.adobe.com
127.0.0.1 wwis-dubc1-vip81.adobe.com
127.0.0.1 wwis-dubc1-vip82.adobe.com
127.0.0.1 wwis-dubc1-vip83.adobe.com
127.0.0.1 wwis-dubc1-vip84.adobe.com
127.0.0.1 wwis-dubc1-vip85.adobe.com
127.0.0.1 wwis-dubc1-vip86.adobe.com
127.0.0.1 wwis-dubc1-vip87.adobe.com
127.0.0.1 wwis-dubc1-vip88.adobe.com
127.0.0.1 wwis-dubc1-vip89.adobe.com
127.0.0.1 wwis-dubc1-vip90.adobe.com
127.0.0.1 wwis-dubc1-vip91.adobe.com
127.0.0.1 wwis-dubc1-vip92.adobe.com
127.0.0.1 wwis-dubc1-vip93.adobe.com
127.0.0.1 wwis-dubc1-vip94.adobe.com
127.0.0.1 wwis-dubc1-vip95.adobe.com
127.0.0.1 wwis-dubc1-vip96.adobe.com
127.0.0.1 wwis-dubc1-vip97.adobe.com
127.0.0.1 wwis-dubc1-vip98.adobe.com
127.0.0.1 wwis-dubc1-vip99.adobe.com
'@
        'Autodesk' = @'
127.0.0.1 api.genuine-software.autodesk.com
127.0.0.1 ase.autodesk.com
127.0.0.1 genuine-software.autodesk.com
127.0.0.1 genuine-software1.autodesk.com
127.0.0.1 genuine-software2.autodesk.com
'@
        'Corel' = @'
127.0.0.1 corel.com
127.0.0.1 www.corel.com
127.0.0.1 apps.corel.com
127.0.0.1 mc.corel.com
127.0.0.1 ipm.corel.com
127.0.0.1 origin-mc.corel.com
127.0.0.1 license.corel.com
'@
    }
}

function Invoke-MaloviskyHostsBlocking {
    param([Parameter(Mandatory=$true)][string[]]$Vendors)
    Assert-Administrator
    $catalog = Get-MaloviskyHostsCatalog
    $document = Get-HostsDocument
    $originalHash = $null
    if (Test-Path -LiteralPath $HostsPath -PathType Leaf) {
        $originalHash = (Get-FileHash -LiteralPath $HostsPath -Algorithm SHA256).Hash
    }

    $known = @{}
    foreach ($line in $document.Lines) {
        $uncommented = ($line -split '#', 2)[0].Trim()
        if (-not $uncommented) { continue }
        $tokens = @($uncommented -split '\s+')
        if ($tokens.Length -lt 2) { continue }
        if ($tokens[0] -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$|^[0-9a-fA-F:]+
    Show-Header 'GERENCIADOR DE HOSTS - V1.5.0'
    Write-Host (' Arquivo: ' + $HostsPath) -ForegroundColor DarkGreen
    Write-Host ''
    Write-Host ' [1] Consultar hosts atual (linhas numeradas e entradas ativas)' -ForegroundColor Green
    Write-Host ' [2] Remover uma linha especifica (com backup)' -ForegroundColor Green
    Write-Host ' [3] Redefinir hosts para o padrao do Windows (com backup)' -ForegroundColor Green
    Write-Host ' [4] Restaurar o ultimo hosts.bkp' -ForegroundColor Green
    Write-Host ' [5] Bloquear fabricantes no HOSTS (Adobe, Autodesk, Corel)' -ForegroundColor Green
    Write-Host ' [0] Voltar ao menu principal / Sair' -ForegroundColor Green
    Write-Host ''
    $choice = (Read-Host 'Escolha uma opcao').Trim()
    try {
        switch ($choice) {
            '1' { Show-HostsContent; Pause-Malovisky }
            '2' { Remove-HostsLine; Pause-Malovisky }
            '3' { Reset-HostsToDefault; Pause-Malovisky }
            '4' { Restore-HostsBackup; Pause-Malovisky }
            '5' { Show-MaloviskyVendorMenu }
            '0' { }
            default { Write-Host ' Opcao invalida.' -ForegroundColor Green; Pause-Malovisky }
        }
    } catch {
        Write-Host ''
        Write-Host (' ERRO: ' + $_.Exception.Message) -ForegroundColor Green
        Pause-Malovisky
    }
} while ($choice -ne '0')
) { continue }
        for ($j = 1; $j -lt $tokens.Length; $j++) {
            $name = $tokens[$j].ToLowerInvariant()
            if (-not $known.ContainsKey($name)) { $known[$name] = $tokens[0] }
        }
    }

    $planned = [System.Collections.Generic.List[string]]::new()
    $newCount = 0
    $existingCount = 0
    $conflictCount = 0
    $details = [ordered]@{}
    foreach ($vendor in $Vendors) {
        if (-not $catalog.ContainsKey($vendor)) { throw 'Fabricante desconhecido.' }
        $batch = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in ($catalog[$vendor].Trim() -split '\r?\n')) {
            $pair = @($entry.Trim() -split '\s+')
            if ($pair.Length -ne 2) { continue }
            $ip = $pair[0]; $hostname = $pair[1]
            $key = $hostname.ToLowerInvariant()
            if ($known.ContainsKey($key)) {
                $existingCount++
                if ($known[$key] -notin @('127.0.0.1','0.0.0.0')) { $conflictCount++ }
                continue
            }
            $batch.Add($ip + ' ' + $hostname)
            $known[$key] = $ip
            $newCount++
        }
        $details[$vendor] = $batch.Count
        if ($batch.Count -gt 0) {
            $planned.Add('')
            $planned.Add('# MALOVISKY IT TOOLS - ' + $vendor.ToUpperInvariant())
            foreach ($line in $batch) { $planned.Add($line) }
        }
    }

    Show-Header 'BLOQUEIO SELETIVO NO ARQUIVO HOSTS'
    Write-Host (' Fabricantes selecionados: ' + ($Vendors -join ', ')) -ForegroundColor Green
    foreach ($key in $details.Keys) {
        Write-Host (' {0}: {1} novas entradas' -f $key, $details[$key]) -ForegroundColor Green
    }
    Write-Host (' Total de entradas novas: ' + $newCount) -ForegroundColor Green
    Write-Host (' Ja existentes, sem duplicar: ' + $existingCount) -ForegroundColor Green
    if ($conflictCount -gt 0) {
        Write-Host (' ATENCAO: {0} hosts apontam para IPs diferentes; nao serao alterados.' -f $conflictCount) -ForegroundColor Green
    }
    Write-Host ''
    Write-Host ' AVISO: pode impedir autenticacao, atualizacoes e validacao de licencas.' -ForegroundColor Green
    Write-Host ' As entradas anteriores serao preservadas, salvo reposicionamento do marcador.' -ForegroundColor Green
    Write-Host ''
    if ($newCount -eq 0) {
        Write-Host ' Nenhuma linha nova para acrescentar.' -ForegroundColor Green
        return
    }
    if ((Read-Host 'Digite BLOQUEAR para confirmar') -cne 'BLOQUEAR') {
        Write-Host ' Cancelado.' -ForegroundColor Green
        return
    }
    if ($originalHash) {
        if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $HostsPath -Algorithm SHA256).Hash -ne $originalHash) {
            throw 'O hosts mudou durante a operacao. Consulte e tente novamente.'
        }
    } elseif (Test-Path -LiteralPath $HostsPath -PathType Leaf) {
        throw 'O hosts foi criado por outro processo. Tente novamente.'
    }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $document.Lines) {
        if ($line.Trim() -cne '#BLOQUEIO REALIZADO COM MALOVISKY IT TOOLS') { $out.Add($line) }
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') {
        $out.RemoveAt($out.Count - 1)
    }
    foreach ($line in $planned) { $out.Add($line) }
    $out.Add('#BLOQUEIO REALIZADO COM MALOVISKY IT TOOLS')
    New-HostsBackup
    Save-HostsContent -Lines ([string[]]$out.ToArray()) -Encoding $document.Encoding -Newline $document.Newline -FinalNewline $true
    Write-Host (' Entradas inseridas: ' + $newCount + ' | Ignoradas por ja existir: ' + $existingCount) -ForegroundColor Green
    Write-Host (' Backup: ' + $BackupPath) -ForegroundColor Green
}

function Show-MaloviskyVendorMenu {
    do {
        Show-Header 'BLOQUEAR FABRICANTES NO HOSTS'
        Write-Host ' [1] ADOBE' -ForegroundColor Green
        Write-Host ' [2] AUTODESK' -ForegroundColor Green
        Write-Host ' [3] COREL' -ForegroundColor Green
        Write-Host ' [4] TODOS' -ForegroundColor Green
        Write-Host ' [0] Voltar' -ForegroundColor Green
        Write-Host ''
        Write-Host ' Selecao multipla permitida: ex. 2,3' -ForegroundColor DarkGreen
        $choice = (Read-Host 'Escolha').Trim()
        if ($choice -eq '0') { break }
        if ($choice -notmatch '^[1-4](\s*,\s*[1-4])*
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
) {
            Write-Host ' Escolha invalida. Use 1, 2, 3, 4 ou 2,3.' -ForegroundColor Green
            Pause-Malovisky
            continue
        }
        $selected = @($choice -split ',' | ForEach-Object { $_.Trim() } | Select-Object -Unique)
        if ($selected -contains '4' -and $selected.Count -gt 1) {
            Write-Host ' Para todos, escolha somente 4.' -ForegroundColor Green
            Pause-Malovisky
            continue
        }
        $vendors = [System.Collections.Generic.List[string]]::new()
        if ($selected -contains '4') {
            foreach ($v in @('Adobe','Autodesk','Corel')) { $vendors.Add($v) }
        } else {
            foreach ($c in $selected) {
                switch ($c) {
                    '1' { $vendors.Add('Adobe') }
                    '2' { $vendors.Add('Autodesk') }
                    '3' { $vendors.Add('Corel') }
                }
            }
        }
        try { Invoke-MaloviskyHostsBlocking -Vendors $vendors.ToArray() }
        catch { Write-Host (' ERRO: ' + $_.Exception.Message) -ForegroundColor Green }
        Pause-Malovisky
    } while ($true)
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
