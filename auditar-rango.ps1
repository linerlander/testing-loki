<#
=============================================================================
 auditar-rango.ps1  ·  Escanea un RANGO de IP propias (desde Windows)

 USO:
   .\auditar-rango.ps1 -Desde <IP_inicial> -Hasta <IP_final>

 Ej (red local tuya):
   .\auditar-rango.ps1 -Desde 192.168.1.1 -Hasta 192.168.1.20

 Ej (varios VPS tuyos seguidos, SOLO si son todos tuyos):
   .\auditar-rango.ps1 -Desde 190.183.229.172 -Hasta 190.183.229.174

 Necesita nmap para Windows:  winget install Insecure.Nmap

 ADVERTENCIA IMPORTANTE:
 Este modo revisa VARIAS IP de una. Cada una de esas IP tiene que ser
 TUYA o estar autorizada por su dueno. La mayoria de los rangos de
 Internet pertenecen a un proveedor (ISP, datacenter) que los reparte
 entre MUCHOS clientes distintos: ser dueno de UNA IP de ese bloque NO
 te da permiso sobre las demas. Si no sabes si el rango entero es tuyo,
 no lo uses: consulta primero con
   (Invoke-RestMethod "https://rdap.lacnic.net/rdap/ip/<IP>").entities
 y confirma que el titular seas vos o tu organizacion.

 Tope de seguridad: maximo 64 IP por corrida, para evitar un uso
 accidental sobre un bloque ajeno grande.
=============================================================================
#>
param(
  [Parameter(Mandatory = $true)] [string]$Desde,
  [Parameter(Mandatory = $true)] [string]$Hasta,
  [switch]$SoloVivos   # si se pasa, no escanea puertos: solo ve que IP responden
)

. "$PSScriptRoot\lib-panel.ps1"

Banner "auditor de rango"

function IP-A-Numero { param($ip)
  $o = $ip.Split('.')
  if ($o.Count -ne 4) { return $null }
  return ([uint32]$o[0] -shl 24) -bor ([uint32]$o[1] -shl 16) -bor ([uint32]$o[2] -shl 8) -bor [uint32]$o[3]
}
function Numero-A-IP { param($n)
  "{0}.{1}.{2}.{3}" -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255)
}

$nd = IP-A-Numero $Desde
$nh = IP-A-Numero $Hasta
if ($null -eq $nd -or $null -eq $nh) {
  Write-Host "  $rojo✖ Las IP tienen que ser del tipo 1.2.3.4$R`n"; exit 1
}
if ($nh -lt $nd) {
  Write-Host "  $rojo✖ -Hasta tiene que ser igual o mayor que -Desde$R`n"; exit 1
}
$total = $nh - $nd + 1
if ($total -gt 64) {
  Write-Host "  $rojo✖ Ese rango tiene $total direcciones: el tope por corrida es 64.$R"
  Write-Host "  $gris   Partilo en tandas mas chicas.$R`n"; exit 1
}

# --- Candado de autorizacion, reforzado para rangos ---------------------------
Write-Host (Seccion "AUTORIZACION")
Write-Host (Texto "${blanco} Vas a escanear ${B}${total} direccion(es)${R}${blanco}: $Desde a $Hasta$R")
Write-Host (Texto "$amar Cada una de esas IP tiene que ser tuya o estar autorizada.$R")
Write-Host (Texto "$gris Si forman parte de un bloque de un proveedor compartido con$R")
Write-Host (Texto "$gris otros clientes, esto NO te autoriza a escanear las de otros.$R")
Write-Host ""
$ok1 = Read-Host "  Escribi 'si' si TODAS esas IP son tuyas o estan autorizadas"
if ($ok1 -ne "si") { Write-Host "`n  $rojo✖ Cancelado.$R`n"; exit 1 }
$ok2 = Read-Host "  Confirma de nuevo: escribi el total de IP (${total}) para continuar"
if ($ok2 -ne "$total") { Write-Host "`n  $rojo✖ Cancelado: no coincide.$R`n"; exit 1 }
Write-Host ""

if (-not (Get-Command nmap -ErrorAction SilentlyContinue)) {
  Write-Host "  $amar Falta nmap:  $blanco winget install Insecure.Nmap$R`n"; exit 1
}

$hora = Get-Date -Format "HH:mm"
Write-Host (Seccion "RANGO · $Desde - $Hasta · $hora")
Write-Host ""

for ($n = $nd; $n -le $nh; $n++) {
  $ip = Numero-A-IP $n
  $vivo = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
  if (-not $vivo) {
    Write-Host (Fila "$ip" "$gris○ sin respuesta$R")
    continue
  }
  if ($SoloVivos) {
    Write-Host (Fila "$ip" "$verde● responde$R")
    continue
  }
  $salida = & nmap -sV -T4 -Pn $ip 2>$null
  $abiertos = ($salida | Select-String -Pattern '^\d+/(tcp|udp)\s+open').Count
  Write-Host (Fila "$ip" "$verde● responde$R $gris· $abiertos puerto(s) abierto(s)$R")
}

Write-Host ""
Pie "Hecho · $hora · solo IP propias o autorizadas"
