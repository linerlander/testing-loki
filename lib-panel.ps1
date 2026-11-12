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
$verde2 = Color "2ee6f0"
$cyan   = Color "2ee6f0"
$lila   = Color "b98cff"
$gris   = Color "6f7b74"
$rojo   = Color "ff5b5b"
$amar   = Color "ffc23b"
$blanco = Color "e8fff0"

# Letras de LOKI en 3 colores (degradado cyan -> lila), estilo marca
function Banner { param($subtitulo = "")
  $g1 = Color "2ee6f0"; $g2 = Color "6fb0ff"; $g3 = Color "b98cff"
  Write-Host ""
  Write-Host "  $g1$B█▀▀$R $g2$B█▀█$R $g2$B█ █$R $g3$B█$R    $gris┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄$R"
  Write-Host "  $g1$B█▄▄$R $g2$B█▄█$R $g2$B█▀▄$R $g3$B█$R    $blanco$B·$R $gris testing-loki$R"
  if ($subtitulo) { Write-Host "  $gris$subtitulo$R" }
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
function PanelSep  { "$cyan├" + ("─"*($script:PW-2)) + "┤$R" }
function PanelBot  { "$cyan╰" + ("─"*($script:PW-2)) + "╯$R" }

function Pie { param($txt) Write-Host "$gris  $txt$R"; Write-Host "" }

New-Panel 62
