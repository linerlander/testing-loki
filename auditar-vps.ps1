<#
=============================================================================
 auditar-vps.ps1  ·  Panel de auditoria de un VPS propio (desde Windows)
 Q"e puertos tiene abiertos, qu, servicios corren y avisos de seguridad.

 USO:   .\auditar-vps.ps1 -Objetivo <IP_O_DOMINIO_TUYO>
 Ej:    .\auditar-vps.ps1 -Objetivo 190.183.229.172

 Necesita nmap para Windows:  winget install Insecure.Nmap

 Solo sobre servidores TUYOS o con autorizacion. Escanear sistemas de
 terceros sin permiso es ilegal.
=============================================================================
#>
param(
  [Parameter(Mandatory = $true)] [string]$Objetivo
)

$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ESC = [char]27
function C { param($hex,[switch]$bg)
  $r=[convert]::ToInt32($hex.Substring(0,2),16); $g=[convert]::ToInt32($hex.Substring(2,2),16); $b=[convert]::ToInt32($hex.Substring(4,2),16)
  if($bg){"$ESC[48;2;$r;$g;${b}m"}else{"$ESC[38;2;$r;$g;${b}m"} }
$R="$ESC[0m"; $B="$ESC[1m"
$verde=C "39ff78"; $cyan=C "2ee6f0"; $lila=C "b98cff"; $gris=C "6f7b74"; $rojo=C "ff5b5b"; $amar=C "ffc23b"; $blanco=C "e8fff0"

$W = 58
function Caja-Top    { param($t) $tl=$t.Length; $resto=$W-4-$tl; "$cyan╭─ $B$blanco$t$R $cyan" + ("─"*$resto) + "╮$R" }
function Caja-Linea  { param($izq,$der="")
  $plano = ($izq -replace "$ESC\[[0-9;]*m","")
  $pd    = ($der -replace "$ESC\[[0-9;]*m","")
  $esp   = $W-3-$plano.Length-$pd.Length; if($esp -lt 1){$esp=1}
  "$cyan│$R $izq" + (" "*$esp) + "$der $cyan│$R" }
function Caja-Sep    { "$cyan├" + ("─"*($W-2)) + "┤$R" }
function Caja-Bot    { "$cyan╰" + ("─"*($W-2)) + "╯$R" }
function Barra { param([double]$pct,$color)
  $n=[math]::Round($pct/10); if($n -gt 10){$n=10}; if($n -lt 0){$n=0}
  "$color" + ("▰"*$n) + "$gris" + ("▱"*(10-$n)) + "$R" }

Clear-Host
Write-Host ""
Write-Host "$verde$B   ██       ██████  ██   ██ ██ $R"
Write-Host "$verde$B   ██      ██    ██ ██  ██  ██ $R   $gris testing-loki · auditor$R"
Write-Host "$verde$B   ██      ██    ██ █████   ██ $R"
Write-Host "$verde$B   ██      ██    ██ ██  ██  ██ $R"
Write-Host "$verde$B   ███████  ██████  ██   ██ ██ $R"
Write-Host ""

# Candado de autorizacion
Write-Host "$amar  ⚠  Este servidor es TUYO o te autorizaron a escanearlo?$R"
$ok = Read-Host "$blanco     escribi 'si' para continuar$R"
if ($ok -ne "si") { Write-Host "$rojo  ✖ Cancelado. Solo servidores propios.$R`n"; exit 1 }

$nmap = Get-Command nmap -ErrorAction SilentlyContinue
if (-not $nmap) {
  Write-Host "$amar  Falta nmap. Instalalo:  $blanco winget install Insecure.Nmap$R"; exit 1
}

Write-Host ""
Write-Host "$gris  Escaneando $Objetivo ... (1-2 min)$R"
$hora  = Get-Date -Format "HH:mm"
$vivo  = Test-Connection -ComputerName $Objetivo -Count 1 -Quiet -ErrorAction SilentlyContinue
$salida = & nmap -sV -T4 -Pn $Objetivo 2>$null
$texto  = $salida -join "`n"

# Puertos abiertos
$puertos = @()
$salida | Select-String -Pattern '^\d+/(tcp|udp)\s+open' | ForEach-Object {
  $campos = ($_ -replace '\s+', ' ').Trim().Split(' ')
  $puertos += [pscustomobject]@{
    Puerto = $campos[0]
    Serv   = $campos[2]
    Vers   = if($campos.Length -gt 3){($campos[3..($campos.Length-1)] -join ' ')}else{""}
  }
}

# Recursos (lo que se puede ver desde afuera)
$lat = "-"
$p = Test-Connection -ComputerName $Objetivo -Count 2 -ErrorAction SilentlyContinue
if ($p) { $lat = [math]::Round(($p | Measure-Object -Property ResponseTime -Average).Average) }

Clear-Host
Write-Host ""
Write-Host (Caja-Top "AUDITORIA DE VPS")
Write-Host (Caja-Linea "$blanco$Objetivo$R" "$gris$hora$R")
Write-Host (Caja-Linea ("$gris" + "Estado:$R " + $(if($vivo){"$verde● responde$R"}else{"$amar○ sin ping (normal)$R"})) ("$gris lat $R$blanco$lat ms$R"))
Write-Host (Caja-Bot)
Write-Host ""

# Puertos
Write-Host (Caja-Top "PUERTOS ABIERTOS · $($puertos.Count)")
if ($puertos.Count -eq 0) {
  Write-Host (Caja-Linea "$gris Ninguno visible desde afuera.$R")
} else {
  foreach ($x in $puertos) {
    $pp = $x.Puerto.PadRight(9)
    $ss = $x.Serv.PadRight(12)
    $vv = $x.Vers; if($vv.Length -gt 22){$vv=$vv.Substring(0,22)}
    Write-Host (Caja-Linea "$verde● $R$blanco$pp$R$cyan$ss$R" "$gris$vv$R")
  }
}
Write-Host (Caja-Bot)
Write-Host ""

# Avisos
Write-Host (Caja-Top "AVISOS DE SEGURIDAD")
$avisos = 0
function Chk { param($p) return ($texto -match $p) }
if (Chk '23/tcp\s+open')   { Write-Host (Caja-Linea "$rojo✖ Telnet (23) abierto: inseguro$R"); $avisos++ }
if (Chk '21/tcp\s+open')   { Write-Host (Caja-Linea "$amar! FTP (21): usa SFTP$R"); $avisos++ }
if (Chk '3306/tcp\s+open') { Write-Host (Caja-Linea "$rojo✖ MySQL (3306) expuesto a internet$R"); $avisos++ }
if (Chk '6379/tcp\s+open') { Write-Host (Caja-Linea "$rojo✖ Redis (6379) expuesto: peligroso$R"); $avisos++ }
if (Chk '5432/tcp\s+open') { Write-Host (Caja-Linea "$amar! PostgreSQL (5432) expuesto$R"); $avisos++ }
if (Chk '22/tcp\s+open')   { Write-Host (Caja-Linea "$gris i SSH (22) en puerto por defecto$R") }
if ($avisos -eq 0) { Write-Host (Caja-Linea "$verde✔ Sin alertas graves.$R") }
Write-Host (Caja-Bot)
Write-Host ""
Write-Host "$gris  Hecho · $hora · solo servidores propios$R"
Write-Host ""
