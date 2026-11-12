<#
=============================================================================
 auditar-vps.ps1  ·  Panel de auditoria de un VPS propio (desde Windows)

 USO:
   .\auditar-vps.ps1 -Objetivo <IP_O_DOMINIO_TUYO>
   .\auditar-vps.ps1 -Objetivo <IP> -Completo     (revisa los 65535 puertos)

 Ej:  .\auditar-vps.ps1 -Objetivo 190.183.229.172 -Completo

 Necesita nmap para Windows:  winget install Insecure.Nmap

 Solo sobre servidores TUYOS o con autorizacion. Escanear sistemas de
 terceros sin permiso es ilegal.
=============================================================================
#>
param(
  [Parameter(Mandatory = $true)] [string]$Objetivo,
  [switch]$Completo
)

$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ESC = [char]27
function C { param($hex)
  $r=[convert]::ToInt32($hex.Substring(0,2),16); $g=[convert]::ToInt32($hex.Substring(2,2),16); $b=[convert]::ToInt32($hex.Substring(4,2),16)
  "$ESC[38;2;$r;$g;${b}m" }
$R="$ESC[0m"; $B="$ESC[1m"
$verde=C "39ff78"; $cyan=C "2ee6f0"; $gris=C "6f7b74"; $rojo=C "ff5b5b"; $amar=C "ffc23b"; $blanco=C "e8fff0"

$W = 60
function Caja-Top   { param($t) $resto=$W-4-$t.Length; "$cyan╭─ $B$blanco$t$R $cyan" + ("─"*$resto) + "╮$R" }
function Caja-Linea { param($izq,$der="")
  $pi=($izq -replace "$ESC\[[0-9;]*m",""); $pd=($der -replace "$ESC\[[0-9;]*m","")
  $esp=$W-3-$pi.Length-$pd.Length; if($esp -lt 1){$esp=1}
  "$cyan│$R $izq" + (" "*$esp) + "$der $cyan│$R" }
function Caja-Bot   { "$cyan╰" + ("─"*($W-2)) + "╯$R" }

Clear-Host
Write-Host ""
Write-Host "$verde$B   ██       ██████  ██   ██ ██ $R   $gris testing-loki · auditor$R"
Write-Host "$verde$B   ██      ██    ██ █████   ██ $R"
Write-Host "$verde$B   ███████  ██████  ██   ██ ██ $R"
Write-Host ""

Write-Host "$amar  ⚠  Este servidor es TUYO o te autorizaron a escanearlo?$R"
$ok = Read-Host "$blanco     escribi 'si' para continuar$R"
if ($ok -ne "si") { Write-Host "$rojo  ✖ Cancelado. Solo servidores propios.$R`n"; exit 1 }

if (-not (Get-Command nmap -ErrorAction SilentlyContinue)) {
  Write-Host "$amar  Falta nmap:  $blanco winget install Insecure.Nmap$R"; exit 1
}

# --- Quien es el dueno de la IP (Cloudflare? proveedor?) ---------------------
Write-Host "$gris  Consultando de quien es la IP...$R"
$org="-"; $pais="-"; $ciudad="-"; $cf=$false
try {
  $ip = [System.Net.Dns]::GetHostAddresses($Objetivo) | Where-Object {$_.AddressFamily -eq 'InterNetwork'} | Select-Object -First 1
  $info = Invoke-RestMethod -Uri "https://ipinfo.io/$($ip.IPAddressToString)/json" -TimeoutSec 8
  if($info.org){$org=$info.org}; if($info.country){$pais=$info.country}; if($info.city){$ciudad=$info.city}
  if($org -match 'cloudflare'){$cf=$true}
} catch {}

