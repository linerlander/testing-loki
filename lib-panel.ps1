<#
 lib-panel.ps1 · Estilo compartido, igual que el menu de LOKI.
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

# Logo LOKI exacto del menu (con sombra), degradado cyan -> lila por fila
function Banner { param($subtitulo = "")
  $logo = @(
    "██╗      █████╗ ██╗  ██╗██╗",
    "██║     ██╔══██╗██║ ██╔╝██║",
    "██║     ██║  ██║█████╔╝ ██║",
    "██║     ██║  ██║██╔═██╗ ██║",
    "███████╗╚█████╔╝██║  ██╗██║"
  )
  $grad = @("2ee6f0","57b6f6","8f9bf2","a78cf4","b98cff")
  Write-Host ""
  for ($fila=0; $fila -lt 5; $fila++) {
    $c = Color $grad[$fila]
    $linea = "   $c$B$($logo[$fila])$R"
    if ($fila -eq 2 -and $subtitulo) { $linea += "   $gris$subtitulo$R" }
    Write-Host $linea
  }
  Write-Host ""
}

$script:PW = 62
function New-Panel { param([int]$Ancho = 62) $script:PW = $Ancho }

# Seccion a todo el ancho, estilo LOKI:  ▌ TITULO ──────────
function Seccion { param($titulo, $colorHex = "2ee6f0")
  $c = Color $colorHex
  $rayas = $script:PW - 5 - $titulo.Length; if($rayas -lt 1){$rayas=1}
  "  $c▌$R $B$blanco$titulo$R $gris" + ("─"*$rayas) + "$R" }

# Fila con relleno de puntos:  etiqueta ········· valor
# Si no hay valor, se muestra como texto con sangria (sin puntos).
function Fila { param($etiqueta, $valor = "")
  if ([string]::IsNullOrEmpty($valor)) { return "    $etiqueta" }
  $pe = ($etiqueta -replace "$($script:ESC)\[[0-9;]*m","")
  $pv = ($valor    -replace "$($script:ESC)\[[0-9;]*m","")
  $pts = $script:PW - 6 - $pe.Length - $pv.Length; if($pts -lt 2){$pts=2}
  "    $blanco$etiqueta$R $gris" + ("·"*$pts) + "$R $valor" }

# Linea suelta con sangria (sin relleno)
function Texto { param($t) "    $t" }

function Pie { param($txt) Write-Host "  $gris$txt$R"; Write-Host "" }
