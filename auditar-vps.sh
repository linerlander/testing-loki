#!/bin/bash
# =============================================================================
#  auditar-vps.sh  ·  Revisa UN VPS TUYO: qué puertos tiene abiertos, qué
#  servicios corren y avisos de seguridad básicos.
#
#  USO:   bash auditar-vps.sh <IP_O_DOMINIO>
#  Ej:    bash auditar-vps.sh 203.0.113.10
#
#  ⚠️  Sólo sobre servidores TUYOS o que te hayan autorizado. Escanear algo
#      ajeno sin permiso es ilegal: el script te lo pregunta antes de empezar.
# =============================================================================
set -u
VERDE='\e[32m'; AMAR='\e[33m'; ROJO='\e[31m'; GRIS='\e[90m'; N='\e[0m'; B='\e[1m'

OBJ="${1:-}"
[ -n "$OBJ" ] || { echo "Uso: bash auditar-vps.sh <IP_O_DOMINIO_TUYO>"; exit 1; }

echo
echo -e "${B}🔍 Auditoría de:${N} $OBJ"
echo -e "${GRIS}────────────────────────────────────────────${N}"

# 1) Candado de autorización ---------------------------------------------------
echo -e "${AMAR}¿Este servidor es TUYO o te autorizaron a escanearlo?${N}"
read -r -p "   Escribí 'si' para continuar: " OK
[ "$OK" = "si" ] || { echo -e "${ROJO}Cancelado. Sólo se escanean servidores propios.${N}"; exit 1; }
echo

# 2) ¿Hace falta nmap? ---------------------------------------------------------
if ! command -v nmap >/dev/null 2>&1; then
  echo -e "${AMAR}Falta nmap. Lo instalo...${N}"
  if   command -v apt-get >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y nmap
  elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y nmap
  elif command -v yum     >/dev/null 2>&1; then sudo yum install -y nmap
  else echo -e "${ROJO}Instalá nmap a mano y volvé a correr.${N}"; exit 1; fi
fi

# 3) ¿Está vivo? ---------------------------------------------------------------
echo -e "${B}1) ¿Responde el servidor?${N}"
if ping -c 1 -W 3 "$OBJ" >/dev/null 2>&1; then
  echo -e "   ${VERDE}✔ Responde al ping${N}"
else
  echo -e "   ${AMAR}⚠ No responde al ping (puede ser normal: muchos VPS lo bloquean).${N}"
fi
echo

# 4) Escaneo de puertos y servicios -------------------------------------------
echo -e "${B}2) Puertos abiertos y servicios (puede tardar 1-2 min)...${N}"
SAL=$(nmap -sV -T4 -Pn "$OBJ" 2>/dev/null)
echo "$SAL" | grep -E '^[0-9]+/(tcp|udp)' | while read -r linea; do
  PUERTO=$(echo "$linea" | awk '{print $1}')
  ESTADO=$(echo "$linea" | awk '{print $2}')
  SERV=$(echo "$linea"   | awk '{print $3}')
  VERS=$(echo "$linea"   | cut -d' ' -f4-)
  [ "$ESTADO" = "open" ] || continue
  printf "   ${VERDE}%-10s${N} %-12s ${GRIS}%s${N}\n" "$PUERTO" "$SERV" "$VERS"
done
echo

# 5) Avisos de seguridad -------------------------------------------------------
echo -e "${B}3) Avisos:${N}"
AVISOS=0
chk() { echo "$SAL" | grep -qE "$1"; }

if chk '^23/tcp +open';   then echo -e "   ${ROJO}✖ Telnet (23) abierto: inseguro, cerralo.${N}"; AVISOS=$((AVISOS+1)); fi
if chk '^21/tcp +open';   then echo -e "   ${AMAR}⚠ FTP (21) abierto: usá SFTP en su lugar.${N}"; AVISOS=$((AVISOS+1)); fi
if chk '^3306/tcp +open'; then echo -e "   ${ROJO}✖ MySQL (3306) expuesto a internet: limitalo al VPS.${N}"; AVISOS=$((AVISOS+1)); fi
if chk '^6379/tcp +open'; then echo -e "   ${ROJO}✖ Redis (6379) expuesto: muy peligroso, cerralo.${N}"; AVISOS=$((AVISOS+1)); fi
if chk '^5432/tcp +open'; then echo -e "   ${AMAR}⚠ PostgreSQL (5432) expuesto: limitalo al VPS.${N}"; AVISOS=$((AVISOS+1)); fi
if chk '^22/tcp +open';   then echo -e "   ${GRIS}ℹ SSH (22) en el puerto por defecto: considerá cambiarlo.${N}"; fi

[ "$AVISOS" -eq 0 ] && echo -e "   ${VERDE}✔ Sin alertas graves.${N}"
echo
echo -e "${GRIS}Listo. Guardá la salida para comparar más adelante.${N}"
