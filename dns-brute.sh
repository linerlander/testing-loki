#!/bin/bash
# =============================================================================
#  dns-brute.sh · testing-loki — DNS BRUTE FORCE DISCOVERY (version avanzada)
#
#  Descubre subdominios de UN DOMINIO TUYO (o autorizado) combinando:
#   - diccionario de palabras (igual que antes)
#   - permutaciones comunes (dev1, api-v2, old-www, etc.) [opcional]
#   - Certificate Transparency / crt.sh (consulta publica y pasiva) [opcional]
#  Para cada host encontrado: resuelve A/AAAA, sigue la cadena de CNAME
#  completa, detecta wildcard DNS (falsos positivos), clasifica el host por
#  tipo de servicio (correo/dns/panel/acceso/desarrollo/etc.) y, si hay
#  curl o wget, identifica el proveedor de la IP via RDAP publico.
#  Tambien consulta MX/NS/TXT/SOA del dominio raiz (una sola vez).
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
#  Para Certificate Transparency y clasificacion por proveedor (RDAP) hace
#  falta curl o wget; si no estan, esas dos partes se omiten solas.
#
#  Solo sobre dominios TUYOS o con autorizacion expresa para pruebas
#  activas. Esto SI genera trafico real de DNS contra el dominio, y si
#  activas CT/RDAP tambien consultas HTTPS a crt.sh y a un registro RDAP
#  publico (nunca al dominio objetivo mismo, son servicios de terceros).
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

# ---- detectar herramienta HTTP para CT/RDAP (opcional) ---------------------
HTTP=""
if command -v curl >/dev/null 2>&1; then HTTP="curl"
elif command -v wget >/dev/null 2>&1; then HTTP="wget"
fi
http_get() { # $1=url $2=timeout -> stdout
  case "$HTTP" in
    curl) timeout "${2:-15}" curl -s -L -A "testing-loki/dns-brute" "$1" 2>/dev/null ;;
    wget) timeout "${2:-15}" wget -qO- -U "testing-loki/dns-brute" "$1" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

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

# ---- consultar un registro MX/NS/TXT/SOA del dominio raiz (best-effort) ---
# El formato de salida de host/nslookup varia segun sistema: esto es mejor
# esfuerzo, no un parser DNS completo. getent no soporta estos tipos.
consultar_registro() { # $1=tipo $2=nombre -> un valor por linea (stdout)
  local tipo="$1" nombre="$2"
  case "$RESOLVER" in
    dig)
      timeout "$TIMEOUT_DNS" dig +short "$tipo" "$nombre" 2>/dev/null | sed 's/\.$//'
      ;;
    host)
      timeout "$TIMEOUT_DNS" host -t "$tipo" "$nombre" 2>/dev/null \
        | sed -E 's/^.*(mail is handled by|name server|descriptive text) *//I' \
        | sed -E 's/^[0-9]+ //; s/\.$//; s/^"//; s/"$//'
      ;;
    nslookup)
      timeout "$TIMEOUT_DNS" nslookup -type="$tipo" "$nombre" 2>/dev/null \
        | grep -iE "mail exchanger|nameserver|text =|origin =|primary name server" \
        | sed -E 's/^.*= *//; s/\.$//; s/^"//; s/"$//'
      ;;
    *) return 1 ;;
  esac
}
registros_root() { # popula REG_MX/REG_NS/REG_TXT/REG_SOA -> rc0 si hay algo
  [ "$RESOLVER" = "getent" ] && return 1
  REG_MX=$(consultar_registro MX "$DOMINIO")
  REG_NS=$(consultar_registro NS "$DOMINIO")
  REG_TXT=$(consultar_registro TXT "$DOMINIO")
  REG_SOA=$(consultar_registro SOA "$DOMINIO")
  [ -n "$REG_MX$REG_NS$REG_TXT$REG_SOA" ]
}

