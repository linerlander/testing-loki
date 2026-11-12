<#
=============================================================================
 diagnostico.ps1  ·  Diagnostico de conectividad: un servidor o un rango

 Comprueba, POR IP (sin depender de DNS para los objetivos):
   - Si tu propio equipo tiene salida a Internet (contra IPs fijas conocidas)
   - Si el host responde (ping)
   - Que puertos TCP estan abiertos (22, 80, 443, 3306 por defecto, o los
     que vos definas con -Puertos)
   - Si hay web en 80/443/8080/8443, el codigo HTTP (200, 301, 403, 404, 500...)
   - Latencia de cada prueba
 Y clasifica cada IP en: host inaccesible / responde pero sin puertos /
 puerto(s) abierto(s) / servicio web respondiendo.

 USO (una sola IP):
   .\diagnostico.ps1 -Objetivo 190.183.229.172
   .\diagnostico.ps1 -Objetivo 190.183.229.172 -Puertos 22,80,443,8080

 USO (rango, mismas reglas que auditar-rango.ps1 — tope 64, doble confirmacion):
   .\diagnostico.ps1 -Desde 192.168.1.1 -Hasta 192.168.1.20

 Reportes:
   Por defecto guarda .\reportes\diagnostico-<fecha-hora>.txt y .csv
   -SinReporte   no guarda nada
   -Txt <ruta>   -Csv <ruta>   elegir el nombre/ubicacion de cada uno

 Solo servidores/rangos TUYOS o con autorizacion expresa (ver auditar-rango.ps1
 para la explicacion completa de por que un rango compartido con otros
 clientes de un mismo proveedor NO esta cubierto por tu autorizacion).
=============================================================================
#>
param(
  [string]$Objetivo,
  [string]$Desde,
  [string]$Hasta,
  [int[]]$Puertos = @(22,80,443,3306),
  [string]$Txt,
  [string]$Csv,
  [switch]$SinReporte
)

. "$PSScriptRoot\lib-panel.ps1"
Banner "diagnostico de conectividad"

# --- 0) Que se pidio: una IP o un rango? --------------------------------------
if ($Objetivo -and ($Desde -or $Hasta)) {
  Write-Host "  $rojo✖ Usa -Objetivo SOLO, o -Desde/-Hasta SOLO, no los dos.$RST`n"; exit 1
}
if (-not $Objetivo -and -not ($Desde -and $Hasta)) {
  Write-Host "  $rojo✖ Falta indicar que revisar:$RST"
  Write-Host "     $gris.\diagnostico.ps1 -Objetivo <IP>$RST"
  Write-Host "     $gris.\diagnostico.ps1 -Desde <IP> -Hasta <IP>$RST`n"
  exit 1
}
$esRango = -not $Objetivo

function IP-A-Numero { param($ip)
  $o = $ip.Split('.')
  if ($o.Count -ne 4) { return $null }
  foreach ($x in $o) { if (-not ($x -match '^\d{1,3}$') -or [int]$x -gt 255) { return $null } }
  return ([uint32]$o[0] -shl 24) -bor ([uint32]$o[1] -shl 16) -bor ([uint32]$o[2] -shl 8) -bor [uint32]$o[3]
}
function Numero-A-IP { param($n)
  "{0}.{1}.{2}.{3}" -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255) }

# --- 1) Armar la lista de IP a revisar -----------------------------------------
Write-Host (Seccion "VALIDACION")
$ips = @()
if ($esRango) {
  $nd = IP-A-Numero $Desde; $nh = IP-A-Numero $Hasta
  if ($null -eq $nd) { Write-Host (Fila "-Desde" "$rojo● invalida: '$Desde'$RST") }
  if ($null -eq $nh) { Write-Host (Fila "-Hasta" "$rojo● invalida: '$Hasta'$RST") }
  if ($null -eq $nd -or $null -eq $nh) { Write-Host ""; exit 1 }
  if ($nh -lt $nd) { Write-Host (Texto "$rojo✖ -Hasta tiene que ser igual o mayor que -Desde$RST`n"); exit 1 }
  $total = $nh - $nd + 1
  if ($total -gt 64) {
    Write-Host (Texto "$rojo✖ Ese rango tiene $total direcciones: el tope por corrida es 64.$RST")
    Write-Host (Texto "$gris   Partilo en tandas mas chicas.$RST`n"); exit 1
  }
  Write-Host (Fila "-Desde" "$verde● $Desde$RST")
  Write-Host (Fila "-Hasta" "$verde● $Hasta$RST")
  Write-Host (Fila "Direcciones a revisar" "$blanco$total$RST")
  for ($n = $nd; $n -le $nh; $n++) { $ips += Numero-A-IP $n }
} else {
  $n1 = IP-A-Numero $Objetivo
  if ($null -eq $n1) { Write-Host (Fila "-Objetivo" "$rojo● invalida: '$Objetivo'$RST`n"); exit 1 }
  Write-Host (Fila "-Objetivo" "$verde● $Objetivo$RST")
  $ips = @($Objetivo)
}
Write-Host (Fila "Puertos a revisar" "$blanco$($Puertos -join ', ')$RST")
Write-Host ""

