#!/bin/bash
# =============================================================================
#  diagnostico.sh · testing-loki — diagnostico de conectividad, estilo LOKI
#
#  Corre igual en Windows (Git Bash), Termux (Android) y Linux: solo usa
#  bash y /dev/tcp (nativo), sin nmap/nc/python obligatorios. openssl es
#  opcional (solo hace falta para revisar puertos HTTPS).
#
#  USO:
#    bash diagnostico.sh              (menu de opciones interactivo)
#
#  Solo servidores/rangos TUYOS o con autorizacion expresa. Un bloque
#  compartido con otros clientes de tu proveedor NO queda autorizado por
#  ser dueno de una sola IP de ese bloque (se explica en el propio menu).
# =============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-panel.sh"

TMP="${TMPDIR:-/tmp}"
mkdir -p "$TMP" 2>/dev/null

# 'timeout' viene en coreutils (en Termux: pkg install coreutils)
if ! command -v timeout >/dev/null 2>&1; then
  printf '\n  %s✖ Falta el comando timeout.%s\n  %sEn Termux:%s pkg install coreutils\n\n' "$E_ERR" "$E_RST" "$E_MUT" "$E_RST"
  exit 1
fi

# ---- validar una IP (4 octetos 0-255) ---------------------------------------
ip_valida() {
  local ip="$1" IFS=.
  local -a o
  read -ra o <<< "$ip"
  [ "${#o[@]}" -eq 4 ] || return 1
  local x
  for x in "${o[@]}"; do
    [[ "$x" =~ ^[0-9]{1,3}$ ]] || return 1
    (( x <= 255 )) || return 1
  done
  return 0
}
ip_a_num() { local IFS=.; local -a o; read -ra o <<< "$1"; echo $(( (o[0]<<24) | (o[1]<<16) | (o[2]<<8) | o[3] )); }
num_a_ip() { local n="$1"; echo "$(( (n>>24)&255 )).$(( (n>>16)&255 )).$(( (n>>8)&255 )).$(( n&255 ))"; }

# ---- probar un puerto TCP por /dev/tcp (nativo de bash, sin dependencias) --
PUERTO_ESTADO=""; PUERTO_MS=0
puerto_test() { # $1=ip $2=puerto $3=timeout_seg
  local t0 t1 rc
  t0=$(ahora_ms)
  # rc 0 = abierto · 124 = timeout lo corto · otro = el host dijo "cerrado"
  timeout "$3" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
  rc=$?
  t1=$(ahora_ms)
  PUERTO_MS=$(( t1 - t0 ))
  if [ "$rc" -eq 0 ]; then PUERTO_ESTADO="abierto"
  elif [ "$rc" -eq 124 ]; then PUERTO_ESTADO="timeout"
  else PUERTO_ESTADO="rechazado"
  fi
}

# ---- ping opcional (mejor esfuerzo: en Linux/Termux da dato real; en   -----
# ---- Windows ping.exe no entiende las opciones y se ignora solo) -----------
PING_ESTADO="sin_dato"; PING_MS=0
ping_test() {
  PING_ESTADO="sin_dato"; PING_MS=0
  command -v ping >/dev/null 2>&1 || return
  local salida rc t0 t1
  t0=$(ahora_ms)
  salida=$(timeout 3 ping -c 1 -W 2 "$1" 2>&1); rc=$?
  t1=$(ahora_ms)
  if [ $rc -eq 0 ]; then PING_ESTADO="ok"; PING_MS=$(( t1 - t0 ))
  elif printf '%s' "$salida" | grep -qi "unreachable"; then PING_ESTADO="rechazado"
  fi
}

# ---- probar HTTP/HTTPS cuando el puerto esta abierto -----------------------
HTTP_CODIGO=0
http_test() { # $1=ip $2=puerto $3=http|https
  HTTP_CODIGO=0
  local treq tresp
  treq=$(mktemp "$TMP/loki_req.XXXXXX" 2>/dev/null) || treq="$TMP/loki_req_$$"
  tresp=$(mktemp "$TMP/loki_resp.XXXXXX" 2>/dev/null) || tresp="$TMP/loki_resp_$$"
  printf 'HEAD / HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n' "$1" > "$treq"
  if [ "$3" = "https" ]; then
    if command -v openssl >/dev/null 2>&1; then
      timeout 6 openssl s_client -quiet -connect "$1:$2" < "$treq" > "$tresp" 2>/dev/null
    fi
  else
    timeout 6 bash -c "exec 5<>'/dev/tcp/$1/$2' && cat '$treq' >&5 && timeout 4 cat <&5" > "$tresp" 2>/dev/null
  fi
  HTTP_CODIGO=$(head -1 "$tresp" 2>/dev/null | grep -oE ' [0-9]{3} ' | tr -d ' ')
  [ -z "$HTTP_CODIGO" ] && HTTP_CODIGO=0
  rm -f "$treq" "$tresp"
}

