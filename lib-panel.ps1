<#
 lib-panel.ps1 · Estilo compartido de los paneles de testing-loki.
 Lo cargan los otros scripts con:  . "$PSScriptRoot\lib-panel.ps1"
#>
$OutputEncoding = [System.Text.Encoding]::UTF8
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:ESC = [char]27
function Color { param($hex)
  $r=[convert]::ToInt32($hex.Substring(0,2),16);$g=[convert]::ToInt32($hex.Substring(2,2),16);$b=[convert]::ToInt32($hex.Substring(4,2),16)
  "$($script:ESC)[38;2;$r;$g;${b}m" }

$R    = "$($script:ESC)[0m"
$B    = "$($script:ESC)[1m"
$verde  = Color "39ff78"
$cyan   = Color "2ee6f0"
$lila   = Color "b98cff"
$gris   = Color "5f6b64"
$rojo   = Color "ff5b5b"
$amar   = Color "ffc23b"
$blanco = Color "e8fff0"

# Logo grande LOKI con degradado por letra (cyan -> lila), estilo marca LOKI
function Banner { param($subtitulo = "")
  $cL = Color "2ee6f0"; $cO = Color "5aa6ff"; $cK = Color "8f84ee"; $cI = Color "b98cff"
  $letraL = @("██    ","██    ","██    ","██    ","██████")
  $letraO = @("██████","██  ██","██  ██","██  ██","██████")
  $letraK = @("██  ██","██ ██ ","████  ","██ ██ ","██  ██")
  $letraI = @("██████"," ██   "," ██   "," ██   ","██████")
  Write-Host ""
  for ($fila=0; $fila -lt 5; $fila++) {
    $linea = "  $cL$B$($letraL[$fila])$R  $cO$B$($letraO[$fila])$R  $cK$B$($letraK[$fila])$R  $cI$B$($letraI[$fila])$R"
    if ($fila -eq 2 -and $subtitulo) { $linea += "    $gris$subtitulo$R" }
    Write-Host $linea
  }
  Write-Host "  $gris┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄$R  $lila testing-loki$R"
  Write-Host ""
}

# Cajas
function New-Panel { param([int]$Ancho = 62) $script:PW = $Ancho }
function PanelTop  { param($t)
  $resto = $script:PW - 4 - $t.Length; if($resto -lt 1){$resto=1}
  "$cyan╭─ $B$blanco$t$R $cyan" + ("─"*$resto) + "╮$R" }
function PanelRow  { param($izq, $der = "")
  $pi = ($izq -replace "$($script:ESC)\[[0-9;]*m","")
  $pd = ($der -replace "$($script:ESC)\[[0-9;]*m","")
  $esp = $script:PW - 3 - $pi.Length - $pd.Length; if($esp -lt 1){$esp=1}
  "$cyan│$R $izq" + (" "*$esp) + "$der $cyan│$R" }
# Fila estilo LOKI: etiqueta ····· valor (puntos de relleno)
function PanelTabla { param($etiqueta, $valor)
  $pe = ($etiqueta -replace "$($script:ESC)\[[0-9;]*m","")
  $pv = ($valor    -replace "$($script:ESC)\[[0-9;]*m","")
  $pts = $script:PW - 5 - $pe.Length - $pv.Length; if($pts -lt 2){$pts=2}
  "$cyan│$R $blanco$etiqueta$R $gris" + ("·"*$pts) + "$R $valor $cyan│$R" }
function PanelSep  { "$cyan├" + ("─"*($script:PW-2)) + "┤$R" }
function PanelBot  { "$cyan╰" + ("─"*($script:PW-2)) + "╯$R" }

function Pie { param($txt) Write-Host "$gris  $txt$R"; Write-Host "" }

New-Panel 62
