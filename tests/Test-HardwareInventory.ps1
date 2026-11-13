#Requires -Version 5.1
# Testes sem acessar ou alterar o hardware do equipamento.
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\public\scripts\Malovisky_Hardware_Inventory.ps1'
if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw 'Modulo de hardware nao encontrado.' }
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($module, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    throw ('Erro de sintaxe: ' + (($errors | ForEach-Object Message) -join '; '))
}
$names = @('Limpar-Valor','Normalizar-Id','Tipo-Memoria','Formato-Memoria','Comparar-DiscoFisico','Tipo-Disco')
foreach ($name in $names) {
    $matching = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($matching.Count -ne 1) { throw ('Funcao ausente ou repetida: ' + $name) }
    Invoke-Expression $matching[0].Extent.Text
}
function Assert-Equals($actual, $expected, [string]$name) {
    if ($actual -cne $expected) { throw ("$name falhou: obtido '$actual', esperado '$expected'") }
}
Assert-Equals (Tipo-Memoria ([pscustomobject]@{SMBIOSMemoryType=26;MemoryType=0})) 'DDR4' 'DDR4'
Assert-Equals (Tipo-Memoria ([pscustomobject]@{SMBIOSMemoryType=34;MemoryType=0})) 'DDR5' 'DDR5'
Assert-Equals (Tipo-Memoria ([pscustomobject]@{SMBIOSMemoryType=0;MemoryType=0})) 'Nao identificado' 'desconhecida'
Assert-Equals (Formato-Memoria 12) 'SODIMM' 'SODIMM'
$wmi=[pscustomobject]@{ SerialNumber='AAA123'; Model='SAMSUNG SSD 980'; Size=500000000000L; InterfaceType='SCSI'; PNPDeviceID='PCI\NVME' }
$storage=[pscustomobject]@{ SerialNumber='AAA123'; FriendlyName='SAMSUNG SSD 980'; Size=500000000000L; MediaType='SSD'; BusType='NVMe' }
$found = Comparar-DiscoFisico -DiscoWmi $wmi -DiscosStorage @($storage)
Assert-Equals $found.FriendlyName 'SAMSUNG SSD 980' 'disco combinado'
Assert-Equals (Tipo-Disco -DiscoWmi $wmi -DiscoStorage $found) 'SSD' 'tipo SSD'
Assert-Equals (Tipo-Disco -DiscoWmi $wmi -DiscoStorage $null) 'SSD (NVMe)' 'NVMe fallback'
Write-Host 'TESTES OK - parser, RAM, identificacao e tipo de disco' -ForegroundColor Green
