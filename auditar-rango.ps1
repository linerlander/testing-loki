<#
=============================================================================
 auditar-rango.ps1  ·  Escanea un RANGO de IP propias (desde Windows)

 USO:
   .\auditar-rango.ps1 -Desde <IP_inicial> -Hasta <IP_final>

 Ej (red local tuya):
   .\auditar-rango.ps1 -Desde 192.168.1.1 -Hasta 192.168.1.20

 Ej (varios VPS tuyos seguidos, SOLO si son todos tuyos):
   .\auditar-rango.ps1 -Desde 203.0.113.10 -Hasta 203.0.113.12

 Opciones:
   -SoloVivos        No escanea puertos: solo ve que IP responden (mas rapido)
   -Reporte <ruta>   Donde guardar el reporte. Si no se pasa, se guarda solo
                      en .\reportes\rango-<fecha-hora>.txt
   -SinReporte       No guarda nada en archivo

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
  [switch]$SoloVivos,
  [string]$Reporte,
  [switch]$SinReporte
)

. "$PSScriptRoot\lib-panel.ps1"

Banner "auditor de rango"

function IP-A-Numero { param($ip)
  $o = $ip.Split('.')
  if ($o.Count -ne 4) { return $null }
  foreach ($x in $o) {
    if (-not ($x -match '^\d{1,3}$') -or [int]$x -gt 255) { return $null }
  }
  return ([uint32]$o[0] -shl 24) -bor ([uint32]$o[1] -shl 16) -bor ([uint32]$o[2] -shl 8) -bor [uint32]$o[3]
}
function Numero-A-IP { param($n)
  "{0}.{1}.{2}.{3}" -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255)
}

# --- 1) Validar las IP ---------------------------------------------------------
Write-Host (Seccion "VALIDACION")
$nd = IP-A-Numero $Desde
$nh = IP-A-Numero $Hasta
if ($null -eq $nd) { Write-Host (Fila "-Desde" "$rojo● invalida: '$Desde' no es una IP valida (ej: 1.2.3.4)$RST") }
if ($null -eq $nh) { Write-Host (Fila "-Hasta" "$rojo● invalida: '$Hasta' no es una IP valida (ej: 1.2.3.4)$RST") }
if ($null -eq $nd -or $null -eq $nh) { Write-Host ""; exit 1 }
Write-Host (Fila "-Desde" "$verde● $Desde$RST")
Write-Host (Fila "-Hasta" "$verde● $Hasta$RST")

if ($nh -lt $nd) {
  Write-Host (Texto "$rojo✖ -Hasta tiene que ser igual o mayor que -Desde$RST`n"); exit 1
}
$total = $nh - $nd + 1
if ($total -gt 64) {
  Write-Host (Texto "$rojo✖ Ese rango tiene $total direcciones: el tope por corrida es 64.$RST")
  Write-Host (Texto "$gris   Partilo en tandas mas chicas.$RST`n"); exit 1
}
Write-Host (Fila "Direcciones a revisar" "$blanco$total$RST")
Write-Host ""