# ---- Certificate Transparency (crt.sh): fuente pasiva, no toca el dominio --
obtener_ct() { # popula CT_ENCONTRADOS (array de fqdns unicos) -> rc0 si hay
  CT_ENCONTRADOS=()
  [ -z "$HTTP" ] && return 1
  local salida dompat
  salida=$(http_get "https://crt.sh/?q=%25.${DOMINIO}&output=json" 20)
  [ -z "$salida" ] && return 1
  dompat=$(printf '%s' "$DOMINIO" | sed 's/\./\\./g')
  mapfile -t CT_ENCONTRADOS < <(
    printf '%s' "$salida" \
      | grep -oE '"name_value":"[^"]*"' \
      | sed -E 's/^"name_value":"//; s/"$//' \
      | awk '{gsub(/\\n/,"\n"); print}' \
      | sed 's/^\*\.//' \
      | tr '[:upper:]' '[:lower:]' \
      | grep -E "(^|\\.)${dompat}\$" \
      | grep -v '^$' \
      | sort -u
  )
  [ "${#CT_ENCONTRADOS[@]}" -gt 0 ]
}

# ---- RDAP publico: de que proveedor es una IP (clasificacion, no intrusivo) -
declare -A RDAP_CACHE
rdap_proveedor() { # $1=ip -> echo "nombre|pais"
  local ip="$1"
  [ -z "$HTTP" ] && { printf '|'; return; }
  if [ -n "${RDAP_CACHE[$ip]+x}" ]; then printf '%s' "${RDAP_CACHE[$ip]}"; return; fi
  local salida nombre pais resultado
  salida=$(http_get "https://rdap.org/ip/$ip" 10)
  nombre=$(printf '%s' "$salida" | grep -oE '"name" *: *"[^"]*"' | head -1 | sed -E 's/^"name" *: *"//; s/"$//')
  pais=$(printf '%s' "$salida" | grep -oE '"country" *: *"[^"]*"' | head -1 | sed -E 's/^"country" *: *"//; s/"$//')
  resultado="${nombre}|${pais}"
  RDAP_CACHE[$ip]="$resultado"
  printf '%s' "$resultado"
}

# ---- clasificar un host por el nombre de su primera etiqueta ---------------
clasificar_servicio() { # $1=primera_etiqueta -> categoria
  case "$1" in
    mail|smtp|pop|imap|webmail|mx|mx1|mx2|autodiscover|autoconfig) printf 'correo';;
    ns1|ns2|ns3|ns|dns) printf 'dns';;
    admin|panel|cp|cpanel|whm|plesk|webdisk|oficina|licencias|bot|direct) printf 'panel';;
    vpn|ssh|remote|office|corp|intranet|extranet|secure|login|auth|sso|accounts|id) printf 'acceso';;
    dev|test|staging|beta|alpha|demo|sandbox|qa|uat) printf 'desarrollo';;
    db|mysql|redis|cache) printf 'base_datos';;
    status|monitor|grafana|kibana) printf 'monitoreo';;
    git|gitlab|jenkins|ci|cd) printf 'ci_cd';;
    *) printf 'web';;
  esac
}

# ---- permutaciones comunes a partir del diccionario ya elegido ------------
generar_permutaciones() { # popula PERM_EXTRA a partir de PALABRAS
  local sufijos_num=(1 2 3) sufijos_tag=(v1 v2 prod backup old new) prefijos=(new old internal backup)
  PERM_EXTRA=()
  local w s
  for w in "${PALABRAS[@]}"; do
    for s in "${sufijos_num[@]}"; do PERM_EXTRA+=("${w}${s}"); done
    for s in "${sufijos_tag[@]}"; do PERM_EXTRA+=("${w}-${s}"); done
    for s in "${prefijos[@]}"; do PERM_EXTRA+=("${s}-${w}"); done
  done
  mapfile -t PERM_EXTRA < <(printf '%s\n' "${PERM_EXTRA[@]}" | awk '!v[$0]++')
}

