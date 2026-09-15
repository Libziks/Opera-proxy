#!/bin/sh
# ================================================================
#  opera-proxy installer for Keenetic / Entware
#  Режим: SOCKS5 (-socks-mode) с обфускацией SNI (2gis.com)
#  Интерфейс: автоматический выбор ProxyX + выход в интернет
# ================================================================

set -e

CONF_FILE="/opt/etc/opera-proxy.conf"
INIT_SCRIPT="/opt/etc/init.d/S99opera-proxy"
REPO_CONF="/opt/etc/opkg/sw.ext.io.conf"
IFACE_NAME="Opera"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; N='\033[0m'
info() { printf "${C}[INFO]${N}  %s\n" "$*"; }
ok()   { printf "${G}[ OK ]${N}  %s\n" "$*"; }
warn() { printf "${Y}[WARN]${N}  %s\n" "$*"; }
die()  { printf "${R}[ERR ]${N}  %s\n" "$*"; exit 1; }

# ── 1. Архитектура ────────────────────────────────────────────
info "Определяем архитектуру процессора..."
A=$(opkg print-architecture 2>/dev/null \
  | awk '/^arch/ && $2~/^(mips|mipsel|aarch64|armv7|arm)/{sub(/[-_].*/,"",$2); print $2; exit}')
[ -z "$A" ] && die "Не удалось определить архитектуру роутера"
ok "Архитектура: $A"

# ── 2. Репозиторий ────────────────────────────────────────────
info "Прописываем репозиторий sw.ext.io..."
mkdir -p /opt/etc/opkg
printf 'src/gz sw http://sw.ext.io/ent/%s\n' "$A" > "$REPO_CONF"
ok "Репозиторий добавлен: http://sw.ext.io/ent/$A"

# ── 3. Обновление opkg и проверка curl ────────────────────────
info "Обновляем список пакетов opkg..."
opkg update > /dev/null 2>&1 || warn "opkg update завершился с предупреждениями"
opkg list-installed | grep -q "^curl " || opkg install curl

# ── 4. Установка opera-proxy ──────────────────────────────────
if opkg list-installed | grep -q "^opera-proxy "; then
  warn "opera-proxy уже установлен — пропускаем шаг установки пакета"
else
  info "Устанавливаем opera-proxy..."
  if ! opkg install opera-proxy > /dev/null 2>&1; then
    info "Поиск .ipk в репозитории..."
    U="http://sw.ext.io/ent/$A"
    PKG=$(curl -fsSL "$U/" 2>/dev/null \
      | grep -o "opera-proxy_[^\"]*_${A}[^\"]*\.ipk" \
      | sort -V | tail -1)
    [ -z "$PKG" ] && die "Пакет opera-proxy не найден в $U/"
    curl -fsSL "$U/$PKG" -o /tmp/opera-proxy.ipk
    opkg install /tmp/opera-proxy.ipk
    rm -f /tmp/opera-proxy.ipk
  fi
fi

command -v opera-proxy > /dev/null 2>&1 || die "Бинарник opera-proxy не найден в /opt/bin"
ok "Установлен: $(command -v opera-proxy)"

# ── 5. Конфигурационный файл (принудительная перезапись) ──────
info "Записываем конфигурационный файл $CONF_FILE..."

if [ -f "$CONF_FILE" ]; then
  warn "Старый конфиг обнаружен — перезаписываем новыми настройками..."
fi

cat > "$CONF_FILE" << 'EOF'
# ─────────────────────────────────────────────────────
#  Конфигурация opera-proxy для Keenetic (SOCKS5)
#  После изменений: /opt/etc/init.d/S99opera-proxy restart
# ─────────────────────────────────────────────────────

# Регион: EU (Европа), AS (Азия), AM (Америка)
COUNTRY="EU"

# Адрес и порт (0.0.0.0 — доступен роутеру и всей домашней сети)
BIND_ADDR="0.0.0.0"
BIND_PORT="1080"

# Обход блокировок ТСПУ/DPI в РФ
OBFUSCATE="yes"
FAKE_SNI="2gis.com"

# Защищённый DoH DNS для первичного поиска серверов
BOOTSTRAP_DNS="https://dns.google/dns-query,https://1.1.1.1/dns-query"

# Выбор сервера: random (случайный) или fastest (быстрый)
SERVER_SELECT="random"

# Уровень логов: 10=debug, 20=info, 30=warn, 40=error
VERBOSITY="30"
EOF
ok "Конфиг успешно записан: $CONF_FILE"

# ── 6. Init-скрипт ────────────────────────────────────────────
info "Создаём init-скрипт $INIT_SCRIPT..."
cat > "$INIT_SCRIPT" << 'INITEOF'
#!/bin/sh

[ -f /opt/etc/opera-proxy.conf ] && . /opt/etc/opera-proxy.conf

ENABLED=yes
PROCS=opera-proxy

OPTS="-socks-mode"
[ -n "$COUNTRY" ] && OPTS="$OPTS -country $COUNTRY"
[ -n "$BIND_ADDR" ] && [ -n "$BIND_PORT" ] && OPTS="$OPTS -bind-address ${BIND_ADDR}:${BIND_PORT}"
[ -n "$VERBOSITY" ] && OPTS="$OPTS -verbosity $VERBOSITY"
[ -n "$SERVER_SELECT" ] && OPTS="$OPTS -server-selection $SERVER_SELECT"
[ -n "$BOOTSTRAP_DNS" ] && OPTS="$OPTS -bootstrap-dns $BOOTSTRAP_DNS"

