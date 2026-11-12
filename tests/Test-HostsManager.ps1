#Requires -Version 5.1
# Testa a funcao real Save-HostsContent, sem modificar o hosts do Windows.
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\public\scripts\Malovisky_Hosts_Manager.ps1'
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
    throw ('Modulo nao encontrado: ' + $module)
}
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($module, [ref]$tokens, [ref]$errors)
if (@($errors).Count -gt 0) {
    throw ('Erros de sintaxe: ' + (($errors | ForEach-Object Message) -join '; '))
}
$fn = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Save-HostsContent'
}, $true))
if ($fn.Count -ne 1) { throw 'Funcao Save-HostsContent nao encontrada exatamente uma vez.' }

$working = Join-Path $env:TEMP ('MaloviskyHosts-Test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $working -Force)
try {
    $HostsPath = Join-Path $working 'hosts'
    $BackupPath = "$HostsPath.bkp"
    function Assert-Administrator { }
    function Clear-HostsDnsCache { }
    Invoke-Expression $fn[0].Extent.Text

    $enc = New-Object System.Text.UTF8Encoding($false)
    $crlf = ([string][char]13) + ([string][char]10)
    $lines = [string[]]@('# Inicio', '', '127.0.0.1 example.local', '', '# Fim')
    Save-HostsContent -Lines $lines -Encoding $enc -Newline $crlf -FinalNewline $true
    $expected = [string]::Join($crlf, $lines) + $crlf
    $actual = [IO.File]::ReadAllText($HostsPath, $enc)
    if ($actual -cne $expected) { throw 'Linhas vazias nao foram mantidas.' }

    Copy-Item -LiteralPath $HostsPath -Destination $BackupPath
    Save-HostsContent -Lines ([string[]]@()) -Encoding $enc -Newline $crlf -FinalNewline $true
    $actual = [IO.File]::ReadAllText($HostsPath, $enc)
    if ($actual.Length -ne 0) { throw 'Colecao vazia nao gerou arquivo vazio.' }

    Write-Host 'TESTES OK - PARSER, LINHAS EM BRANCO E COLECAO VAZIA' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $working -Recurse -Force -ErrorAction SilentlyContinue
}
