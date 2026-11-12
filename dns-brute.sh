#!/bin/bash
# =============================================================================
#  dns-brute.sh · testing-loki — DNS BRUTE FORCE DISCOVERY
#
#  Descubre subdominios de UN DOMINIO TUYO (o autorizado) probando un
#  diccionario de palabras. Resuelve A/AAAA/CNAME, detecta wildcard DNS
#  (para marcar falsos positivos) y corre varias consultas en paralelo.
#
#  Modulo independiente: no toca diagnostico.sh, auditar-rango.sh ni nada
#  mas del repo. Solo LEE lib-panel.sh para el mismo estilo visual.
#
#  USO:
#    bash dns-brute.sh
#
#  Necesita UNO de estos resolutores DNS (se detecta solo, en este orden):
#    dig > host > getent > nslookup
#  En Termux, si falta: pkg install dnsutils
#  nslookup viene de fabrica en Windows; es el que usa Git Bash si no
#  instalaste dig/host/getent.
#
#  Solo sobre dominios TUYOS o con autorizacion expresa para pruebas
#  activas. Esto SI genera trafico real de DNS contra el dominio.
# =============================================================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-panel.sh"

TMP="${TMPDIR:-/tmp}/dns-brute-$$"
mkdir -p "$TMP" 2>/dev/null

if ! command -v timeout >/dev/null 2>&1; then
  printf '\n  %s✖ Falta el comando timeout.%s\n  %sEn Termux:%s pkg install coreutils\n\n' "$E_ERR" "$E_RST" "$E_MUT" "$E_RST"
  exit 1
fi

# ---- diccionario por defecto (sin internet, offline) ------------------------
PALABRAS_DEFECTO=(
  www mail ftp admin api dev test staging vpn ssh portal webmail
  ns1 ns2 ns3 mx mx1 mx2 smtp pop imap blog shop store app cdn
  static assets img images media files download docs support help
  status monitor grafana kibana git gitlab jenkins ci cd db mysql
  redis cache old new beta alpha demo sandbox qa uat prod produccion
  internal intranet extranet remote office corp secure login auth sso
  id accounts billing pay m mobile wap cp cpanel whm plesk direct
  webdisk autodiscover autoconfig panel oficina licencias bot
)

# ---- detectar que herramienta de DNS hay disponible ------------------------
RESOLVER=""
if command -v dig >/dev/null 2>&1; then RESOLVER="dig"
elif command -v host >/dev/null 2>&1; then RESOLVER="host"
elif command -v getent >/dev/null 2>&1; then RESOLVER="getent"
elif command -v nslookup >/dev/null 2>&1; then RESOLVER="nslookup"
fi
if [ -z "$RESOLVER" ]; then
  printf '\n  %s✖ No encontre dig, host, getent ni nslookup.%s\n' "$E_ERR" "$E_RST"
  printf '  %sEn Termux:%s pkg install dnsutils\n\n' "$E_MUT" "$E_RST"
  exit 1
fi

