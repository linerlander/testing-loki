<#
=============================================================================
 diagnostico.ps1  ·  Diagnostico de conectividad en vivo: un servidor o un
 rango, con panel que se actualiza mientras corre.

 USO (una sola IP):
   .\diagnostico.ps1 -Objetivo 203.0.113.10
   .\diagnostico.ps1 -Objetivo 203.0.113.10 -Puertos 22,80,443,8080

 USO (rango — mismas reglas que auditar-rango.ps1: tope 64, doble
 confirmacion, un bloque compartido con otros clientes de tu proveedor
 NO queda autorizado solo porque una IP tuya este ahi):
   .\diagnostico.ps1 -Desde 192.168.1.1 -Hasta 192.168.1.20

 MONITOREO CONTINUO (vuelve a revisar cada N segundos y avisa cuando una
 IP cae o vuelve):
   .\diagnostico.ps1 -Objetivo 203.0.113.10 -Monitoreo -IntervaloSeg 30
   .\diagnostico.ps1 -Desde 192.168.1.1 -Hasta 192.168.1.20 -Monitoreo
   (se corta con Ctrl+C)

 Estados por IP:
   ONLINE   el host contesto de alguna forma (ping ok, o un puerto abierto,
            o un puerto que contesto "cerrado" — eso tambien prueba que
            el host esta vivo, solo que ese servicio no esta activo ahi)
   OFFLINE  la red devolvio un "destino inalcanzable" explicito (no es
            silencio: es un router o firewall diciendo que no hay nada)
   TIMEOUT  nadie contesto NADA dentro del tiempo de espera (ni ping ni
            puertos) — lo mas comun cuando un firewall descarta todo
   ERROR    fallo algo inesperado al probar esa IP (no es culpa del
            servidor, es un problema de la prueba en si)

 Reportes: por defecto .\reportes\diagnostico-<fecha-hora>.txt y .csv
   -SinReporte   no guarda nada       -Txt / -Csv <ruta>  elegir nombre

 Solo servidores/rangos TUYOS o con autorizacion expresa.
