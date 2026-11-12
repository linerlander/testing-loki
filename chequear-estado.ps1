param(
  [string[]]$Objetivos
)

# ---- EDITA AQUI tu lista fija (se usa si no pasas -Objetivos) ---------------
$LISTA = @(
  "lic.linerlander.space"
  # "190.183.229.172:80"
  # "190.183.229.172:443"
  # "mi-otro-vps.com"
)
# ----------------------------------------------------------------------------


if (-not $Objetivos -or $Objetivos.Count -eq 0) { $Objetivos = $LISTA }

. "$PSScriptRoot\lib-panel.ps1"

Banner "estado de servidores"

New-Panel 62

function Prueba-Puerto { param($h,$p)
  try {
    $c=New-Object System.Net.Sockets.TcpClient
    $iar=$c.BeginConnect($h,$p,$null,$null)
    $okw=$iar.AsyncWaitHandle.WaitOne(4000,$false)
    if($okw -and $c.Connected){$c.Close();return $true}
    $c.Close();return $false
  } catch { return $false }
}

function Prueba-HTTP { param($url)
  try {
    $resp=Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 8 -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Stop
    return [int]$resp.StatusCode
  } catch {
    if($_.Exception.Response){ try { return [int]$_.Exception.Response.StatusCode } catch {} }
    return 0
  }
}

function Texto-Status { param($code)
  switch ($code) {
    200 {"$verde● 200 OK$R"; break}
    {$_ -in 301,302,307,308} {"$cyan● $code redirige$R"; break}
    403 {"$amar● 403 prohibido$R"; break}
    404 {"$amar● 404 no existe$R"; break}
    {$_ -ge 500} {"$rojo● $code caido$R"; break}
    0   {"$rojo● sin respuesta$R"; break}
    default {"$blanco● $code$R"}
  }
}

$hora=Get-Date -Format "HH:mm"
Write-Host (PanelTop "ESTADO DE SERVIDORES · $hora")

foreach ($o in $Objetivos) {
  $o=$o.Trim(); if(-not $o){continue}
  if ($o -match ':(\d+)$') {
    # host:puerto -> prueba TCP y, si es web, el status
    $h=$o.Substring(0,$o.LastIndexOf(':')); $p=[int]$Matches[1]
    $conecta = Prueba-Puerto $h $p
    if (-not $conecta) {
      Write-Host (PanelTabla "$o" "$rojo● no conecta$R")
    } elseif ($p -in 80,8080) {
      $st=Prueba-HTTP "http://$h`:$p"; Write-Host (PanelTabla "$o" (Texto-Status $st))
    } elseif ($p -in 443,8443) {
      $st=Prueba-HTTP "https://$h`:$p"; Write-Host (PanelTabla "$o" (Texto-Status $st))
    } else {
      Write-Host (PanelTabla "$o" "$verde● conecta$R")
    }
  } else {
    # solo dominio -> prueba HTTP y HTTPS
    $st80 =Prueba-HTTP "http://$o"
    $st443=Prueba-HTTP "https://$o"
    Write-Host (PanelRow "$lila▸ $blanco$o$R")
    Write-Host (PanelTabla "  :80  http" (Texto-Status $st80))
    Write-Host (PanelTabla "  :443 https" (Texto-Status $st443))
  }
}
Write-Host (PanelBot)
Write-Host ""
Write-Host "$gris  200 = responde bien · solo servidores propios$R"
Write-Host ""

