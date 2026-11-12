<#
=============================================================================
 auditar-vps.ps1  ·  Revisa UN VPS TUYO desde Windows (PowerShell).
 Qué puertos tiene abiertos, qué servicios corren y avisos de seguridad.

 USO:   .\auditar-vps.ps1 -Objetivo <IP_O_DOMINIO_TUYO>
 Ej:    .\auditar-vps.ps1 -Objetivo 190.183.229.172

 Necesita nmap para Windows:  winget install Insecure.Nmap

 ADVERTENCIA: Solo sobre servidores TUYOS o con autorizacion expresa.
 Escanear sistemas de terceros sin permiso es ilegal.
=============================================================================
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Objetivo
)

function Linea { param($c) Write-Host $c }

Linea ""
Write-Host "Auditoria de: $Objetivo" -ForegroundColor White
Write-Host "--------------------------------------------" -ForegroundColor DarkGray

# 1) Candado de autorizacion ---------------------------------------------------
Write-Host "Este servidor es TUYO o te autorizaron a escanearlo?" -ForegroundColor Yellow
$ok = Read-Host "   Escribi 'si' para continuar"
if ($ok -ne "si") {
  Write-Host "Cancelado. Solo se escanean servidores propios." -ForegroundColor Red
  exit 1
}
Linea ""

# 2) Verificar nmap ------------------------------------------------------------
$nmap = Get-Command nmap -ErrorAction SilentlyContinue
if (-not $nmap) {
  Write-Host "Falta nmap. Instalalo con:" -ForegroundColor Yellow
  Write-Host "   winget install Insecure.Nmap" -ForegroundColor White
  Write-Host "Despues cerra y abri PowerShell y volve a correr." -ForegroundColor Yellow
  exit 1
}

# 3) Esta vivo? ----------------------------------------------------------------
Write-Host "1) Responde el servidor?" -ForegroundColor White
if (Test-Connection -ComputerName $Objetivo -Count 1 -Quiet -ErrorAction SilentlyContinue) {
  Write-Host "   OK - Responde al ping" -ForegroundColor Green
} else {
  Write-Host "   Aviso - No responde al ping (normal: muchos VPS lo bloquean)." -ForegroundColor Yellow
}
Linea ""

# 4) Escaneo de puertos y servicios -------------------------------------------
Write-Host "2) Puertos abiertos y servicios (puede tardar 1-2 min)..." -ForegroundColor White
$salida = & nmap -sV -T4 -Pn $Objetivo 2>$null
$texto = $salida -join "`n"

$salida | Select-String -Pattern '^\d+/(tcp|udp)\s+open' | ForEach-Object {
  $campos = ($_ -replace '\s+', ' ').Trim().Split(' ')
  $puerto  = $campos[0]
  $serv    = $campos[2]
  $vers    = ($campos[3..($campos.Length-1)] -join ' ')
  "{0,-10} {1,-12} {2}" -f $puerto, $serv, $vers | Write-Host -ForegroundColor Green
}
Linea ""

# 5) Avisos de seguridad -------------------------------------------------------
Write-Host "3) Avisos:" -ForegroundColor White
$avisos = 0
function Chk { param($p) return ($texto -match $p) }

if (Chk '23/tcp\s+open')   { Write-Host "   X  Telnet (23) abierto: inseguro, cerralo." -ForegroundColor Red; $avisos++ }
if (Chk '21/tcp\s+open')   { Write-Host "   !  FTP (21) abierto: usa SFTP en su lugar." -ForegroundColor Yellow; $avisos++ }
if (Chk '3306/tcp\s+open') { Write-Host "   X  MySQL (3306) expuesto a internet: limitalo al VPS." -ForegroundColor Red; $avisos++ }
if (Chk '6379/tcp\s+open') { Write-Host "   X  Redis (6379) expuesto: muy peligroso, cerralo." -ForegroundColor Red; $avisos++ }
if (Chk '5432/tcp\s+open') { Write-Host "   !  PostgreSQL (5432) expuesto: limitalo al VPS." -ForegroundColor Yellow; $avisos++ }
if (Chk '22/tcp\s+open')   { Write-Host "   i  SSH (22) en el puerto por defecto: considera cambiarlo." -ForegroundColor DarkGray }

if ($avisos -eq 0) { Write-Host "   OK - Sin alertas graves." -ForegroundColor Green }
Linea ""
Write-Host "Listo. Guarda la salida para comparar mas adelante." -ForegroundColor DarkGray