=============================================================================
#>
param(
  [string]$Objetivo,
  [string]$Desde,
  [string]$Hasta,
  [int[]]$Puertos = @(22,80,443,3306),
  [string]$Txt,
  [string]$Csv,
  [switch]$SinReporte,
  [switch]$Monitoreo,
  [int]$IntervaloSeg = 30,
  [int]$AlertaLatenciaMs = 300
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
  $partes = $ip.Split('.')
  if ($partes.Count -ne 4) { return $null }
  foreach ($x in $partes) { if (-not ($x -match '^\d{1,3}$') -or [int]$x -gt 255) { return $null } }
  return ([uint32]$partes[0] -shl 24) -bor ([uint32]$partes[1] -shl 16) -bor ([uint32]$partes[2] -shl 8) -bor [uint32]$partes[3]
}
function Numero-A-IP { param($n)
  "{0}.{1}.{2}.{3}" -f (($n -shr 24) -band 255), (($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255) }

# --- 1) Armar la lista de IP a revisar -----------------------------------------
Write-Host (Seccion "VALIDACION")
$listaIps = @()
if ($esRango) {
  $numDesde = IP-A-Numero $Desde; $numHasta = IP-A-Numero $Hasta
  if ($null -eq $numDesde) { Write-Host (Fila "-Desde" "$rojo● invalida: '$Desde'$RST") }
  if ($null -eq $numHasta) { Write-Host (Fila "-Hasta" "$rojo● invalida: '$Hasta'$RST") }
  if ($null -eq $numDesde -or $null -eq $numHasta) { Write-Host ""; exit 1 }
  if ($numHasta -lt $numDesde) { Write-Host (Texto "$rojo✖ -Hasta tiene que ser igual o mayor que -Desde$RST`n"); exit 1 }
  $totalIps = $numHasta - $numDesde + 1
  if ($totalIps -gt 64) {
    Write-Host (Texto "$rojo✖ Ese rango tiene $totalIps direcciones: el tope por corrida es 64.$RST")
    Write-Host (Texto "$gris   Partilo en tandas mas chicas.$RST`n"); exit 1
  }
  Write-Host (Fila "-Desde" "$verde● $Desde$RST")
  Write-Host (Fila "-Hasta" "$verde● $Hasta$RST")
  Write-Host (Fila "Direcciones a revisar" "$blanco$totalIps$RST")
  for ($num = $numDesde; $num -le $numHasta; $num++) { $listaIps += Numero-A-IP $num }
} else {
  $numUno = IP-A-Numero $Objetivo
  if ($null -eq $numUno) { Write-Host (Fila "-Objetivo" "$rojo● invalida: '$Objetivo'$RST`n"); exit 1 }
  Write-Host (Fila "-Objetivo" "$verde● $Objetivo$RST")
  $listaIps = @($Objetivo)
}
Write-Host (Fila "Puertos a revisar" "$blanco$($Puertos -join ', ')$RST")
if ($Monitoreo) { Write-Host (Fila "Monitoreo continuo" "$blanco cada $IntervaloSeg s (Ctrl+C para cortar)$RST") }
Write-Host ""

# --- 2) Resumen + reporte + autorizacion ---------------------------------------
Write-Host (Seccion "RESUMEN")
Write-Host (Fila "Modo" "$blanco$(if($esRango){'rango'}else{'servidor unico'})$RST")
Write-Host (Fila "Cantidad de IP" "$blanco$($listaIps.Count)$RST")
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
  $ok2 = Read-Host "  Confirma de nuevo: escribi el total de IP ($($listaIps.Count)) para continuar"
  if ($ok2 -ne "$($listaIps.Count)") { Write-Host "`n  $rojo✖ Cancelado: no coincide.$RST`n"; exit 1 }
} else {
  Write-Host ""
  $ok1 = Read-Host "  Escribi 'si' si este servidor es tuyo o esta autorizado"
  if ($ok1 -ne "si") { Write-Host "`n  $rojo✖ Cancelado.$RST`n"; exit 1 }
}
Write-Host ""
if ($Monitoreo) {
  Write-Host (Texto "$gris  El monitoreo continuo usa esta MISMA autorizacion: no se vuelve$RST")
  Write-Host (Texto "$gris  a preguntar en cada vuelta. Cortalo con Ctrl+C cuando quieras.$RST")
  Write-Host ""
}

# --- 3) Pruebas de red: ping real (distingue timeout de "inalcanzable"),
#        puerto (distingue abierto / rechazado / timeout), y http -------------
function Prueba-Ping { param($ip, $msTimeout = 2000)
  try {
    $pinger = New-Object System.Net.NetworkInformation.Ping
    $resp = $pinger.Send($ip, $msTimeout)
    $ms = [int]$resp.RoundtripTime
    switch ($resp.Status) {
      "Success" { return @{ Estado = "ok"; Ms = $ms } }
      "TimedOut" { return @{ Estado = "timeout"; Ms = $msTimeout } }
      default {
        # DestinationHostUnreachable, DestinationNetworkUnreachable, etc:
        # la red CONTESTO que no hay nada, no es silencio.
        return @{ Estado = "rechazado"; Ms = $ms; Detalle = "$($resp.Status)" }
      }
    }
  } catch {
    return @{ Estado = "error"; Ms = 0; Detalle = $_.Exception.Message }
  }
}