# ---- modo marca: si escriben un nombre sin TLD (ej "linerlander"), probar -
# ---- los TLD mas comunes con una consulta NS liviana (no es brute force) --
TLDS_MARCA=(com net org info io co space site online xyz me app dev tech store shop cloud pro live top vip)
modo_marca() { # $1=marca -> si encuentra, deja DOMINIO seteado y retorna 0
  local marca="$1" encontrados=() t c existe ns
  printf '\n  %s↻ "%s" no es un dominio completo. Probando TLDs comunes (consulta NS, liviano)...%s\n\n' "$E_INFO" "$marca" "$E_RST"
  for t in "${TLDS_MARCA[@]}"; do
    c="${marca}.${t}"; existe=0
    if [ "$RESOLVER" != "getent" ]; then
      ns=$(consultar_registro NS "$c")
      [ -n "$ns" ] && existe=1
    fi
    [ "$existe" -eq 0 ] && resolver_fqdn "$c" && existe=1
    if [ "$existe" -eq 1 ]; then
      encontrados+=("$c")
      printf '  %s✔ %s%s%s %sexiste%s\n' "$E_OK" "$E_BLD$E_TXT" "$c" "$E_RST" "$E_MUT" "$E_RST"
    fi
  done
  printf '\n'
  if [ "${#encontrados[@]}" -eq 0 ]; then
    printf '  %s✖ No encontre "%s" registrado en ningun TLD comun.%s\n' "$E_ERR" "$marca" "$E_RST"
    printf '  %sSi sabes el TLD exacto, escribilo completo (ej: %s.com)%s\n\n' "$E_MUT" "$marca" "$E_RST"
    return 1
  elif [ "${#encontrados[@]}" -eq 1 ]; then
    DOMINIO="${encontrados[0]}"
    printf '  %s→ Usando %s%s\n\n' "$E_INFO" "$DOMINIO" "$E_RST"
    return 0
  else
    printf '  %sEncontre %s%s%s dominios. Elegi cual usar:%s\n' "$E_TXT" "$E_BLD" "${#encontrados[@]}" "$E_RST" "$E_RST"
    local i=1
    for c in "${encontrados[@]}"; do printf '    %s%d)%s %s\n' "$E_P2" "$i" "$E_RST" "$c"; i=$((i+1)); done
    read -rp "  $(printf "%sNumero:%s " "$E_TXT" "$E_RST")" ELEC
    if ! [[ "$ELEC" =~ ^[0-9]+$ ]] || [ "$ELEC" -lt 1 ] || [ "$ELEC" -gt "${#encontrados[@]}" ]; then
      printf '\n  %s✖ Opcion invalida.%s\n\n' "$E_ERR" "$E_RST"; return 1
    fi
    DOMINIO="${encontrados[$((ELEC-1))]}"
    printf '\n  %s→ Usando %s%s\n\n' "$E_INFO" "$DOMINIO" "$E_RST"
    return 0
  fi
}

# ============================================================= OPCIONES =====
clear
logo "DNS brute force discovery"