# --- 2) Resumen antes de empezar + autorizacion --------------------------------
Write-Host (Seccion "RESUMEN")
Write-Host (Fila "Rango" "$blanco$Desde  →  $Hasta$RST")
Write-Host (Fila "Cantidad de IP" "$blanco$total$RST")
Write-Host (Fila "Modo" "$blanco$(if($SoloVivos){'solo ver si responden'}else{'responde + puertos abiertos'})$RST")
$rutaReporte = $null
if (-not $SinReporte) {
  if (-not $Reporte) {
    $dirRep = Join-Path $PSScriptRoot "reportes"
    New-Item -ItemType Directory -Path $dirRep -Force | Out-Null
    $rutaReporte = Join-Path $dirRep ("rango-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
  } else { $rutaReporte = $Reporte }
  Write-Host (Fila "Reporte" "$blanco$rutaReporte$RST")
} else {
  Write-Host (Fila "Reporte" "$gris no se va a guardar$RST")
}
Write-Host ""
Write-Host (Texto "$amar⚠ Cada una de esas IP tiene que ser tuya o estar autorizada.$RST")
Write-Host (Texto "$gris  Si forman parte de un bloque de un proveedor compartido con$RST")
Write-Host (Texto "$gris  otros clientes, esto NO te autoriza a escanear las de otros.$RST")
Write-Host ""
$ok1 = Read-Host "  Escribi 'si' si TODAS esas IP son tuyas o estan autorizadas"
if ($ok1 -ne "si") { Write-Host "`n  $rojo✖ Cancelado.$RST`n"; exit 1 }
$ok2 = Read-Host "  Confirma de nuevo: escribi el total de IP (${total}) para continuar"
if ($ok2 -ne "$total") { Write-Host "`n  $rojo✖ Cancelado: no coincide.$RST`n"; exit 1 }
Write-Host ""

if (-not $SoloVivos -and -not (Get-Command nmap -ErrorAction SilentlyContinue)) {
  Write-Host "  $amar Falta nmap:  $blanco winget install Insecure.Nmap$RST`n"; exit 1
}

# --- 3) Escaneo -----------------------------------------------------------------
$hora = Get-Date -Format "HH:mm"
$inicio = Get-Date
Write-Host (Seccion "RANGO · $Desde - $Hasta · $hora")
Write-Host ""

$resultados = @()
for ($n = $nd; $n -le $nh; $n++) {
  $ip = Numero-A-IP $n
  $vivo = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
  if (-not $vivo) {
    Write-Host (Fila "$ip" "$gris○ sin respuesta$RST")
    $resultados += [pscustomobject]@{ IP=$ip; Estado="sin respuesta"; Puertos="" }
    continue
  }
  if ($SoloVivos) {
    Write-Host (Fila "$ip" "$verde● responde$RST")
    $resultados += [pscustomobject]@{ IP=$ip; Estado="responde"; Puertos="(no revisado, -SoloVivos)" }
    continue
  }
  $salida = & nmap -sV -T4 -Pn $ip 2>$null
  $lineasAbiertos = $salida | Select-String -Pattern '^\d+/(tcp|udp)\s+open'
  $abiertos = $lineasAbiertos.Count
  $detalle = ($lineasAbiertos | ForEach-Object { ($_ -replace '\s+',' ').Trim() }) -join " | "
  Write-Host (Fila "$ip" "$verde● responde$RST $gris· $abiertos puerto(s) abierto(s)$RST")
  $resultados += [pscustomobject]@{ IP=$ip; Estado="responde"; Puertos=$detalle }
}

Write-Host ""
Pie "Hecho · $hora · solo IP propias o autorizadas"

# --- 4) Guardar reporte ----------------------------------------------------------
if ($rutaReporte) {
  $dur = (Get-Date) - $inicio
  $lineas = @()
  $lineas += "REPORTE DE AUDITORIA POR RANGO - testing-loki"
  $lineas += "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $lineas += "Rango: $Desde a $Hasta  ($total direccion(es))"
  $lineas += "Modo: $(if($SoloVivos){'solo ver si responden'}else{'responde + puertos abiertos'})"
  $lineas += "Duracion: $([math]::Round($dur.TotalSeconds,1)) s"
  $lineas += ""
  $lineas += "IP               | Estado         | Puertos"
  $lineas += "-----------------|----------------|--------------------------------------------"
  foreach ($r in $resultados) {
    $lineas += "{0,-16} | {1,-14} | {2}" -f $r.IP, $r.Estado, $r.Puertos
  }
  Set-Content -Path $rutaReporte -Value $lineas -Encoding UTF8
  Write-Host "  $gris📄 Reporte guardado en: $blanco$rutaReporte$RST`n"
}
