#!/bin/bash
# =============================================================================
#  lib-panel.sh · testing-loki — mismo estilo visual que LOKI (lib/ui.sh):
#  misma paleta, mismo logo, mismas cajas. Se carga con:  . lib-panel.sh
#  Corre igual en Windows (Git Bash), Termux (Android) y Linux: solo usa
#  bash y /dev/tcp, sin programas externos obligatorios.
# =============================================================================
ANCHO=${ANCHO:-78}

# ---- paleta (identica a lib/ui.sh de LOKI) -----------------------------------
C_P1="45;212;232"    # cian    · primario
C_P2="155;140;255"   # violeta · marca
C_OK="63;224;168"    # menta   · ON / exito
C_WARN="255;194;71"  # ambar   · aviso
C_ERR="255;95;109"   # coral   · OFF / error
C_INFO="95;168;255"  # azul    · dato
C_MUT="111;125;156"  # gris    · secundario
C_TXT="220;228;245"  # texto
C_BORDE="40;64;106"
C_CHIP="25;41;70"

E_RST=$'\e[0m'; E_BLD=$'\e[1m'
E_P1=$'\e[38;2;'"$C_P1"'m';     E_P2=$'\e[38;2;'"$C_P2"'m'
E_OK=$'\e[38;2;'"$C_OK"'m';     E_WARN=$'\e[38;2;'"$C_WARN"'m'
E_ERR=$'\e[38;2;'"$C_ERR"'m';   E_INFO=$'\e[38;2;'"$C_INFO"'m'
E_MUT=$'\e[38;2;'"$C_MUT"'m';   E_TXT=$'\e[38;2;'"$C_TXT"'m'
E_BOR=$'\e[38;2;'"$C_BORDE"'m'
B_CHIP=$'\e[48;2;'"$C_CHIP"'m'

pad()  { local s="$1" w="$2"; (( ${#s} > w )) && s="${s:0:w}"
         local n=$(( w - ${#s} )); printf '%s%*s' "$s" "$n" ''; }
rpad() { local s="$1" w="$2"; (( ${#s} > w )) && s="${s:0:w}"
         local n=$(( w - ${#s} )); printf '%*s%s' "$n" '' "$s"; }
rep()  { local i; for ((i=0;i<$2;i++)); do printf '%s' "$1"; done; }

# ---- el logo real de LOKI -----------------------------------------------------
logo() { # $1=subtitulo
  printf '\n'
  printf '  %s%s██╗      █████╗ ██╗  ██╗██╗%s\n'      "$E_BLD" "$E_P1" "$E_RST"
  printf '  %s%s██║     ██╔══██╗██║ ██╔╝██║%s\n'       "$E_BLD" "$E_P1" "$E_RST"
  printf '  %s%s██║     ██║  ██║█████╔╝ ██║%s   %s%s\n' "$E_BLD" "$E_P1" "$E_RST" "$E_MUT" "${1:-}"
  printf '  %s%s██║     ██║  ██║██╔═██╗ ██║%s\n'       "$E_BLD" "$E_P1" "$E_RST"
  printf '  %s%s███████╗╚█████╔╝██║  ██╗██║%s\n'      "$E_BLD" "$E_P2" "$E_RST"
  printf '  %s%s╚══════╝ ╚════╝ ╚═╝  ╚═╝╚═╝%s\n'      "$E_BLD" "$E_P2" "$E_RST"
  printf '\n'
}

# ---- titulo de seccion a todo lo ancho (igual a seccion() de LOKI) ----------
seccion() { # $1=titulo $2=color (variable E_xxx, por defecto E_P1)
  local c="${2:-$E_P1}"
  printf '  %s▌%s %s%s%s %s%s%s\n' "$c" "$E_RST" "$E_BLD" "$E_TXT" "$1" \
         "$E_MUT" "$(rep '─' $(( ANCHO - 5 - ${#1} )))" "$E_RST"
}

# ---- caja de ancho completo: caja_top / caja_fila / caja_bot ----------------
caja_top() { # $1=titulo $2=color de marco (opcional)
  local bi="${2:-$E_BOR}"
  printf '  %s╭─%s%s%s %s %s%s%s╮%s\n' "$bi" "$E_RST" "$B_CHIP$E_BLD" "${3:-$E_P1}" "$1" \
         "$E_RST$bi" "$(rep '─' $(( ANCHO - 7 - ${#1} )))" "$bi" "$E_RST"
}
caja_fila() { # $1=contenido ya formateado (con sus propios colores)
  printf '  %s│%s %s%s│%s\n' "$E_BOR" "$E_RST" "$1" "$(rep ' ' $(( ANCHO - 5 - $(largo_visible "$1") )))" "$E_BOR$E_RST"
}
caja_bot() { local bi="${1:-$E_BOR}"; printf '  %s╰%s╯%s\n' "$bi" "$(rep '─' $(( ANCHO - 4 )))" "$E_RST"; }

# ---- largo visible: descuenta los codigos de color para no desalinear -------
largo_visible() {
  local s="$1" sin
  sin=$(printf '%s' "$s" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  printf '%d' "${#sin}"
}

# ---- fila etiqueta · valor (ambos de ancho fijo, como la cabecera de LOKI) --
fila() { # $1=etiqueta $2=valor (ya coloreado)
  printf '  %s%s%s%s%s\n' "$E_MUT" "$(pad "$1" 22)" "$E_RST" "$2" "$E_RST"
}

reloj() { date '+%H:%M:%S'; }
fecha_hoy() { date '+%d %b %Y'; }
ahora_ms() { date +%s%3N 2>/dev/null || echo 0; }
