#!/usr/bin/env bash
#
# KAIRO INSTALLER V4 – Fully Self‑Contained
# No external installers. Only downloads official source files.
# github.com/animiefan14-wq/kairov4installer

set -euo pipefail

# ----- Colors -----
BOLD="\033[1m"
RESET="\033[0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"

# ----- Helper: spinner -----
spinner() {
    local pid=$1
    local delay=0.15
    local spinstr='|/-\'
    printf "  "
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\b\b\b[%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\b\b\b\b    \n"
}

# ----- Banner -----
banner() {
    clear
    echo -e "${MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║   ██╗  ██╗ █████╗ ██╗██████╗  ██████╗   ██╗   ██╗██╗  ██╗  ║"
    echo "║   ██║ ██╔╝██╔══██╗██║██╔══██╗██╔═══██╗  ██║   ██║██║  ██║  ║"
    echo "║   █████╔╝ ███████║██║██████╔╝██║   ██║  ██║   ██║███████║  ║"
    echo "║   ██╔═██╗ ██╔══██║██║██╔══██╗██║   ██║  ╚██╗ ██╔╝╚════██║  ║"
    echo "║   ██║  ██╗██║  ██║██║██║  ██║╚██████╔╝   ╚████╔╝      ██║  ║"
    echo "║   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝     ╚═══╝       ╚═╝  ║"
    echo "║                                                          ║"
    echo "║           PTERODACTYL AUTO INSTALLER v4.0                ║"
    echo "║                 (SELF‑CONTAINED)                         ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ----- Safe input -----
ask() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local input
    read -r -p "$(echo -e "${CYAN}${prompt} ${YELLOW}[${default}]${RESET}: ")" input
    input="${input:-$default}"
    export "$var_name"="$input"
}

confirm() {
    local msg="$1"
    local ans
    read -r -p "$(echo -e "${YELLOW}${msg} [y/N]: ${RESET}")" ans
    case "$ans" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}✘ Run as root.${RESET}"
        exit 1
    fi
}

# ----- OS & Dependency Setup -----
setup_dependencies() {
    echo -e "${CYAN}Updating system & installing base packages...${RESET}"
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq && apt-get upgrade -y -qq
            apt-get install -y -qq curl wget tar unzip git software-properties-common gnupg lsb-release ca-certificates apt-transport-https
            # PHP repo
            curl -sSL https://packages.sury.org/php/README.txt | bash -s -- -qq
            apt-get update -qq
            apt-get install -y -qq php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl,redis} nginx mariadb-server redis-server composer
            ;;
        rocky|almalinux)
            dnf -y update
            dnf -y install epel-release
            dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm
            dnf module reset php -y
            dnf module enable php:remi-8.1 -y
            dnf -y install curl wget tar unzip git nginx mariadb-server redis php php-{cli,gd,mysqlnd,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl,redis}
            # Composer
            curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
            ;;
        *)
            echo -e "${RED}Unsupported OS.${RESET}"
            exit 1
            ;;
    esac
    systemctl enable --now nginx mariadb redis
}

# ----- Install Panel (manual) -----
install_panel() {
    banner
    echo -e "${WHITE}▶ SELF‑CONTAINED PANEL INSTALL${RESET}\n"

    if [ -d /var/www/pterodactyl ]; then
        echo -e "${RED}Panel already exists. Uninstall first.${RESET}"
        read -r -p "Press Enter..."
        return
    fi

    ask "Panel FQDN (e.g. panel.example.com)" PANEL_FQDN
    ask "Admin email" PANEL_EMAIL
    ask "SSL email (Let's Encrypt)" SSL_EMAIL "$PANEL_EMAIL"
    ask "Timezone" TIMEZONE "UTC"
    ask "DB password (empty = auto)" DB_PASS "$(openssl rand -base64 32)"

    if ! confirm "Install Panel now?"; then
        echo -e "${CYAN}Aborted.${RESET}"
        return
    fi

    # Setup dependencies (idempotent)
    setup_dependencies

    # MariaDB secure installation + user/db creation
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS pterodactyl;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

    # Download latest panel release
    mkdir -p /var/www
    cd /var/www
    LATEST_PANEL=$(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -L "https://github.com/pterodactyl/panel/releases/download/${LATEST_PANEL}/panel.tar.gz" -o panel.tar.gz
    tar -xzf panel.tar.gz && mv panel-* pterodactyl
    rm panel.tar.gz
    cd pterodactyl

    # Set permissions
    chmod -R 755 storage bootstrap/cache
    chown -R www-data:www-data *

    # .env file
    cp .env.example .env
    composer install --no-dev --optimize-autoloader -q
    php artisan key:generate --force
    php artisan p:environment:setup --db-host=127.0.0.1 --db-port=3306 --db-name=pterodactyl --db-user=pterodactyl --db-pass="$DB_PASS" --url="https://${PANEL_FQDN}" --timezone="$TIMEZONE" --cache-driver=redis --session-driver=redis --queue-driver=redis --redis-host=127.0.0.1 --redis-port=6379
    php artisan p:environment:mail --driver=mail --email="$PANEL_EMAIL"
    php artisan migrate --seed --force
    php artisan p:user:make --admin=1 --email="$PANEL_EMAIL"

    # Nginx config
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_FQDN};
    root /var/www/pterodactyl/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx

    # SSL via certbot (if domain resolves)
    if host "$PANEL_FQDN" >/dev/null; then
        apt-get install -y -qq certbot python3-certbot-nginx 2>/dev/null || dnf install -y certbot python3-certbot-nginx 2>/dev/null
        certbot --nginx -d "$PANEL_FQDN" --non-interactive --agree-tos -m "$SSL_EMAIL"
    fi

    echo -e "${GREEN}✔ Panel installed! Visit https://${PANEL_FQDN}${RESET}"
    read -r -p "Press Enter..."
}