# ---- clasificar una IP en ONLINE / OFFLINE / TIMEOUT / ERROR ---------------
clasificar() { # $1=ping_estado $2="estado1 estado2 ..." (de cada puerto)
  local pe="$1" pts="$2"
  if printf '%s' "$pts" | grep -qw abierto; then echo "ONLINE"; return; fi
  if printf '%s' "$pts" | grep -qw rechazado; then echo "ONLINE"; return; fi
  [ "$pe" = "ok" ] && { echo "ONLINE"; return; }
  [ "$pe" = "rechazado" ] && { echo "OFFLINE"; return; }
  if printf '%s' "$pts" | grep -qw timeout; then echo "TIMEOUT"; return; fi
  echo "ERROR"
}
color_estado() { case "$1" in ONLINE) echo "$E_OK";; OFFLINE) echo "$E_ERR";; TIMEOUT) echo "$E_WARN";; *) echo "$E_ERR";; esac; }

# ============================================================= OPCIONES =====
clear
logo "diagnostico de conectividad"

seccion "OPCIONES" "$E_P2"
printf '\n'
printf '  %s1%s · IP unica\n' "${E_BLD}${E_P1}" "$E_RST"
printf '  %s2%s · Rango de IP\n\n' "${E_BLD}${E_P1}" "$E_RST"
read -rp "  $(printf "%sElegi (1 o 2):%s " "$E_TXT" "$E_RST")" MODO
[ "$MODO" = "2" ] && ES_RANGO=1 || ES_RANGO=0

IPS=()
if [ "$ES_RANGO" -eq 0 ]; then
  read -rp "  $(printf "%sIP objetivo:%s " "$E_TXT" "$E_RST")" OBJETIVO
  if ! ip_valida "$OBJETIVO"; then
    printf '\n  %s✖ Esa IP no es valida.%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
  IPS=("$OBJETIVO")
else
  read -rp "  $(printf "%sDesde:%s " "$E_TXT" "$E_RST")" DESDE
  read -rp "  $(printf "%sHasta:%s " "$E_TXT" "$E_RST")" HASTA
  if ! ip_valida "$DESDE" || ! ip_valida "$HASTA"; then
    printf '\n  %s✖ Desde/Hasta no son IP validas.%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
  ND=$(ip_a_num "$DESDE"); NH=$(ip_a_num "$HASTA")
  if [ "$NH" -lt "$ND" ]; then
    printf '\n  %s✖ Hasta tiene que ser igual o mayor que Desde.%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
  TOTAL=$(( NH - ND + 1 ))
  if [ "$TOTAL" -gt 64 ]; then
    printf '\n  %s✖ Ese rango tiene %s direcciones: el tope por corrida es 64.%s\n\n' "$E_ERR" "$TOTAL" "$E_RST"; exit 1
  fi
  for ((n=ND; n<=NH; n++)); do IPS+=("$(num_a_ip "$n")"); done
fi

read -rp "  $(printf "%sPuertos separados por coma [22,80,443,3306]:%s " "$E_TXT" "$E_RST")" PUERTOS_TXT
PUERTOS_TXT="${PUERTOS_TXT:-22,80,443,3306}"
IFS=',' read -ra PUERTOS <<< "$PUERTOS_TXT"
for p in "${PUERTOS[@]}"; do
  p="$(echo "$p" | tr -d ' ')"
  if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
    printf '\n  %s✖ Puerto invalido: %s%s\n\n' "$E_ERR" "$p" "$E_RST"; exit 1
  fi
done

read -rp "  $(printf "%sMonitoreo continuo? (s/N):%s " "$E_TXT" "$E_RST")" MON
INTERVALO=30
if [[ "$MON" =~ ^[sS]$ ]]; then
  MONITOREO=1
  read -rp "  $(printf "%sIntervalo en segundos [30]:%s " "$E_TXT" "$E_RST")" INTERVALO_IN
  INTERVALO="${INTERVALO_IN:-30}"
  if ! [[ "$INTERVALO" =~ ^[0-9]+$ ]] || [ "$INTERVALO" -lt 3 ]; then
    printf '\n  %s✖ El intervalo tiene que ser un numero (minimo 3).%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