# ---- resolver un nombre -> RES_IPS (coma-separado) y RES_CNAME -------------
# RES_ERROR=1 cuando la herramienta no contesto NADA (timeout/sin red): eso
# es un ERROR de la consulta, distinto de "ese nombre no existe" (NXDOMAIN).
TIMEOUT_DNS=8
resolver_fqdn() { # $1=fqdn -> rc 0 si resolvio algo
  RES_IPS=""; RES_CNAME=""; RES_ERROR=0
  case "$RESOLVER" in
    dig)
      local salida; salida=$(timeout "$TIMEOUT_DNS" dig +short A "$1" 2>&1)
      local rc=$?
      [ "$rc" -eq 124 ] && { RES_ERROR=1; return 1; }
      RES_IPS=$(printf '%s\n' "$salida" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u | paste -sd, -)
      local v6; v6=$(timeout "$TIMEOUT_DNS" dig +short AAAA "$1" 2>/dev/null | sort -u | paste -sd, -)
      [ -n "$v6" ] && RES_IPS="${RES_IPS:+$RES_IPS,}$v6"
      RES_CNAME=$(timeout "$TIMEOUT_DNS" dig +short CNAME "$1" 2>/dev/null | sed 's/\.$//' | head -1)
      ;;
    host)
      local salida; salida=$(timeout "$TIMEOUT_DNS" host "$1" 2>&1)
      local rc=$?
      [ "$rc" -eq 124 ] && { RES_ERROR=1; return 1; }
      printf '%s' "$salida" | grep -qi "is an alias for" && \
        RES_CNAME=$(printf '%s' "$salida" | grep -i "is an alias for" | sed -E 's/.*is an alias for *//I; s/\.$//')
      RES_IPS=$(printf '%s\n' "$salida" | grep -i "has address\|has IPv6 address" | awk '{print $NF}' | sort -u | paste -sd, -)
      ;;
    getent)
      local salida; salida=$(timeout "$TIMEOUT_DNS" getent ahosts "$1" 2>&1)
      local rc=$?
      [ "$rc" -eq 124 ] && { RES_ERROR=1; return 1; }
      [ -n "$salida" ] && RES_IPS=$(printf '%s\n' "$salida" | awk '{print $1}' | sort -u | paste -sd, -)
      ;;
    nslookup)
      # El bloque 1 es SIEMPRE el servidor DNS (su propia IP, no la del
      # dominio). La respuesta real es el ULTIMO parrafo (separado por una
      # linea en blanco). Si solo hay un parrafo, no hubo respuesta real
      # (nombre inexistente: normal, no es error). Si no hubo NADA de
      # salida o el comando lo mato el timeout, eso si es un error real.
      local salida nparr ultimo rc
      salida=$(timeout "$TIMEOUT_DNS" nslookup "$1" 2>&1); rc=$?
      if [ "$rc" -eq 124 ] || [ -z "$salida" ]; then RES_ERROR=1; return 1; fi
      nparr=$(printf '%s' "$salida" | awk 'BEGIN{RS="";n=0}{n++}END{print n+0}')
      [ "${nparr:-0}" -lt 2 ] && return 1
      ultimo=$(printf '%s' "$salida" | awk 'BEGIN{RS=""}{p=$0}END{print p}')
      RES_IPS=$(printf '%s\n' "$ultimo" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | paste -sd, -)
      local v6; v6=$(printf '%s\n' "$ultimo" | grep -oE '[0-9a-fA-F]{1,4}:[0-9a-fA-F:]{2,}[0-9a-fA-F]' | sort -u | paste -sd, -)
      [ -n "$v6" ] && RES_IPS="${RES_IPS:+$RES_IPS,}$v6"
      if printf '%s' "$ultimo" | grep -qi 'Aliases'; then
        RES_CNAME=$(printf '%s\n' "$ultimo" | grep -iE '^Nombre|^Name' | sed -E 's/^[^:]*: *//' | head -1)
      fi
      ;;
  esac
  [ -n "$RES_IPS" ] && return 0 || return 1
}

# ============================================================= OPCIONES =====
clear
logo "DNS brute force discovery"