# --- 2) Resumen + reporte -------------------------------------------------------
Write-Host (Seccion "RESUMEN")
Write-Host (Fila "Modo" "$blanco$(if($esRango){'rango'}else{'servidor unico'})$RST")
Write-Host (Fila "Cantidad de IP" "$blanco$($ips.Count)$RST")
Write-Host (Fila "Puertos" "$blanco$($Puertos -join ', ')$RST")
$rutaTxt = $null; $rutaCsv = $null
if (-not $SinReporte) {
  $dirRep = Join-Path $PSScriptRoot "reportes"
  New-Item -ItemType Directory -Path $dirRep -Force | Out-Null
  $sello = Get-Date -Format "yyyyMMdd-HHmmss"
  $rutaTxt = if ($Txt) { $Txt } else { Join-Path $dirRep "diagnostico-$sello.txt" }
  $rutaCsv = if ($Csv) { $Csv } else { Join-Path $dirRep "diagnostico-$sello.csv" }
  Write-Host (Fila "Reporte TXT" "$blanco$rutaTxt$RST")
  Write-Host (Fila "Reporte CSV" "$blanco$rutaCsv$RST")
} else {
  Write-Host (Fila "Reporte" "$gris no se va a guardar$RST")
}
Write-Host ""
Write-Host (Texto "$amar⚠ Cada IP tiene que ser tuya o estar autorizada.$RST")
if ($esRango) {
  Write-Host (Texto "$gris  Un bloque compartido con otros clientes de tu proveedor NO$RST")
  Write-Host (Texto "$gris  queda autorizado por ser dueno de UNA sola IP de ese bloque.$RST")
  Write-Host ""
  $ok1 = Read-Host "  Escribi 'si' si TODAS esas IP son tuyas o estan autorizadas"
  if ($ok1 -ne "si") { Write-Host "`n  $rojo✖ Cancelado.$RST`n"; exit 1 }
  $ok2 = Read-Host "  Confirma de nuevo: escribi el total de IP ($($ips.Count)) para continuar"
  if ($ok2 -ne "$($ips.Count)") { Write-Host "`n  $rojo✖ Cancelado: no coincide.$RST`n"; exit 1 }
} else {
  Write-Host ""
  $ok1 = Read-Host "  Escribi 'si' si este servidor es tuyo o esta autorizado"
  if ($ok1 -ne "si") { Write-Host "`n  $rojo✖ Cancelado.$RST`n"; exit 1 }
}
Write-Host ""

# --- 3) Tu propio internet, sin usar DNS (IPs fijas conocidas) -----------------
function Prueba-Puerto { param($h,$p,$msTimeout=2500)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect($h,$p,$null,$null)
    $okw = $iar.AsyncWaitHandle.WaitOne($msTimeout,$false)
    $ok = $okw -and $c.Connected
    $c.Close()
    $sw.Stop()
    return @{ Ok = $ok; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds) }
  } catch { $sw.Stop(); return @{ Ok = $false; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds) } }
}

Write-Host (Seccion "TU CONEXION A INTERNET")
$miNet = (Prueba-Puerto "1.1.1.1" 443 2000).Ok -or (Prueba-Puerto "8.8.8.8" 443 2000).Ok
if ($miNet) { Write-Host (Fila "Internet (via IP, sin DNS)" "$verde● conectado$RST") }
else { Write-Host (Fila "Internet (via IP, sin DNS)" "$rojo● sin salida a internet$RST") }
Write-Host ""