else
  MONITOREO=0
fi

read -rp "  $(printf "%sGuardar reporte TXT y CSV? (S/n):%s " "$E_TXT" "$E_RST")" REP
[[ "$REP" =~ ^[nN]$ ]] && GUARDAR=0 || GUARDAR=1
CARPETA="$DIR/reportes"

printf '\n'
caja_top "AUTORIZACION" "$E_WARN"
caja_fila "$(printf '%sCada IP (o cada IP del rango) tiene que ser tuya%s' "$E_TXT" "$E_RST")"
caja_fila "$(printf '%so estar autorizada. Un bloque compartido con otros%s' "$E_TXT" "$E_RST")"
caja_fila "$(printf '%sclientes de tu proveedor NO queda autorizado por ser%s' "$E_TXT" "$E_RST")"
caja_fila "$(printf '%sdueno de una sola IP de ese bloque.%s' "$E_TXT" "$E_RST")"
caja_bot "$E_WARN"
printf '\n'
read -rp "  $(printf "%sEscribi 'si' si es tuyo/autorizado:%s " "$E_TXT" "$E_RST")" OK1
if [ "$OK1" != "si" ]; then printf '\n  %s✖ Cancelado.%s\n\n' "$E_ERR" "$E_RST"; exit 1; fi
if [ "$ES_RANGO" -eq 1 ]; then
  read -rp "  $(printf "%sConfirma: escribi el total de IP (%s):%s " "$E_TXT" "${#IPS[@]}" "$E_RST")" OK2
  if [ "$OK2" != "${#IPS[@]}" ]; then printf '\n  %s✖ Cancelado: no coincide.%s\n\n' "$E_ERR" "$E_RST"; exit 1; fi
fi

# ============================================================== REPORTES ====
RUTA_TXT=""; RUTA_CSV=""
if [ "$GUARDAR" -eq 1 ]; then
  mkdir -p "$CARPETA" 2>/dev/null
  SELLO="$(date '+%Y%m%d-%H%M%S')"
  RUTA_TXT="$CARPETA/diagnostico-$SELLO.txt"
  RUTA_CSV="$CARPETA/diagnostico-$SELLO.csv"
  echo "IP,Estado,PingMs,Puertos,Http,Hora" > "$RUTA_CSV"
  { echo "DIAGNOSTICO - testing-loki"; echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')"; echo; } > "$RUTA_TXT"
fi

# ============================================================ UNA PASADA ====
declare -A ESTADO_PREVIO
CONT_ON=0; CONT_OFF=0; CONT_TO=0; CONT_ERR=0

pasada() {
  CONT_ON=0; CONT_OFF=0; CONT_TO=0; CONT_ERR=0
  local total="${#IPS[@]}" idx=0 ip
  local t_inicio; t_inicio=$(ahora_ms)

  for ip in "${IPS[@]}"; do
    idx=$((idx+1))
    printf '  %s▸ [%d/%d] %s%s%s\n' "$E_P2" "$idx" "$total" "$E_BLD$E_TXT" "$ip" "$E_RST"

    ping_test "$ip"
    local estados_puertos="" abiertos="" http_txt="—"
    for p in "${PUERTOS[@]}"; do
      p="$(echo "$p" | tr -d ' ')"
      puerto_test "$ip" "$p" 3
      estados_puertos="$estados_puertos $PUERTO_ESTADO"
      if [ "$PUERTO_ESTADO" = "abierto" ]; then
        abiertos="${abiertos:+$abiertos, }$p"
        case "$p" in
          80|8080) http_test "$ip" "$p" "http"; http_txt="$HTTP_CODIGO" ;;
          443|8443) http_test "$ip" "$p" "https"; http_txt="$HTTP_CODIGO" ;;
        esac
        printf '      %s:%s%s %s● abierto%s %s· %sms%s\n' "$E_MUT" "$p" "$E_RST" "$E_OK" "$E_RST" "$E_MUT" "$PUERTO_MS" "$E_RST"
      elif [ "$PUERTO_ESTADO" = "rechazado" ]; then
        printf '      %s:%s%s %s● cerrado (el host contesto)%s\n' "$E_MUT" "$p" "$E_RST" "$E_WARN" "$E_RST"
      else
        printf '      %s:%s%s %s○ sin respuesta (timeout)%s\n' "$E_MUT" "$p" "$E_RST" "$E_MUT" "$E_RST"
      fi
    done
    [ -z "$abiertos" ] && abiertos="—"

    local estado; estado=$(clasificar "$PING_ESTADO" "$estados_puertos")
    local c; c=$(color_estado "$estado")
    printf '      %sESTADO%s %s%s%s%s\n\n' "$E_MUT" "$E_RST" "$E_BLD" "$c" "$estado" "$E_RST"

    case "$estado" in
      ONLINE)  CONT_ON=$((CONT_ON+1));;
      OFFLINE) CONT_OFF=$((CONT_OFF+1));;
      TIMEOUT) CONT_TO=$((CONT_TO+1));;
      *)       CONT_ERR=$((CONT_ERR+1));;
    esac

    if [ -n "${ESTADO_PREVIO[$ip]:-}" ] && [ "${ESTADO_PREVIO[$ip]}" != "$estado" ]; then
      if [ "$estado" = "ONLINE" ]; then
        printf '  %s✔ %s%s%s volvio (%s -> ONLINE)%s\n\n' "$E_OK" "$E_BLD" "$ip" "$E_RST$E_OK" "${ESTADO_PREVIO[$ip]}" "$E_RST"
      elif [ "${ESTADO_PREVIO[$ip]}" = "ONLINE" ]; then
        printf '  %s✖ %s%s%s se cayo (ONLINE -> %s)%s\n\n' "$E_ERR" "$E_BLD" "$ip" "$E_RST$E_ERR" "$estado" "$E_RST"
      fi
    fi
    ESTADO_PREVIO[$ip]="$estado"

    if [ "$GUARDAR" -eq 1 ]; then
      echo "$ip,$estado,$PING_MS,\"$abiertos\",$http_txt,$(date '+%H:%M:%S')" >> "$RUTA_CSV"
      echo "$ip | $estado | ping ${PING_MS}ms | puertos: $abiertos | http: $http_txt" >> "$RUTA_TXT"
    fi
  done

  local t_fin; t_fin=$(ahora_ms)
  local dur_s=$(( (t_fin - t_inicio) / 1000 ))
  seccion "RESUMEN · $(reloj)" "$E_P1"
  printf '\n'
  fila "total revisadas" "${E_TXT}${total}${E_RST}"
  fila "online"  "${E_OK}${CONT_ON}${E_RST}"
  fila "offline" "${E_ERR}${CONT_OFF}${E_RST}"
  fila "timeout" "${E_WARN}${CONT_TO}${E_RST}"
  fila "error"   "${E_ERR}${CONT_ERR}${E_RST}"
  fila "duracion" "${E_TXT}${dur_s} s${E_RST}"
  printf '\n'
}