read -rp "  $(printf "%sDominio objetivo (ej: midominio.com):%s " "$E_TXT" "$E_RST")" DOMINIO
DOMINIO="$(printf '%s' "$DOMINIO" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
if ! [[ "$DOMINIO" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  printf '\n  %s✖ Eso no parece un dominio valido.%s\n\n' "$E_ERR" "$E_RST"; exit 1
fi

read -rp "  $(printf "%sArchivo de wordlist (vacio = diccionario por defecto, %s palabras):%s " "$E_TXT" "${#PALABRAS_DEFECTO[@]}" "$E_RST")" WORDLIST
PALABRAS=()
if [ -n "$WORDLIST" ]; then
  if [ ! -r "$WORDLIST" ]; then
    printf '\n  %s✖ No puedo leer ese archivo.%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
  while IFS= read -r linea || [ -n "$linea" ]; do
    linea="$(printf '%s' "$linea" | tr -d ' \r\n' | tr '[:upper:]' '[:lower:]')"
    [ -n "$linea" ] && PALABRAS+=("$linea")
  done < "$WORDLIST"
  if [ "${#PALABRAS[@]}" -eq 0 ]; then
    printf '\n  %s✖ Ese archivo esta vacio.%s\n\n' "$E_ERR" "$E_RST"; exit 1
  fi
else
  PALABRAS=("${PALABRAS_DEFECTO[@]}")
fi
# quitar palabras repetidas (no cuenta la misma dos veces)
mapfile -t PALABRAS < <(printf '%s\n' "${PALABRAS[@]}" | awk '!v[$0]++')

if [ "$RESOLVER" = "nslookup" ]; then
  printf '  %s(nslookup en Windows no aguanta mucha concurrencia: si ves%s\n' "$E_MUT" "$E_RST"
  printf '  %smuchos errores, repeti con un numero mas bajo, ej: 3-5)%s\n' "$E_MUT" "$E_RST"
fi
read -rp "  $(printf "%sConcurrencia [5]:%s " "$E_TXT" "$E_RST")" CONC
CONC="${CONC:-5}"
if ! [[ "$CONC" =~ ^[0-9]+$ ]] || [ "$CONC" -lt 1 ]; then
  printf '\n  %s✖ La concurrencia tiene que ser un numero mayor a 0.%s\n\n' "$E_ERR" "$E_RST"; exit 1
fi

read -rp "  $(printf "%sGuardar reporte TXT y CSV? (S/n):%s " "$E_TXT" "$E_RST")" REP
[[ "$REP" =~ ^[nN]$ ]] && GUARDAR=0 || GUARDAR=1
CARPETA="$DIR/reportes"

# ---- deteccion de wildcard DNS: si un nombre inventado resuelve, TODO ------
# ---- subdominio va a "resolver" aunque no exista de verdad -----------------
printf '\n  %s↻ Revisando si %s tiene DNS wildcard...%s\n' "$E_INFO" "$DOMINIO" "$E_RST"
AZAR="noexiste-$RANDOM$RANDOM-chequeo"
WILDCARD_IPS=""
if resolver_fqdn "${AZAR}.${DOMINIO}"; then
  WILDCARD_IPS="$RES_IPS"
  printf '  %s⚠ DNS wildcard detectado: TODO resuelve a %s%s\n' "$E_WARN" "$WILDCARD_IPS" "$E_RST"
  printf '  %sLos subdominios que devuelvan esa misma IP se marcan como%s\n' "$E_MUT" "$E_RST"
  printf '  %sposible falso positivo, en vez de darlos por reales.%s\n\n' "$E_MUT" "$E_RST"
else
  printf '  %s✔ Sin wildcard: los que aparezcan son subdominios reales.%s\n\n' "$E_OK" "$E_RST"
fi

# ---- resumen + autorizacion --------------------------------------------------
SEG_EST=$(( (${#PALABRAS[@]} / CONC + 1) * TIMEOUT_DNS ))
caja_top "RESUMEN" "$E_P1"
caja_fila "$(printf '%sDominio%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$DOMINIO" "$E_RST")"
caja_fila "$(printf '%sPalabras a probar%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "${#PALABRAS[@]}" "$E_RST")"
caja_fila "$(printf '%sConcurrencia%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$CONC" "$E_RST")"
caja_fila "$(printf '%sResolutor%s %s%s%s' "$E_MUT" "$E_RST" "$E_INFO" "$RESOLVER" "$E_RST")"
caja_fila "$(printf '%sTiempo estimado%s %s~%s s%s' "$E_MUT" "$E_RST" "$E_TXT" "$SEG_EST" "$E_RST")"
caja_bot "$E_P1"
printf '\n'
caja_top "AUTORIZACION" "$E_WARN"
caja_fila "$(printf '%sEsto genera consultas DNS reales contra el dominio.%s' "$E_TXT" "$E_RST")"
caja_fila "$(printf '%sUsalo solo sobre un dominio tuyo o con autorizacion.%s' "$E_TXT" "$E_RST")"
caja_bot "$E_WARN"
printf '\n'
read -rp "  $(printf "%sEscribi 'si' si %s es tuyo/autorizado:%s " "$E_TXT" "$DOMINIO" "$E_RST")" OK1
if [ "$OK1" != "si" ]; then printf '\n  %s✖ Cancelado.%s\n\n' "$E_ERR" "$E_RST"; exit 1; fi

# ============================================================== REPORTES ====
RUTA_TXT=""; RUTA_CSV=""; RUTA_JSON=""
if [ "$GUARDAR" -eq 1 ]; then
  mkdir -p "$CARPETA" 2>/dev/null
  SELLO="$(date '+%Y%m%d-%H%M%S')"
  RUTA_TXT="$CARPETA/dns-brute-$SELLO.txt"
  RUTA_CSV="$CARPETA/dns-brute-$SELLO.csv"
  RUTA_JSON="$CARPETA/dns-brute-$SELLO.json"
  echo "Subdominio,IPs,CNAME,Tipo,Fuente" > "$RUTA_CSV"
  { echo "DNS BRUTE FORCE DISCOVERY - testing-loki"; echo "Dominio: $DOMINIO"; echo "Generado: $(date '+%Y-%m-%d %H:%M:%S')"; echo; } > "$RUTA_TXT"
fi

# ---- Ctrl+C limpio: igual que diagnostico.sh -------------------------------
CORTADO=0
# Con el control de trabajos activo, cada "&" es su propio grupo de proceso:
# al cortar, matamos el GRUPO entero (timeout + nslookup incluidos), no solo
# el subshell de arriba (si no, nslookup queda colgado en segundo plano).
set -m
trap 'CORTADO=1; for pid in $(jobs -p); do kill -TERM -- "-$pid" 2>/dev/null; done' INT

# ================================================== BUSQUEDA EN PARALELO ====
printf '\n'
seccion "BUSCANDO SUBDOMINIOS" "$E_INFO"
printf '\n'

probar_palabra() { # corre en segundo plano: escribe su resultado a un archivo propio
  local palabra="$1" fqdn="$1.$DOMINIO"
  if resolver_fqdn "$fqdn"; then
    local tipo="real"
    if [ -n "$WILDCARD_IPS" ] && [ "$RES_IPS" = "$WILDCARD_IPS" ]; then tipo="posible_falso_positivo"; fi
    printf '%s|%s|%s|%s\n' "$fqdn" "$RES_IPS" "$RES_CNAME" "$tipo" > "$TMP/$palabra.res"
    if [ "$tipo" = "real" ]; then
      printf '  %s✔ %s%s%s %s· %s%s\n' "$E_OK" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$RES_IPS" "$E_RST"
    else
      printf '  %s? %s%s%s %s· %s (wildcard, posible falso positivo)%s\n' "$E_WARN" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$RES_IPS" "$E_RST"
    fi
  elif [ "${RES_ERROR:-0}" -eq 1 ]; then
    printf '%s\n' "$fqdn" > "$TMP/$palabra.err"
    printf '  %s✖ %s%s%s %serror al consultar (sin respuesta de la herramienta)%s\n' "$E_ERR" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$E_RST"
  fi
}

TOTAL_PAL=${#PALABRAS[@]}
DONE=0
mostrar_progreso() {
  local pct=$(( TOTAL_PAL > 0 ? DONE * 100 / TOTAL_PAL : 100 ))
  printf '  %s[%s/%s · %s%%]%s\n' "$E_P2" "$DONE" "$TOTAL_PAL" "$pct" "$E_RST"
}
EN_VUELO=0
for palabra in "${PALABRAS[@]}"; do
  [ "$CORTADO" -eq 1 ] && break
  if [ "$EN_VUELO" -ge "$CONC" ]; then
    wait -n 2>/dev/null; EN_VUELO=$((EN_VUELO-1)); DONE=$((DONE+1))
    { [ $((DONE % 10)) -eq 0 ] || [ "$DONE" -eq "$TOTAL_PAL" ]; } && mostrar_progreso
  fi
  probar_palabra "$palabra" &
  EN_VUELO=$((EN_VUELO+1))
done
while [ "$EN_VUELO" -gt 0 ]; do
  wait -n 2>/dev/null; EN_VUELO=$((EN_VUELO-1)); DONE=$((DONE+1))
  { [ $((DONE % 10)) -eq 0 ] || [ "$DONE" -eq "$TOTAL_PAL" ]; } && mostrar_progreso
done

# ============================================================= RESUMEN ======
printf '\n'
REALES=0; FALSOS=0; ERRORES=0
JSON_HOSTS=""; JSON_ERRS=""
esc_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
for f in "$TMP"/*.res; do
  [ -e "$f" ] || continue
  IFS='|' read -r fqdn ips cname tipo < "$f"
  if [ "$tipo" = "real" ]; then REALES=$((REALES+1)); else FALSOS=$((FALSOS+1)); fi
  if [ "$GUARDAR" -eq 1 ]; then
    echo "$fqdn,\"$ips\",\"$cname\",$tipo,$RESOLVER" >> "$RUTA_CSV"
    echo "$fqdn | IPs: $ips | CNAME: ${cname:-—} | $tipo" >> "$RUTA_TXT"
    ips_json=$(printf '%s' "$ips" | awk -F, '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?",":""), $i}')
    JSON_HOSTS="${JSON_HOSTS}${JSON_HOSTS:+,}{\"subdominio\":\"$(esc_json "$fqdn")\",\"ips\":[$ips_json],\"cname\":\"$(esc_json "$cname")\",\"tipo\":\"$tipo\"}"
  fi
done
for f in "$TMP"/*.err; do
  [ -e "$f" ] || continue
  ERRORES=$((ERRORES+1))
  fqdn_err=$(cat "$f")
  if [ "$GUARDAR" -eq 1 ]; then
    echo "$fqdn_err | ERROR: sin respuesta de $RESOLVER" >> "$RUTA_TXT.errores" 2>/dev/null
    JSON_ERRS="${JSON_ERRS}${JSON_ERRS:+,}\"$(esc_json "$fqdn_err")\""
  fi
done

seccion "RESUMEN" "$E_P1"
printf '\n'
fila "palabras probadas" "${E_TXT}${TOTAL_PAL}${E_RST}"
fila "subdominios reales" "${E_OK}${REALES}${E_RST}"
fila "falsos positivos" "${E_WARN}${FALSOS}${E_RST}"
fila "errores de consulta" "${E_ERR}${ERRORES}${E_RST}"
printf '\n'
if [ "$CORTADO" -eq 1 ]; then
  printf '  %s✖ Cortado por el usuario. Lo ya encontrado queda arriba.%s\n\n' "$E_WARN" "$E_RST"
fi
if [ "$GUARDAR" -eq 1 ]; then
  {
    printf '{\n  "dominio": "%s",\n  "generado": "%s",\n  "resolutor": "%s",\n' \
      "$(esc_json "$DOMINIO")" "$(date '+%Y-%m-%d %H:%M:%S')" "$RESOLVER"
    printf '  "wildcard_ip": "%s",\n  "palabras_probadas": %s,\n' "$(esc_json "$WILDCARD_IPS")" "$TOTAL_PAL"
    printf '  "hosts": [%s],\n  "errores": [%s]\n}\n' "$JSON_HOSTS" "$JSON_ERRS"
  } > "$RUTA_JSON"
  if [ -s "$RUTA_TXT.errores" ]; then
    { echo; echo "ERRORES DE CONSULTA (sin respuesta de $RESOLVER):"; cat "$RUTA_TXT.errores"; } >> "$RUTA_TXT"
    rm -f "$RUTA_TXT.errores"
  fi
  printf '  %s📄 TXT:%s  %s\n  %s📄 CSV:%s  %s\n  %s📄 JSON:%s %s\n\n' \
    "$E_MUT" "$E_RST" "$RUTA_TXT" "$E_MUT" "$E_RST" "$RUTA_CSV" "$E_MUT" "$E_RST" "$RUTA_JSON"
fi
rm -rf "$TMP"
printf '  %ssolo dominios propios o autorizados%s\n\n' "$E_MUT" "$E_RST"