# --- Escaneo de puertos ------------------------------------------------------
if ($Completo) {
  Write-Host "$gris  Escaneo COMPLETO (65535 puertos). Puede tardar 5-15 min...$R"
  $args = @('-sV','-T4','-Pn','-p-',$Objetivo)
} else {
  Write-Host "$gris  Escaneo rapido (1000 puertos comunes). 1-2 min...$R"
  $args = @('-sV','-T4','-Pn',$Objetivo)
}
$hora = Get-Date -Format "HH:mm"
$vivo = Test-Connection -ComputerName $Objetivo -Count 1 -Quiet -ErrorAction SilentlyContinue
$salida = & nmap @args 2>$null
$texto  = $salida -join "`n"

$puertos=@()
$salida | Select-String -Pattern '^\d+/(tcp|udp)\s+open' | ForEach-Object {
  $c=($_ -replace '\s+',' ').Trim().Split(' ')
  $puertos += [pscustomobject]@{ Puerto=$c[0]; Serv=$c[2]; Vers=if($c.Length -gt 3){($c[3..($c.Length-1)] -join ' ')}else{""} }
}

Clear-Host
Write-Host ""
Write-Host (Caja-Top "AUDITORIA DE VPS")
Write-Host (Caja-Linea "$blanco$Objetivo$R" "$gris$hora$R")
Write-Host (Caja-Linea ("$gris" + "Estado:$R " + $(if($vivo){"$verde● responde$R"}else{"$amar○ sin ping$R"})) ("$gris $(if($Completo){'escaneo completo'}else{'escaneo rapido'})$R"))
Write-Host (Caja-Bot)
Write-Host ""

# Dueno de la IP
Write-Host (Caja-Top "DUENO DE LA IP")
Write-Host (Caja-Linea "$gris Proveedor:$R $blanco$org$R")
Write-Host (Caja-Linea "$gris Lugar:$R $blanco$ciudad, $pais$R")
if($cf){ Write-Host (Caja-Linea "$amar ⚑ Esta IP es de CLOUDFLARE$R") }
else   { Write-Host (Caja-Linea "$verde ● IP directa del servidor (no Cloudflare)$R") }
Write-Host (Caja-Bot)
Write-Host ""

# Puertos
Write-Host (Caja-Top "PUERTOS ABIERTOS · $($puertos.Count)")
if($puertos.Count -eq 0){ Write-Host (Caja-Linea "$gris Ninguno visible desde afuera.$R") }
else { foreach($x in $puertos){
  $vv=$x.Vers; if($vv.Length -gt 24){$vv=$vv.Substring(0,24)}
  Write-Host (Caja-Linea "$verde● $R$blanco$($x.Puerto.PadRight(9))$R$cyan$($x.Serv.PadRight(11))$R" "$gris$vv$R")
}}
Write-Host (Caja-Bot)
Write-Host ""

# Avisos
Write-Host (Caja-Top "AVISOS DE SEGURIDAD")
$av=0
function Chk { param($p) return ($texto -match $p) }
if(Chk '23/tcp\s+open')  {Write-Host (Caja-Linea "$rojo✖ Telnet (23) abierto: inseguro$R");$av++}
if(Chk '21/tcp\s+open')  {Write-Host (Caja-Linea "$amar! FTP (21): usa SFTP$R");$av++}
if(Chk '3306/tcp\s+open'){Write-Host (Caja-Linea "$rojo✖ MySQL (3306) expuesto a internet$R");$av++}
if(Chk '6379/tcp\s+open'){Write-Host (Caja-Linea "$rojo✖ Redis (6379) expuesto: peligroso$R");$av++}
if(Chk '5432/tcp\s+open'){Write-Host (Caja-Linea "$amar! PostgreSQL (5432) expuesto$R");$av++}
if(Chk '22/tcp\s+open')  {Write-Host (Caja-Linea "$gris i SSH (22) en puerto por defecto$R")}
if($av -eq 0){ Write-Host (Caja-Linea "$verde✔ Sin alertas graves.$R") }
Write-Host (Caja-Bot)
Write-Host ""
Write-Host "$gris  Hecho · $hora · solo servidores propios$R"
Write-Host ""
