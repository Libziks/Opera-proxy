# 🎭 Opera Proxy для Keenetic

Быстрый локальный **SOCKS5-прокси** через инфраструктуру **Opera VPN (SurfEasy)**.  
Работает без сторонних приложений, маскирует TLS-рукопожатие под незаблокированный домен (SNI `2gis.com`) и обходит фильтрацию ТСПУ/DPI в РФ.

```
Устройство / Роутер → SOCKS5 :1080 → opera-proxy (SNI 2gis.com + DoH) → TLS 443 → *.sec-tunnel.com → 🌍
```

---

## ⚡ Установка

Выполните команду в терминале роутера (SSH / Entware):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Libziks/Opera-proxy/main/install.sh)"
```

**Что скрипт делает автоматически:**
- 🔍 Определяет архитектуру процессора (`aarch64`, `armv7`, `mips`, `mipsel`);
- 📦 Устанавливает пакет `opera-proxy` и настраивает DoH-резолвер для обхода блокировок API;
- 🛡️ Активирует обфускацию TLS (маскировка под `2gis.com`);
- 🔌 Находит первый свободный слот (`Proxy0`, `Proxy1`...), не затирая существующие прокси;
- 🌐 Создаёт в KeeneticOS интерфейс **Opera** с активной опцией **«Использовать для выхода в Интернет»** (без конфликтующего UDP).

---

## ⚙️ Настройка

Все параметры меняются в одном конфигурационном файле `/opt/etc/opera-proxy.conf`:

```sh
nano /opt/etc/opera-proxy.conf
```

| Параметр | По умолчанию | Описание |
| :--- | :--- | :--- |
| `COUNTRY` | `"EU"` | Регион подключения: `EU` (Европа), `AM` (Америка), `AS` (Азия) |
| `BIND_ADDR` | `"0.0.0.0"` | `0.0.0.0` — доступен всей домашней сети, `127.0.0.1` — только роутеру |
| `BIND_PORT` | `"1080"` | Локальный порт SOCKS5 |
| `OBFUSCATE` | `"yes"` | Включение маскировки SNI (`yes` / `no`) |
| `FAKE_SNI` | `"2gis.com"` | Домен для маскировки TLS-рукопожатия |
| `BOOTSTRAP_DNS` | *Google/Cloudflare* | Защищённый DoH для первичного поиска серверов |

После сохранения изменений примените настройки:
```sh
/opt/etc/init.d/S*opera-proxy restart
```

---

## 🎮 Управление службой

```sh
/opt/etc/init.d/S*opera-proxy start    # Запуск
/opt/etc/init.d/S*opera-proxy stop     # Остановка
/opt/etc/init.d/S*opera-proxy restart  # Перезапуск
/opt/etc/init.d/S*opera-proxy check    # Проверка статуса процесса
```

---

## 📡 Использование

### 1. На роутере (KeeneticOS)
- Подключение доступно в меню **«Другие подключения»** → раздел **«Прокси»** под именем **Opera**.
- Для выборочной маршрутизации устройств или доменов перейдите в **«Сетевые правила» → «Приоритеты подключений»** и привяжите интерфейс **Opera** к нужной политике.

> ⚠️ **Важно (только TCP):** Сеть Opera **не поддерживает UDP**. Для стабильной работы сайтов добавьте DoH-сервер (например, `https://dns.google/dns-query`) в веб-интерфейсе Keenetic: **«Сетевые правила» → «DNS»**.

### 2. На устройствах в локальной сети (вручную)
В настройках прокси браузера / Telegram / ОС укажите:
* **Тип:** `SOCKS5`
* **Адрес:** IP-адрес роутера (например, `192.168.1.1`)
* **Порт:** `1080`

---

## ✅ Проверка работы

Серверам Opera требуется **10–15 секунд** после запуска на поиск и тестирование лучшего узла.

```sh
# Проверка внешнего IP через прокси:
curl -fsSL --socks5-hostname 127.0.0.1:1080 https://api.ipify.org

# Просмотр журнала подключения:
logread | grep -i opera
```

---

## 🗑️ Удаление

```sh
/opt/etc/init.d/S*opera-proxy stop
rm -f /opt/etc/init.d/S*opera-proxy /opt/etc/opera-proxy.conf
opkg remove opera-proxy
rm -f /opt/etc/opkg/sw.ext.io.conf
ndmc -c "no interface $(ndmc -c 'show running-config' | awk '/^interface Proxy[0-9]+/ {cur=$2} /description.*Opera/ {print cur; exit}')"
ndmc -c "system configuration save"
```

---

## 🔗 Источники

- Ядро прокси: [Alexey71/opera-proxy](https://github.com/Alexey71/opera-proxy) (форк с поддержкой SNI и DoH)