# ----- Install Wings (manual) -----
install_wings() {
    banner
    echo -e "${WHITE}▶ SELF‑CONTAINED WINGS INSTALL${RESET}\n"

    if systemctl is-active --quiet wings || [ -f /usr/local/bin/wings ]; then
        echo -e "${RED}Wings already installed.${RESET}"
        read -r -p "Press Enter..."
        return
    fi

    ask "Panel URL (https://panel.domain.com)" PANEL_URL
    ask "Node FQDN" NODE_FQDN
    ask "API key" API_KEY
    ask "Node name" NODE_NAME

    if ! confirm "Install Wings?"; then
        echo -e "${CYAN}Aborted.${RESET}"
        return
    fi

    # Docker
    curl -fsSL https://get.docker.com | bash
    systemctl enable --now docker

    # Wings binary
    LATEST_WINGS=$(curl -s https://api.github.com/repos/pterodactyl/wings/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -L "https://github.com/pterodactyl/wings/releases/download/${LATEST_WINGS}/wings_linux_amd64" -o /usr/local/bin/wings
    chmod +x /usr/local/bin/wings

    mkdir -p /etc/pterodactyl
    cat > /etc/pterodactyl/config.yml <<EOF
debug: false
app_name: "Pterodactyl"
uuid: "$(uuidgen)"
token_id: "$API_KEY"
token: "$API_KEY"
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
  upload_limit: 100
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_address: 0.0.0.0
    port: 2022
  archive_directory: /var/lib/pterodactyl/archives
  backup_directory: /var/lib/pterodactyl/backups
  log_directory: /var/log/pterodactyl
  tmp_directory: /tmp/pterodactyl
  username: pterodactyl
  timezone: UTC
docker:
  socket: /var/run/docker.sock
  autoupdate: false
  debug: false
throttle:
  enabled: false
  lines: 2000
  maximum_trigger: 5
  decay: 60
  kill_signal: SIGINT
remote: https://$NODE_FQDN
allowed_mounts: []
deny_mounts: []
EOF

    # Systemd service
    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=65536
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now wings

    echo -e "${GREEN}✔ Wings installed! Check: systemctl status wings${RESET}"
    read -r -p "Press Enter..."
}

# ----- Blueprint (manual) -----
install_blueprint() {
    banner
    echo -e "${WHITE}▶ BLUEPRINT INSTALL${RESET}\n"
    if [ ! -d /var/www/pterodactyl ]; then
        echo -e "${RED}Panel not installed.${RESET}"
        read -r -p "Press Enter..."
        return
    fi
    cd /var/www/pterodactyl
    # Blueprint download
    curl -sSL https://blueprint.zip -o blueprint.zip
    unzip -o blueprint.zip
    chmod +x blueprint.sh
    ./blueprint.sh
    rm blueprint.zip
    echo -e "${GREEN}✔ Blueprint added.${RESET}"
    read -r -p "Press Enter..."
}

# ----- Uninstall -----
uninstall_all() {
    banner
    echo -e "${RED}⚠ FULL UNINSTALL${RESET}"
    read -r -p "Type 'yes' to confirm: " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}Cancelled.${RESET}"
        return
    fi
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true
    rm -f /usr/local/bin/wings
    rm -rf /etc/pterodactyl
    rm -f /etc/systemd/system/wings.service
    systemctl daemon-reload
    rm -rf /var/www/pterodactyl
    mysql -u root -e "DROP DATABASE IF EXISTS pterodactyl; DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
    echo -e "${GREEN}✔ Everything removed.${RESET}"
    read -r -p "Press Enter..."
}

# ----- Menu -----
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}${BOLD}Choose an option:${RESET}\n"
        echo -e "  ${GREEN}1)${RESET} Install Panel"
        echo -e "  ${GREEN}2)${RESET} Install Wings"
        echo -e "  ${GREEN}3)${RESET} Install Panel + Wings (one go)"
        echo -e "  ${GREEN}4)${RESET} Install Blueprint extension"
        echo -e "  ${RED}5)${RESET} UNINSTALL everything"
        echo -e "  ${WHITE}6)${RESET} Exit\n"
        read -r -p "$(echo -e "${YELLOW}Enter choice [1-6]: ${RESET}")" choice
        case $choice in
            1) install_panel ;;
            2) install_wings ;;
            3) install_panel && install_wings ;;
            4) install_blueprint ;;
            5) uninstall_all ;;
            6) echo -e "${GREEN}Goodbye!${RESET}"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${RESET}"; sleep 1 ;;
        esac
    done
}

require_root
main_menu