if (-not $miNet) {
  Write-Host (Texto "$amar⚠ Tu equipo no pudo salir a internet ni contra 1.1.1.1 ni 8.8.8.8.$RST")
  Write-Host (Texto "$gris   Lo que sigue puede fallar por TU conexion, no por tus servidores.$RST")
  Write-Host ""
}

# --- 4) Diagnostico por IP --------------------------------------------------
function Prueba-HTTP { param($url, $msTimeout=6000)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $r = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec ([int]($msTimeout/1000)) -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
    $sw.Stop(); return @{ Codigo = [int]$r.StatusCode; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds) }
  } catch {
    $sw.Stop()
    if ($_.Exception.Response) { try { return @{ Codigo = [int]$_.Exception.Response.StatusCode; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds) } } catch {} }
    return @{ Codigo = 0; Ms = [math]::Round($sw.Elapsed.TotalMilliseconds) }
  }
}
function Texto-Status { param($code)
  switch ($code) {
    200 { "$verde● 200 OK$RST"; break }
    { $_ -in 301,302,307,308 } { "$cyan● $code redirige$RST"; break }
    403 { "$amar● 403 prohibido$RST"; break }
    404 { "$amar● 404 no existe$RST"; break }
    { $_ -ge 500 } { "$rojo● $code caido$RST"; break }
    0   { "$rojo● sin respuesta http$RST"; break }
    default { "$blanco● $code$RST" }
  }
}

$hora = Get-Date -Format "HH:mm:ss"
Write-Host (Seccion "DIAGNOSTICO · $hora")
Write-Host ""

$filas = @()   # para el CSV: IP, Prueba, Resultado, Detalle, LatenciaMs, Hora
$resumenIP = @()

foreach ($ip in $ips) {
  $tInicio = Get-Date
  $pingSw = [System.Diagnostics.Stopwatch]::StartNew()
  $vivo = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
  $pingSw.Stop()
  $pingMs = [math]::Round($pingSw.Elapsed.TotalMilliseconds)

  Write-Host (Texto "$lila▌$RST $blanco$BLD$ip$RST")
  $filas += [pscustomobject]@{ IP=$ip; Prueba="ping"; Resultado=$(if($vivo){"responde"}else{"sin respuesta"}); Detalle=""; LatenciaMs=$pingMs; Hora=$tInicio }

  $algunPuertoAbierto = $false
  $algunWebOk = $false
  foreach ($p in $Puertos) {
    $r = Prueba-Puerto $ip $p
    if ($r.Ok) {
      $algunPuertoAbierto = $true
      if ($p -in 80,8080) {
        $h = Prueba-HTTP "http://$ip`:$p"
        if ($h.Codigo -ge 200 -and $h.Codigo -lt 600) { $algunWebOk = $true }
        Write-Host (Fila "  :$p  (abierto)" "$(Texto-Status $h.Codigo) $gris· $($r.Ms) ms conexion, $($h.Ms) ms http$RST")
        $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p + http"; Resultado="abierto, http $($h.Codigo)"; Detalle="conexion $($r.Ms)ms / http $($h.Ms)ms"; LatenciaMs=$r.Ms; Hora=(Get-Date) }
      } elseif ($p -in 443,8443) {
        $h = Prueba-HTTP "https://$ip`:$p"
        if ($h.Codigo -ge 200 -and $h.Codigo -lt 600) { $algunWebOk = $true }
        Write-Host (Fila "  :$p  (abierto)" "$(Texto-Status $h.Codigo) $gris· $($r.Ms) ms conexion, $($h.Ms) ms https$RST")
        $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p + https"; Resultado="abierto, https $($h.Codigo)"; Detalle="conexion $($r.Ms)ms / https $($h.Ms)ms"; LatenciaMs=$r.Ms; Hora=(Get-Date) }
      } else {
        Write-Host (Fila "  :$p" "$verde● abierto$RST $gris· $($r.Ms) ms$RST")
        $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p"; Resultado="abierto"; Detalle=""; LatenciaMs=$r.Ms; Hora=(Get-Date) }
      }
    } else {
      Write-Host (Fila "  :$p" "$gris○ cerrado / sin respuesta$RST")
      $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p"; Resultado="cerrado o sin respuesta"; Detalle=""; LatenciaMs=$r.Ms; Hora=(Get-Date) }
    }
  }

  # Clasificacion final de esta IP
  if ($algunWebOk) { $cat = "servicio web respondiendo" }
  elseif ($algunPuertoAbierto) { $cat = "puerto(s) abierto(s)" }
  elseif ($vivo) { $cat = "responde, sin puertos abiertos" }
  elseif (-not $miNet) { $cat = "sin datos (revisa tu conexion)" }
  else { $cat = "host inaccesible" }
  $colorCat = switch ($cat) {
    "servicio web respondiendo"      { $verde }
    "puerto(s) abierto(s)"           { $verde }
    "responde, sin puertos abiertos" { $amar }
    "sin datos (revisa tu conexion)" { $amar }
    default                          { $rojo }
  }
  Write-Host (Fila "  Diagnostico" "$colorCat● $cat$RST")
  Write-Host ""
  $resumenIP += [pscustomobject]@{ IP=$ip; Ping=$(if($vivo){"responde"}else{"sin respuesta"}); PingMs=$pingMs; Diagnostico=$cat }
}

