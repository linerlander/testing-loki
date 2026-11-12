param(
  [Parameter(Mandatory = $true)] [string]$Objetivo,
  [switch]$Completo
)

. "$PSScriptRoot\lib-panel.ps1"

Banner "auditor de servidores"
Write-Host "$amar  ⚠  Este servidor es TUYO o te autorizaron a escanearlo?$RST"
$ok = Read-Host "$blanco     escribi 'si' para continuar$RST"
if ($ok -ne "si") { Write-Host "$rojo  ✖ Cancelado. Solo servidores propios.$RST`n"; exit 1 }

if (-not (Get-Command nmap -ErrorAction SilentlyContinue)) {
  Write-Host "$amar  Falta nmap:  $blanco winget install Insecure.Nmap$RST"; exit 1
}

# --- Quien es el dueno de la IP (Cloudflare? proveedor?) ---------------------
Write-Host "$gris  Consultando de quien es la IP...$RST"
$org="-"; $pais="-"; $ciudad="-"; $cf=$false
try {
  $ip = [System.Net.Dns]::GetHostAddresses($Objetivo) | Where-Object {$_.AddressFamily -eq 'InterNetwork'} | Select-Object -First 1
  $info = Invoke-RestMethod -Uri "https://ipinfo.io/$($ip.IPAddressToString)/json" -TimeoutSec 8
  if($info.org){$org=$info.org}; if($info.country){$pais=$info.country}; if($info.city){$ciudad=$info.city}
  if($org -match 'cloudflare'){$cf=$true}
} catch {}

# --- Escaneo de puertos ------------------------------------------------------
if ($Completo) {
  Write-Host "$gris  Escaneo COMPLETO (65535 puertos). Puede tardar 5-15 min...$RST"
  $args = @('-sV','-T4','-Pn','-p-',$Objetivo)
} else {
  Write-Host "$gris  Escaneo rapido (1000 puertos comunes). 1-2 min...$RST"
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
Banner "auditor de servidores"
Write-Host (Seccion "AUDITORIA DE VPS")
Write-Host (Fila "$blanco$Objetivo$RST" "$gris$hora$RST")
Write-Host (Fila ("$gris" + "Estado:$RST " + $(if($vivo){"$verde● responde$RST"}else{"$amar○ sin ping$RST"})) ("$gris $(if($Completo){'escaneo completo'}else{'escaneo rapido'})$RST"))

Write-Host ""

# Dueno de la IP
Write-Host (Seccion "DUENO DE LA IP")
Write-Host (Fila "$gris Proveedor:$RST $blanco$org$RST")
Write-Host (Fila "$gris Lugar:$RST $blanco$ciudad, $pais$RST")
if($cf){ Write-Host (Fila "$amar ⚑ Esta IP es de CLOUDFLARE$RST") }
else   { Write-Host (Fila "$verde ● IP directa del servidor (no Cloudflare)$RST") }

Write-Host ""

# Puertos
Write-Host (Seccion "PUERTOS ABIERTOS · $($puertos.Count)")
if($puertos.Count -eq 0){ Write-Host (Fila "$gris Ninguno visible desde afuera.$RST") }
else { foreach($x in $puertos){
  $vv=$x.Vers; if($vv.Length -gt 24){$vv=$vv.Substring(0,24)}
  Write-Host (Fila "$verde● $RST$blanco$($x.Puerto.PadRight(9))$RST$cyan$($x.Serv.PadRight(11))$RST" "$gris$vv$RST")
}}

Write-Host ""

# Avisos
Write-Host (Seccion "AVISOS DE SEGURIDAD")
$av=0
function Chk { param($p) return ($texto -match $p) }
if(Chk '23/tcp\s+open')  {Write-Host (Fila "$rojo✖ Telnet (23) abierto: inseguro$RST");$av++}
if(Chk '21/tcp\s+open')  {Write-Host (Fila "$amar! FTP (21): usa SFTP$RST");$av++}
if(Chk '3306/tcp\s+open'){Write-Host (Fila "$rojo✖ MySQL (3306) expuesto a internet$RST");$av++}
if(Chk '6379/tcp\s+open'){Write-Host (Fila "$rojo✖ Redis (6379) expuesto: peligroso$RST");$av++}
if(Chk '5432/tcp\s+open'){Write-Host (Fila "$amar! PostgreSQL (5432) expuesto$RST");$av++}
if(Chk '22/tcp\s+open')  {Write-Host (Fila "$gris i SSH (22) en puerto por defecto$RST")}
if($av -eq 0){ Write-Host (Fila "$verde✔ Sin alertas graves.$RST") }

Write-Host ""
Write-Host "$gris  Hecho · $hora · solo servidores propios$RST"
Write-Host ""