if [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ]; then
    OPTS="$OPTS -fake-SNI $FAKE_SNI"
fi

ARGS="$OPTS"
PREARGS=""
DESC="Opera Proxy SOCKS5"
PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
INITEOF
chmod 755 "$INIT_SCRIPT"
ok "Init-скрипт готов"

# ── 7. Очистка старого cron ───────────────────────────────────
CRONTAB_FILE="/opt/var/spool/cron/crontabs/root"
if [ -f "$CRONTAB_FILE" ] && grep -qF "opera-proxy" "$CRONTAB_FILE" 2>/dev/null; then
  sed -i '/opera-proxy/d' "$CRONTAB_FILE"
  ok "Старый watchdog удален из crontab"
fi

# ── 8. Запуск сервиса ─────────────────────────────────────────
info "Запускаем службу opera-proxy..."
"$INIT_SCRIPT" restart > /dev/null 2>&1 || "$INIT_SCRIPT" start > /dev/null 2>&1
sleep 2

PID=$(pidof opera-proxy 2>/dev/null | awk '{print $1}')
if [ -n "$PID" ]; then
  ok "Успешно запущен (PID: $PID)"
else
  die "Процесс не запустился. Проверьте логи: logread | grep -i opera"
fi

# ── 9. Поиск и настройка интерфейса в Keenetic OS ─────────────
[ -f "$CONF_FILE" ] && . "$CONF_FILE"
BIND_PORT="${BIND_PORT:-1080}"

if ! command -v ndmc > /dev/null 2>&1; then
  warn "Утилита ndmc не найдена — настройте подключение вручную в «Другие подключения»"
else
  info "Поиск доступного Proxy-интерфейса в Keenetic OS..."
  CONF_RUNNING=$(ndmc -c "show running-config" 2>/dev/null || echo "")
  
  IFACE=""
  # 1. Проверяем, есть ли уже интерфейс Opera
  if [ -n "$CONF_RUNNING" ]; then
    IFACE=$(printf '%s\n' "$CONF_RUNNING" | awk '
      /^interface Proxy[0-9]+/ { cur=$2 }
      /description.*Opera/     { print cur; exit }
    ')
  fi
  
  # 2. Если Opera нет — ищем первый СВОБОДНЫЙ ProxyX
  if [ -z "$IFACE" ]; then
    for i in 0 1 2 3 4 5 6 7 8 9; do
      if ! printf '%s\n' "$CONF_RUNNING" | grep -q "^interface Proxy$i"; then
        IFACE="Proxy$i"
        break
      fi
    done
  fi
  
  [ -z "$IFACE" ] && IFACE="Proxy0"
  info "Используется интерфейс: $IFACE"

  # Настройка интерфейса
  ndmc -c "interface $IFACE" > /dev/null 2>&1 || true
  ndmc -c "interface $IFACE proxy protocol socks5" > /dev/null 2>&1
  ndmc -c "no interface $IFACE proxy socks5-udp" > /dev/null 2>&1 || true
  
  # Сброс старой авторизации
  ndmc -c "no interface $IFACE authentication" > /dev/null 2>&1 || true
  ndmc -c "no interface $IFACE authentication identity" > /dev/null 2>&1 || true
  ndmc -c "no interface $IFACE authentication password" > /dev/null 2>&1 || true
  
  ndmc -c "interface $IFACE proxy upstream 127.0.0.1 $BIND_PORT" > /dev/null 2>&1
  ndmc -c "interface $IFACE description $IFACE_NAME" > /dev/null 2>&1
  # ВКЛЮЧАЕМ ГАЛОЧКУ "Использовать для выхода в Интернет":
  ndmc -c "interface $IFACE ip global auto" > /dev/null 2>&1
  ndmc -c "interface $IFACE up" > /dev/null 2>&1
  ndmc -c "system configuration save" > /dev/null 2>&1
  ok "Интерфейс '$IFACE_NAME' настроен на $IFACE (выход в интернет включен)"
fi

echo ""
printf "${G}══════════════════════════════════════════════════════════${N}\n"
printf "${G}  Установка и настройка успешно завершены!${N}\n"
printf "${G}══════════════════════════════════════════════════════════${N}\n"
printf "\n"
printf "  Служба:               Запущена (PID: %s)\n" "$PID"
printf "  Имя подключения:      %s (%s)\n" "$IFACE_NAME" "$IFACE"
printf "  Выход в интернет:     Включен (ip global auto)\n"
printf "  Прокси для клиентов:  socks5://%s:%s\n" "${BIND_ADDR:-0.0.0.0}" "$BIND_PORT"
printf "  Обфускация:           %s (%s)\n" "${OBFUSCATE:-yes}" "${FAKE_SNI:-2gis.com}"
printf "\n"
printf "  В веб-интерфейсе Keenetic подключение находится в меню:\n"
printf "  «Другие подключения» (раздел «Прокси») под именем \"%s\".\n" "$IFACE_NAME"
printf "\n"
printf "  ℹ️  Первичное подключение к серверам Opera занимает 10-20 секунд.\n"
printf "  Проверить соединение вручную чуть позже:\n"
printf "    curl -fsSL --socks5-hostname 127.0.0.1:%s https://api.ipify.org\n" "$BIND_PORT"
printf "\n"
printf "  Посмотреть лог работы:\n"
printf "    logread | grep -i opera\n"
printf "\n"