read -rp "  $(printf "%sDominio objetivo (ej: midominio.com, o solo 'marca' para probar TLDs):%s " "$E_TXT" "$E_RST")" DOMINIO
DOMINIO="$(printf '%s' "$DOMINIO" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
if [[ "$DOMINIO" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  : # dominio completo, sigue de largo
elif [[ "$DOMINIO" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  modo_marca "$DOMINIO" || exit 1
else
  printf '\n  %s✖ Eso no parece un dominio ni un nombre valido.%s\n\n' "$E_ERR" "$E_RST"; exit 1
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

read -rp "  $(printf "%s¿Agregar permutaciones comunes (dev1, api-v2, old-www, etc.)? Multiplica bastante la cantidad de consultas (s/N):%s " "$E_TXT" "$E_RST")" PERM_SI
PERM_EXTRA=()
if [[ "$PERM_SI" =~ ^[sS]$ ]]; then
  generar_permutaciones
  printf '  %s✔ %s permutaciones generadas.%s\n' "$E_OK" "${#PERM_EXTRA[@]}" "$E_RST"
fi

CT_HABILITADO=0
if [ -n "$HTTP" ]; then
  read -rp "  $(printf "%s¿Buscar tambien en Certificate Transparency (crt.sh, consulta publica y pasiva)? (S/n):%s " "$E_TXT" "$E_RST")" CT_SI
  [[ "$CT_SI" =~ ^[nN]$ ]] || CT_HABILITADO=1
else
  printf '  %s(sin curl ni wget: se omiten Certificate Transparency y la clasificacion por proveedor)%s\n' "$E_MUT" "$E_RST"
fi

CT_ENCONTRADOS=()
if [ "$CT_HABILITADO" -eq 1 ]; then
  printf '  %s↻ Consultando crt.sh...%s' "$E_INFO" "$E_RST"
  if obtener_ct; then
    printf '\r  %s✔ Certificate Transparency: %s nombres encontrados.%s\n' "$E_OK" "${#CT_ENCONTRADOS[@]}" "$E_RST"
  else
    printf '\r  %s✖ Sin resultados de crt.sh (o sin red en este momento).%s\n' "$E_WARN" "$E_RST"
  fi
fi

# ---- unificar diccionario + permutaciones + CT en una sola lista de fqdns --
declare -A FUENTE_DE
TARGETS=()
agregar_target() { # $1=fqdn $2=fuente
  local f="$1" s="$2"
  if [ -z "${FUENTE_DE[$f]+x}" ]; then
    TARGETS+=("$f"); FUENTE_DE[$f]="$s"
  else
    case "${FUENTE_DE[$f]}" in *"$s"*) ;; *) FUENTE_DE[$f]="${FUENTE_DE[$f]}+$s";; esac
  fi
}
for palabra in "${PALABRAS[@]}"; do agregar_target "$palabra.$DOMINIO" "diccionario"; done
for palabra in "${PERM_EXTRA[@]:-}"; do [ -n "$palabra" ] && agregar_target "$palabra.$DOMINIO" "permutacion"; done
for h in "${CT_ENCONTRADOS[@]:-}"; do [ -n "$h" ] && agregar_target "$h" "ct"; done

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

# ---- registros del dominio raiz (una sola consulta, no por subdominio) ----
if registros_root; then
  caja_top "REGISTROS DEL DOMINIO RAIZ" "$E_INFO"
  if [ -n "$REG_NS" ]; then while IFS= read -r l; do [ -n "$l" ] && caja_fila "$(printf '%sNS%s  %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$l" "$E_RST")"; done <<< "$REG_NS"; fi
  if [ -n "$REG_MX" ]; then while IFS= read -r l; do [ -n "$l" ] && caja_fila "$(printf '%sMX%s  %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$l" "$E_RST")"; done <<< "$REG_MX"; fi
  if [ -n "$REG_SOA" ]; then while IFS= read -r l; do [ -n "$l" ] && caja_fila "$(printf '%sSOA%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$l" "$E_RST")"; done <<< "$REG_SOA"; fi
  if [ -n "$REG_TXT" ]; then while IFS= read -r l; do [ -n "$l" ] && caja_fila "$(printf '%sTXT%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$l" "$E_RST")"; done <<< "$REG_TXT"; fi
  caja_bot "$E_INFO"
  printf '\n'
else
  [ "$RESOLVER" = "getent" ] && printf '  %s(getent no permite consultar MX/NS/TXT/SOA; instala dig u host para esto)%s\n\n' "$E_MUT" "$E_RST"
fi