function Prueba-Puerto { param($ip, $puerto, $msTimeout = 2500)
  $cron = [System.Diagnostics.Stopwatch]::StartNew()
  $cliente = New-Object System.Net.Sockets.TcpClient
  try {
    $pendiente = $cliente.BeginConnect($ip, $puerto, $null, $null)
    $llego = $pendiente.AsyncWaitHandle.WaitOne($msTimeout, $false)
    if (-not $llego) {
      $cron.Stop()
      return @{ Estado = "timeout"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
    }
    try {
      $cliente.EndConnect($pendiente)
      $cron.Stop()
      return @{ Estado = "abierto"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
    } catch {
      $cron.Stop()
      return @{ Estado = "rechazado"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
    }
  } catch {
    $cron.Stop()
    return @{ Estado = "error"; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
  } finally {
    try { if ($cliente.Connected) { $cliente.Close() } else { $cliente.Dispose() } } catch {}
  }
}

function Prueba-HTTP { param($url, $msTimeout = 6000)
  $cron = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec ([int]($msTimeout/1000)) -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
    $cron.Stop(); return @{ Codigo = [int]$resp.StatusCode; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
  } catch {
    $cron.Stop()
    if ($_.Exception.Response) { try { return @{ Codigo = [int]$_.Exception.Response.StatusCode; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) } } catch {} }
    return @{ Codigo = 0; Ms = [math]::Round($cron.Elapsed.TotalMilliseconds) }
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
function Texto-Puerto { param($estado, $ms)
  switch ($estado) {
    "abierto"   { "$verde● abierto$RST $gris· ${ms} ms$RST"; break }
    "rechazado" { "$amar● cerrado (el host contesto)$RST $gris· ${ms} ms$RST"; break }
    "timeout"   { "$gris○ sin respuesta (timeout)$RST"; break }
    default     { "$rojo● error$RST" }
  }
}

# Clasifica la IP completa en ONLINE / OFFLINE / TIMEOUT / ERROR
function Clasificar { param($ping, $puertosRes)
  if ($ping.Estado -eq "error") { return "ERROR" }
  if ($ping.Estado -eq "ok") { return "ONLINE" }
  $hayAbierto   = $puertosRes | Where-Object { $_.Estado -eq "abierto" }
  $hayRechazado = $puertosRes | Where-Object { $_.Estado -eq "rechazado" }
  $hayError     = $puertosRes | Where-Object { $_.Estado -eq "error" }
  if ($hayAbierto)   { return "ONLINE" }   # algo escucha: el host esta vivo seguro
  if ($hayRechazado) { return "ONLINE" }   # el host contesto "cerrado": tambien esta vivo
  if ($ping.Estado -eq "rechazado") { return "OFFLINE" }  # la red dijo "inalcanzable"
  if ($hayError -and $puertosRes.Count -eq $hayError.Count) { return "ERROR" }
  return "TIMEOUT"   # nadie contesto nada, ni a favor ni en contra
}
function Color-Estado { param($estado)
  switch ($estado) {
    "ONLINE"  { $verde; break }
    "OFFLINE" { $rojo; break }
    "TIMEOUT" { $amar; break }
    default   { $rojo }
  }
}

# --- 4) Tu propio internet, sin usar DNS (IPs fijas conocidas) -----------------
Write-Host (Seccion "TU CONEXION A INTERNET")
$r1 = Prueba-Puerto "1.1.1.1" 443 2000
$r2 = if ($r1.Estado -ne "abierto") { Prueba-Puerto "8.8.8.8" 443 2000 } else { $null }
$miNet = ($r1.Estado -eq "abierto") -or ($r2 -and $r2.Estado -eq "abierto")
if ($miNet) { Write-Host (Fila "Internet (via IP, sin DNS)" "$verde● conectado$RST") }
else        { Write-Host (Fila "Internet (via IP, sin DNS)" "$rojo● sin salida a internet$RST") }
Write-Host ""
if (-not $miNet) {
  Write-Host (Texto "$amar⚠ Tu equipo no pudo salir a internet ni contra 1.1.1.1 ni 8.8.8.8.$RST")
  Write-Host (Texto "$gris   Lo que sigue puede fallar por TU conexion, no por tus servidores.$RST")
  Write-Host ""
}

# --- 5) Barra de progreso de una sola linea, "viva" ---------------------------
# Se redibuja en el lugar: antes de imprimir el detalle de la siguiente IP se
# borra con retorno de carro + espacios (sin depender de codigos ANSI de
# borrado de linea, que no siempre se interpretan igual segun la terminal),
# y despues de cada IP se vuelve a dejar al pie, sin saltos de linea. Asi
# convive con el log normal que va quedando arriba.
$script:barraViva = $false
$script:barraLargoAnterior = 0
function Borrar-Barra {
  if ($script:barraViva) {
    Write-Host -NoNewline ("`r" + (" " * $script:barraLargoAnterior) + "`r")
    $script:barraViva = $false
  }
}
function Dibujar-Barra { param($indice, $total, $ipActual, $cont, $inicio)
  $pct = if ($total -gt 0) { [math]::Round(($indice / $total) * 100) } else { 100 }
  $n = [math]::Round($pct / 10); if ($n -gt 10) { $n = 10 }; if ($n -lt 0) { $n = 0 }
  $barra = "$verde" + ("▰"*$n) + "$gris" + ("▱"*(10-$n)) + "$RST"
  $transcurrido = (Get-Date) - $inicio
  $porIp = if ($indice -gt 0) { $transcurrido.TotalSeconds / $indice } else { 0 }
  $restan = [math]::Max(0, $total - $indice)
  $eta = [TimeSpan]::FromSeconds([math]::Round($porIp * $restan))
  $txt = "  $barra $blanco$pct%$RST $gris·$RST $indice/$total $gris·$RST $blanco$ipActual$RST  " +
         "$verde ON:$($cont.ONLINE)$RST $rojo OFF:$($cont.OFFLINE)$RST $amar TO:$($cont.TIMEOUT)$RST $rojo ERR:$($cont.ERROR)$RST  " +
         "$gris $($transcurrido.ToString('mm\:ss')) transcurrido · ETA ~$($eta.ToString('mm\:ss'))$RST"
  $plano = ($txt -replace "$($script:ESC)\[[0-9;]*m","")
  Write-Host -NoNewline $txt
  $script:barraLargoAnterior = $plano.Length
  $script:barraViva = $true
}

# --- 6) Una pasada completa sobre la lista de IP -------------------------------
function Una-Pasada { param($ips, $Puertos, $miNet)
  $inicio = Get-Date
  $filas = @()        # para CSV/TXT: detalle de cada prueba
  $resumenIP = @()    # para el resumen y para el monitoreo continuo
  $cont = @{ ONLINE = 0; OFFLINE = 0; TIMEOUT = 0; ERROR = 0 }

  for ($idx = 0; $idx -lt $ips.Count; $idx++) {
    $ip = $ips[$idx]
    Borrar-Barra
    Write-Host (Texto "$lila▌$RST $blanco$BLD$ip$RST")

    try {
      $tInicio = Get-Date
      $ping = Prueba-Ping $ip
      $alertaLat = $ping.Ms -gt $AlertaLatenciaMs
      $txtPing = switch ($ping.Estado) {
        "ok"        { "$verde● responde$RST $gris· $($ping.Ms) ms$RST" + $(if($alertaLat){" $amar⚠ latencia alta$RST"}else{""}) }
        "timeout"   { "$gris○ sin respuesta (timeout)$RST" }
        "rechazado" { "$rojo● inalcanzable$RST $gris· $($ping.Detalle)$RST" }
        default     { "$rojo✖ error$RST $gris· $($ping.Detalle)$RST" }
      }
      Write-Host (Fila "  ping" $txtPing)
      $filas += [pscustomobject]@{ IP=$ip; Prueba="ping"; Resultado=$ping.Estado; Detalle=""; LatenciaMs=$ping.Ms; Hora=$tInicio }

      $puertosRes = @()
      foreach ($p in $Puertos) {
        $res = Prueba-Puerto $ip $p
        $puertosRes += [pscustomobject]@{ Puerto=$p; Estado=$res.Estado; Ms=$res.Ms }
        if ($res.Estado -eq "abierto" -and $p -in 80,8080) {
          $http = Prueba-HTTP "http://$ip`:$p"
          Write-Host (Fila "  :$p" "$(Texto-Status $http.Codigo) $gris· $($res.Ms) ms conexion, $($http.Ms) ms http$RST")
          $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p + http"; Resultado="http $($http.Codigo)"; Detalle="conexion $($res.Ms)ms / http $($http.Ms)ms"; LatenciaMs=$res.Ms; Hora=(Get-Date) }
        } elseif ($res.Estado -eq "abierto" -and $p -in 443,8443) {
          $http = Prueba-HTTP "https://$ip`:$p"
          Write-Host (Fila "  :$p" "$(Texto-Status $http.Codigo) $gris· $($res.Ms) ms conexion, $($http.Ms) ms https$RST")
          $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p + https"; Resultado="https $($http.Codigo)"; Detalle="conexion $($res.Ms)ms / https $($http.Ms)ms"; LatenciaMs=$res.Ms; Hora=(Get-Date) }
        } else {
          Write-Host (Fila "  :$p" (Texto-Puerto $res.Estado $res.Ms))
          $filas += [pscustomobject]@{ IP=$ip; Prueba="puerto $p"; Resultado=$res.Estado; Detalle=""; LatenciaMs=$res.Ms; Hora=(Get-Date) }
        }
      }

      $estado = Clasificar $ping $puertosRes
    } catch {
      $estado = "ERROR"
      Write-Host (Fila "  error" "$rojo✖ $($_.Exception.Message)$RST")
      $filas += [pscustomobject]@{ IP=$ip; Prueba="general"; Resultado="error"; Detalle=$_.Exception.Message; LatenciaMs=0; Hora=(Get-Date) }
      $ping = @{ Estado = "error"; Ms = 0 }
      $puertosRes = @()
    }
    $cont[$estado]++
    Write-Host (Fila "  ESTADO" "$(Color-Estado $estado)$BLD$estado$RST")
    Write-Host ""
    $resumenIP += [pscustomobject]@{ IP=$ip; Ping=$ping.Estado; PingMs=$ping.Ms; Estado=$estado }

    Dibujar-Barra ($idx+1) $ips.Count $ip $cont $inicio
  }
  Borrar-Barra
  return @{ Filas = $filas; ResumenIP = $resumenIP; Cont = $cont; Duracion = (Get-Date) - $inicio }
}

# --- 7) Guardar reportes --------------------------------------------------------
function Guardar-Reportes { param($rutaTxt, $rutaCsv, $modo, $ips, $Puertos, $miNet, $pasada)
  if ($rutaTxt) {
    $lin = @()
    $lin += "DIAGNOSTICO DE CONECTIVIDAD - testing-loki"
    $lin += "Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lin += "Modo: $modo"
    $lin += "Puertos revisados: $($Puertos -join ', ')"
    $lin += "Tu internet (sin DNS, via 1.1.1.1/8.8.8.8): $(if($miNet){'OK'}else{'SIN SALIDA'})"
    $lin += "Duracion: $([math]::Round($pasada.Duracion.TotalSeconds,1)) s"
    $lin += ""
    $lin += "RESUMEN"
    $lin += "  Total revisadas: $($ips.Count)"
    $lin += "  ONLINE: $($pasada.Cont.ONLINE)  OFFLINE: $($pasada.Cont.OFFLINE)  TIMEOUT: $($pasada.Cont.TIMEOUT)  ERROR: $($pasada.Cont.ERROR)"
    $lin += ""
    $lin += "DETALLE POR IP"
    foreach ($r in $pasada.ResumenIP) { $lin += "  $($r.IP) — ping: $($r.Ping) ($($r.PingMs) ms) — estado: $($r.Estado)" }
    $lin += ""
    $lin += "DETALLE DE CADA PRUEBA"
    $lin += "IP               | Prueba              | Resultado                    | Detalle"
    $lin += "-----------------|---------------------|------------------------------|-----------------"
    foreach ($f in $pasada.Filas) { $lin += "{0,-16} | {1,-19} | {2,-28} | {3}" -f $f.IP, $f.Prueba, $f.Resultado, $f.Detalle }
    Set-Content -Path $rutaTxt -Value $lin -Encoding UTF8
  }
  if ($rutaCsv) {
    $pasada.Filas | Select-Object IP,Prueba,Resultado,Detalle,LatenciaMs,Hora | Export-Csv -Path $rutaCsv -NoTypeInformation -Encoding UTF8
  }
}

# ===============================================================================
if (-not $Monitoreo) {
  # --- Una sola pasada --------------------------------------------------------
  $hora = Get-Date -Format "HH:mm:ss"
  Write-Host (Seccion "DIAGNOSTICO · $hora")
  Write-Host ""
  $pasada = Una-Pasada $listaIps $Puertos $miNet

  Write-Host (Seccion "RESUMEN GENERAL")
  Write-Host (Fila "Total revisadas" "$blanco$($listaIps.Count)$RST")
  Write-Host (Fila "ONLINE" "$verde$($pasada.Cont.ONLINE)$RST")
  Write-Host (Fila "OFFLINE" "$rojo$($pasada.Cont.OFFLINE)$RST")
  Write-Host (Fila "TIMEOUT" "$amar$($pasada.Cont.TIMEOUT)$RST")
  Write-Host (Fila "ERROR" "$rojo$($pasada.Cont.ERROR)$RST")
  Write-Host (Fila "Duracion" "$blanco$([math]::Round($pasada.Duracion.TotalSeconds,1)) s$RST")
  Write-Host ""
  Pie "Hecho · $hora · solo IP propias o autorizadas"

  if ($rutaTxt -or $rutaCsv) {
    Guardar-Reportes $rutaTxt $rutaCsv $(if($esRango){"rango $Desde a $Hasta"}else{"servidor unico $Objetivo"}) $listaIps $Puertos $miNet $pasada
    if ($rutaTxt) { Write-Host "  $gris📄 TXT: $blanco$rutaTxt$RST" }
    if ($rutaCsv) { Write-Host "  $gris📄 CSV: $blanco$rutaCsv$RST" }
    Write-Host ""
  }
} else {
  # --- Monitoreo continuo ------------------------------------------------------
  Write-Host (Seccion "MONITOREO CONTINUO")
  Write-Host (Texto "$gris  Revisando cada $IntervaloSeg s. Ctrl+C para cortar.$RST")
  Write-Host ""
  $previo = @{}
  $vuelta = 0
  while ($true) {
    $vuelta++
    $horaVuelta = Get-Date -Format "HH:mm:ss"
    Write-Host (Seccion "VUELTA $vuelta · $horaVuelta")
    Write-Host ""
    $pasada = Una-Pasada $listaIps $Puertos $miNet

    # Avisos de cambio de estado respecto a la vuelta anterior
    $huboCambios = $false
    foreach ($r in $pasada.ResumenIP) {
      $antes = $previo[$r.IP]
      if ($antes -and $antes -ne $r.Estado) {
        $huboCambios = $true
        $flecha = "$gris$antes$RST $gris→$RST $(Color-Estado $r.Estado)$BLD$($r.Estado)$RST"
        if ($r.Estado -eq "ONLINE" -and $antes -ne "ONLINE") {
          Write-Host "  $verde✔ $blanco$($r.IP)$RST volvio: $flecha $gris($horaVuelta)$RST"
        } elseif ($antes -eq "ONLINE" -and $r.Estado -ne "ONLINE") {
          Write-Host "  $rojo✖ $blanco$($r.IP)$RST se cayo: $flecha $gris($horaVuelta)$RST"
        } else {
          Write-Host "  $amar● $blanco$($r.IP)$RST cambio: $flecha $gris($horaVuelta)$RST"
        }
      }
      $previo[$r.IP] = $r.Estado
    }
    if ($huboCambios) { Write-Host "" }

    Write-Host (Fila "Resumen de esta vuelta" "$verde ON:$($pasada.Cont.ONLINE)$RST $rojo OFF:$($pasada.Cont.OFFLINE)$RST $amar TO:$($pasada.Cont.TIMEOUT)$RST $rojo ERR:$($pasada.Cont.ERROR)$RST")
    Write-Host ""

    if ($rutaTxt -or $rutaCsv) {
      Guardar-Reportes $rutaTxt $rutaCsv $(if($esRango){"rango $Desde a $Hasta (monitoreo, vuelta $vuelta)"}else{"servidor unico $Objetivo (monitoreo, vuelta $vuelta)"}) $listaIps $Puertos $miNet $pasada
    }
    Write-Host (Texto "$gris  Proxima vuelta en $IntervaloSeg s... (Ctrl+C para cortar)$RST")
    Write-Host ""
    Start-Sleep -Seconds $IntervaloSeg
  }
}
