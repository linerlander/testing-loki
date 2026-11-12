<#
=============================================================================
 chequear-estado.ps1  ·  Panel de estado de TUS servidores
 Prueba, para cada objetivo: si el puerto conecta y que codigo HTTP devuelve.

 USO:
   .\chequear-estado.ps1                         (usa la lista de abajo)
   .\chequear-estado.ps1 -Objetivos "mi.web.com","1.2.3.4:443"

 Formato de cada objetivo:
   dominio.com            -> prueba HTTP (80) y HTTPS (443)
   dominio.com:8080       -> prueba solo ese puerto
   1.2.3.4:22             -> prueba si ese puerto conecta (TCP)

 Solo servidores TUYOS o con autorizacion.
=============================================================================
#>
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

$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ESC=[char]27
function C { param($hex)
  $r=[convert]::ToInt32($hex.Substring(0,2),16);$g=[convert]::ToInt32($hex.Substring(2,2),16);$b=[convert]::ToInt32($hex.Substring(4,2),16)
  "$ESC[38;2;$r;$g;${b}m" }
$R="$ESC[0m";$B="$ESC[1m"
$verde=C "39ff78";$cyan=C "2ee6f0";$gris=C "6f7b74";$rojo=C "ff5b5b";$amar=C "ffc23b";$blanco=C "e8fff0"

$W=62
function Top { param($t) $resto=$W-4-$t.Length; "$cyan╭─ $B$blanco$t$R $cyan"+("─"*$resto)+"╮$R" }
function Ln  { param($izq,$der="")
  $pi=($izq -replace "$ESC\[[0-9;]*m","");$pd=($der -replace "$ESC\[[0-9;]*m","")
  $esp=$W-3-$pi.Length-$pd.Length; if($esp -lt 1){$esp=1}
  "$cyan│$R $izq"+(" "*$esp)+"$der $cyan│$R" }
function Bot { "$cyan╰"+("─"*($W-2))+"╯$R" }

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
    {$_ -in 301,302,307,308} {"$cyan↪ $code redirige$R"; break}
    403 {"$amar🔒 403 prohibido$R"; break}
    404 {"$amar? 404 no existe$R"; break}
    {$_ -ge 500} {"$rojo⚠ $code caido$R"; break}
    0   {"$rojo✖ sin respuesta$R"; break}
    default {"$blanco$code$R"}
  }
}

Clear-Host
Write-Host ""
Write-Host "$verde$B   ██       ██████  ██   ██ ██ $R   $gris testing-loki · estado$R"
Write-Host "$verde$B   ███████  ██████  ██   ██ ██ $R"
Write-Host ""
$hora=Get-Date -Format "HH:mm"
Write-Host (Top "ESTADO DE SERVIDORES · $hora")

foreach ($o in $Objetivos) {
  $o=$o.Trim(); if(-not $o){continue}
  if ($o -match ':(\d+)$') {
    # host:puerto -> prueba TCP y, si es web, el status
    $h=$o.Substring(0,$o.LastIndexOf(':')); $p=[int]$Matches[1]
    $conecta = Prueba-Puerto $h $p
    if (-not $conecta) {
      Write-Host (Ln "$blanco$o$R" "$rojo✖ no conecta$R")
    } elseif ($p -in 80,8080) {
      $st=Prueba-HTTP "http://$h`:$p"; Write-Host (Ln "$blanco$o$R" (Texto-Status $st))
    } elseif ($p -in 443,8443) {
      $st=Prueba-HTTP "https://$h`:$p"; Write-Host (Ln "$blanco$o$R" (Texto-Status $st))
    } else {
      Write-Host (Ln "$blanco$o$R" "$verde● conecta (TCP)$R")
    }
  } else {
    # solo dominio -> prueba HTTP y HTTPS
    $st80 =Prueba-HTTP "http://$o"
    $st443=Prueba-HTTP "https://$o"
    Write-Host (Ln "$blanco$o$R")
    Write-Host (Ln "$gris   :80  http $R" (Texto-Status $st80))
    Write-Host (Ln "$gris   :443 https$R" (Texto-Status $st443))
  }
}
Write-Host (Bot)
Write-Host ""
Write-Host "$gris  200 = responde bien · ✖ = no conecta · solo servidores propios$R"
Write-Host ""