# ---- resumen + autorizacion --------------------------------------------------
TOTAL_PAL=${#TARGETS[@]}
SEG_EST=$(( (TOTAL_PAL / CONC + 1) * TIMEOUT_DNS ))
caja_top "RESUMEN" "$E_P1"
caja_fila "$(printf '%sDominio%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$DOMINIO" "$E_RST")"
caja_fila "$(printf '%sObjetivos a probar%s %s%s%s %s(diccionario %s · permutaciones %s · CT %s)%s' \
  "$E_MUT" "$E_RST" "$E_TXT" "$TOTAL_PAL" "$E_RST" "$E_MUT" "${#PALABRAS[@]}" "${#PERM_EXTRA[@]}" "${#CT_ENCONTRADOS[@]}" "$E_RST")"
caja_fila "$(printf '%sConcurrencia%s %s%s%s' "$E_MUT" "$E_RST" "$E_TXT" "$CONC" "$E_RST")"
caja_fila "$(printf '%sResolutor%s %s%s%s' "$E_MUT" "$E_RST" "$E_INFO" "$RESOLVER" "$E_RST")"
caja_fila "$(printf '%sTiempo estimado%s %s~%s s%s' "$E_MUT" "$E_RST" "$E_TXT" "$SEG_EST" "$E_RST")"
caja_bot "$E_P1"
printf '\n'
caja_top "AUTORIZACION" "$E_WARN"
caja_fila "$(printf '%sEsto genera consultas DNS reales contra el dominio.%s' "$E_TXT" "$E_RST")"
[ "$CT_HABILITADO" -eq 1 ] && caja_fila "$(printf '%sTambien consulta crt.sh y RDAP publico (terceros, pasivo).%s' "$E_TXT" "$E_RST")"
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
  echo "Subdominio,IPs,CNAME,CadenaCNAME,Tipo,Fuente,Categoria,Proveedor,Pais" > "$RUTA_CSV"
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

probar_target() { # corre en segundo plano: escribe su resultado a un archivo propio
  local fqdn="$1" fuente="${FUENTE_DE[$1]:-desconocida}" fname
  fname=$(printf '%s' "$fqdn" | tr -c 'A-Za-z0-9._-' '_')
  if resolver_fqdn "$fqdn"; then
    local ips="$RES_IPS" cadena="$RES_CNAME" objetivo="$RES_CNAME" saltos=0
    # seguir la cadena de CNAME hasta su destino final (maximo 5 saltos)
    while [ -n "$objetivo" ] && [ "$saltos" -lt 5 ]; do
      saltos=$((saltos+1))
      if resolver_fqdn "$objetivo"; then
        [ -n "$RES_IPS" ] && ips="$RES_IPS"
        if [ -n "$RES_CNAME" ] && [ "$RES_CNAME" != "$objetivo" ]; then
          cadena="$cadena -> $RES_CNAME"; objetivo="$RES_CNAME"
        else objetivo=""; fi
      else objetivo=""; fi
    done
    local tipo="real"
    if [ -n "$WILDCARD_IPS" ] && [ "$ips" = "$WILDCARD_IPS" ]; then tipo="posible_falso_positivo"; fi
    local proveedor="" pais=""
    if [ "$tipo" = "real" ] && [ -n "$HTTP" ]; then
      local primera_ip="${ips%%,*}"
      IFS='|' read -r proveedor pais <<< "$(rdap_proveedor "$primera_ip")"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$fqdn" "$ips" "$cadena" "$tipo" "$fuente" "$cadena" "$proveedor" "$pais" > "$TMP/$fname.res"
    local detalle="$E_MUT$ips$E_RST"
    [ -n "$proveedor" ] && detalle="$detalle $E_MUT· $proveedor${pais:+ ($pais)}$E_RST"
    if [ "$tipo" = "real" ]; then
      printf '  %s✔ %s%s%s %s[%s] %s%s\n' "$E_OK" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$fuente" "$E_RST" "$detalle"
    else
      printf '  %s? %s%s%s %s[%s] (wildcard, posible falso positivo) %s%s\n' "$E_WARN" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$fuente" "$ips" "$E_RST"
    fi
  elif [ "${RES_ERROR:-0}" -eq 1 ]; then
    printf '%s\n' "$fqdn" > "$TMP/$fname.err"
    printf '  %s✖ %s%s%s %serror al consultar (sin respuesta de la herramienta)%s\n' "$E_ERR" "$E_BLD$E_TXT" "$fqdn" "$E_RST" "$E_MUT" "$E_RST"
  fi
}

DONE=0
mostrar_progreso() {
  local pct=$(( TOTAL_PAL > 0 ? DONE * 100 / TOTAL_PAL : 100 ))
  printf '  %s[%s/%s · %s%%]%s\n' "$E_P2" "$DONE" "$TOTAL_PAL" "$pct" "$E_RST"
}
EN_VUELO=0
for fqdn in "${TARGETS[@]}"; do
  [ "$CORTADO" -eq 1 ] && break
  if [ "$EN_VUELO" -ge "$CONC" ]; then
    wait -n 2>/dev/null; EN_VUELO=$((EN_VUELO-1)); DONE=$((DONE+1))
    { [ $((DONE % 10)) -eq 0 ] || [ "$DONE" -eq "$TOTAL_PAL" ]; } && mostrar_progreso
  fi
  probar_target "$fqdn" &
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
declare -A POR_CATEGORIA
esc_json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
for f in "$TMP"/*.res; do
  [ -e "$f" ] || continue
  IFS='|' read -r fqdn ips cadena tipo fuente _cadena2 proveedor pais < "$f"
  categoria=$(clasificar_servicio "${fqdn%%.*}")
  if [ "$tipo" = "real" ]; then
    REALES=$((REALES+1))
    POR_CATEGORIA["$categoria"]=$(( ${POR_CATEGORIA["$categoria"]:-0} + 1 ))
  else
    FALSOS=$((FALSOS+1))
  fi
  if [ "$GUARDAR" -eq 1 ]; then
    echo "$fqdn,\"$ips\",\"$cadena\",\"$cadena\",$tipo,$fuente,$categoria,\"$proveedor\",\"$pais\"" >> "$RUTA_CSV"
    echo "$fqdn | IPs: $ips | CNAME: ${cadena:-—} | $tipo | fuente: $fuente | categoria: $categoria${proveedor:+ | proveedor: $proveedor}${pais:+ ($pais)}" >> "$RUTA_TXT"
    ips_json=$(printf '%s' "$ips" | awk -F, '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?",":""), $i}')
    JSON_HOSTS="${JSON_HOSTS}${JSON_HOSTS:+,}{\"subdominio\":\"$(esc_json "$fqdn")\",\"ips\":[$ips_json],\"cadena_cname\":\"$(esc_json "$cadena")\",\"tipo\":\"$tipo\",\"fuente\":\"$(esc_json "$fuente")\",\"categoria\":\"$categoria\",\"proveedor\":\"$(esc_json "$proveedor")\",\"pais\":\"$(esc_json "$pais")\"}"
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
fila "objetivos probados" "${E_TXT}${TOTAL_PAL}${E_RST}"
fila "subdominios reales" "${E_OK}${REALES}${E_RST}"
fila "falsos positivos" "${E_WARN}${FALSOS}${E_RST}"
fila "errores de consulta" "${E_ERR}${ERRORES}${E_RST}"
if [ "${#POR_CATEGORIA[@]}" -gt 0 ]; then
  printf '\n'
  seccion "POR TIPO DE SERVICIO" "$E_P2"
  printf '\n'
  for cat in "${!POR_CATEGORIA[@]}"; do
    fila "  $cat" "${E_INFO}${POR_CATEGORIA[$cat]}${E_RST}"
  done
fi
printf '\n'
if [ "$CORTADO" -eq 1 ]; then
  printf '  %s✖ Cortado por el usuario. Lo ya encontrado queda arriba.%s\n\n' "$E_WARN" "$E_RST"
fi
if [ "$GUARDAR" -eq 1 ]; then
  {
    printf '{\n  "dominio": "%s",\n  "generado": "%s",\n  "resolutor": "%s",\n' \
      "$(esc_json "$DOMINIO")" "$(date '+%Y-%m-%d %H:%M:%S')" "$RESOLVER"
    printf '  "wildcard_ip": "%s",\n  "objetivos_probados": %s,\n' "$(esc_json "$WILDCARD_IPS")" "$TOTAL_PAL"
    printf '  "registros_raiz": {"ns": "%s", "mx": "%s", "txt": "%s", "soa": "%s"},\n' \
      "$(esc_json "${REG_NS:-}")" "$(esc_json "${REG_MX:-}")" "$(esc_json "${REG_TXT:-}")" "$(esc_json "${REG_SOA:-}")"
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