# ========================================================= CTRL+C LIMPIO ====
CORTADO=0
trap 'CORTADO=1; printf "\n  %s✖ Cortado por el usuario. Lo ya escaneado queda arriba.%s\n\n" "$E_WARN" "$E_RST"; [ -n "$RUTA_TXT" ] && printf "  %s📄 TXT:%s %s\n  %s📄 CSV:%s %s\n\n" "$E_MUT" "$E_RST" "$RUTA_TXT" "$E_MUT" "$E_RST" "$RUTA_CSV"; exit 130' INT

# ================================================================ MAIN ======
VUELTA=0
if [ "$MONITOREO" -eq 0 ]; then
  printf '\n'
  seccion "ESCANEANDO (${#IPS[@]} IP)" "$E_INFO"
  printf '\n'
  pasada
else
  printf '\n  %s↻ Monitoreo cada %s s. Ctrl+C para cortar.%s\n' "$E_INFO" "$INTERVALO" "$E_RST"
  while [ "$CORTADO" -eq 0 ]; do
    VUELTA=$((VUELTA+1))
    printf '\n'
    seccion "VUELTA $VUELTA · $(reloj)" "$E_INFO"
    printf '\n'
    pasada
    printf '  %sProxima vuelta en %s s... (Ctrl+C para cortar)%s\n' "$E_MUT" "$INTERVALO" "$E_RST"
    sleep "$INTERVALO"
  done
fi

if [ "$GUARDAR" -eq 1 ] && [ "$CORTADO" -eq 0 ]; then
  printf '  %s📄 TXT:%s %s\n  %s📄 CSV:%s %s\n\n' "$E_MUT" "$E_RST" "$RUTA_TXT" "$E_MUT" "$E_RST" "$RUTA_CSV"
fi
printf '  %ssolo IP propias o autorizadas%s\n\n' "$E_MUT" "$E_RST"