# --- 5) Resumen general ---------------------------------------------------------
Write-Host (Seccion "RESUMEN GENERAL")
$cAccesibles = ($resumenIP | Where-Object { $_.Diagnostico -in "servicio web respondiendo","puerto(s) abierto(s)" }).Count
$cSoloPing   = ($resumenIP | Where-Object { $_.Diagnostico -eq "responde, sin puertos abiertos" }).Count
$cInacces    = ($resumenIP | Where-Object { $_.Diagnostico -eq "host inaccesible" }).Count
$cSinDatos   = ($resumenIP | Where-Object { $_.Diagnostico -eq "sin datos (revisa tu conexion)" }).Count
Write-Host (Fila "Total revisadas" "$blanco$($ips.Count)$RST")
Write-Host (Fila "Con servicio/puerto activo" "$verde$cAccesibles$RST")
Write-Host (Fila "Responden pero sin puertos" "$amar$cSoloPing$RST")
Write-Host (Fila "Inaccesibles" "$rojo$cInacces$RST")
if ($cSinDatos -gt 0) { Write-Host (Fila "Sin datos (tu conexion)" "$amar$cSinDatos$RST") }
Write-Host ""
Pie "Hecho · $hora · solo IP propias o autorizadas"

# --- 6) Reportes -----------------------------------------------------------------
if ($rutaTxt) {
  $lin = @()
  $lin += "DIAGNOSTICO DE CONECTIVIDAD - testing-loki"
  $lin += "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $lin += "Modo: $(if($esRango){"rango $Desde a $Hasta"}else{"servidor unico $Objetivo"})"
  $lin += "Puertos revisados: $($Puertos -join ', ')"
  $lin += "Tu internet (sin DNS, via 1.1.1.1/8.8.8.8): $(if($miNet){'OK'}else{'SIN SALIDA'})"
  $lin += ""
  $lin += "RESUMEN"
  $lin += "  Total revisadas: $($ips.Count)"
  $lin += "  Con servicio/puerto activo: $cAccesibles"
  $lin += "  Responden pero sin puertos abiertos: $cSoloPing"
  $lin += "  Inaccesibles: $cInacces"
  $lin += ""
  $lin += "DETALLE POR IP"
  foreach ($r in $resumenIP) {
    $lin += "  $($r.IP) — ping: $($r.Ping) ($($r.PingMs) ms) — diagnostico: $($r.Diagnostico)"
  }
  $lin += ""
  $lin += "DETALLE DE CADA PRUEBA"
  $lin += "IP               | Prueba              | Resultado                    | Detalle"
  $lin += "-----------------|---------------------|------------------------------|-----------------"
  foreach ($f in $filas) {
    $lin += "{0,-16} | {1,-19} | {2,-28} | {3}" -f $f.IP, $f.Prueba, $f.Resultado, $f.Detalle
  }
  Set-Content -Path $rutaTxt -Value $lin -Encoding UTF8
  Write-Host "  $gris📄 TXT: $blanco$rutaTxt$RST"
}
if ($rutaCsv) {
  $filas | Select-Object IP,Prueba,Resultado,Detalle,LatenciaMs,Hora | Export-Csv -Path $rutaCsv -NoTypeInformation -Encoding UTF8
  Write-Host "  $gris📄 CSV: $blanco$rutaCsv$RST"
}
if ($rutaTxt -or $rutaCsv) { Write-Host "" }
