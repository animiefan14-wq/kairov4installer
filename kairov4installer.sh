#!/usr/bin/env bash
#
# ██╗  ██╗ █████╗ ██╗██████╗  ██████╗     ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     ███████╗██████╗
# ██║ ██╔╝██╔══██╗██║██╔══██╗██╔═══██╗    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     ██╔════╝██╔══██╗
# █████╔╝ ███████║██║██████╔╝██║   ██║    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     █████╗  ██████╔╝
# ██╔═██╗ ██╔══██║██║██╔══██╗██║   ██║    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     ██╔══╝  ██╔══██╗
# ██║  ██╗██║  ██║██║██║  ██║╚██████╔╝    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗███████╗██║  ██║
# ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝
# Pterodactyl Panel + Wings One‑Click Installer – V4
# github.com/YOUR_USER/kairov4installer

set -euo pipefail

# ---- Colors ----
BOLD="\033[1m"
RESET="\033[0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"

# ---- Spinner for long tasks ----
spinner() {
    local pid=$1
    local delay=0.15
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ---- Display big banner ----
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
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ---- Helper: colored ask ----
ask() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    local input
    read -r -p "$(echo -e "${CYAN}${prompt} ${YELLOW}[${default}]${RESET}: ")" input
    input="${input:-$default}"
    export "$var_name"="$input"
}

# ---- Check if root ----
require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}✘ This script must be run as root! Use sudo.${RESET}"
        exit 1
    fi
}

# ---- Check OS compatibility ----
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os=$ID
        ver=$VERSION_ID
    else
        echo -e "${RED}✘ Cannot detect OS.${RESET}"
        exit 1
    fi
    # Only allow supported distros
    case "$os" in
        ubuntu|debian|rocky|almalinux)
            echo -e "${GREEN}✔ Detected $os $ver${RESET}"
            ;;
        *)
            echo -e "${RED}✘ Unsupported OS: $os. Only Ubuntu, Debian, Rocky, AlmaLinux are supported.${RESET}"
            exit 1
            ;;
    esac
}

# ---- Pre-install checks for panel ----
panel_exists() {
    [ -d /var/www/pterodactyl ] && return 0
    return 1
}

wings_exists() {
    systemctl is-active --quiet wings 2>/dev/null && return 0
    [ -f /usr/local/bin/wings ] && return 0
    return 1
}

# ---- Install panel (official installer) ----
install_panel() {
    banner
    echo -e "${WHITE}${BOLD}▶ PANEL INSTALLATION${RESET}"
    echo -e "${YELLOW}We need a few details to proceed.${RESET}\n"

    if panel_exists; then
        echo -e "${RED}✘ Panel already installed in /var/www/pterodactyl!${RESET}"
        echo -e "${YELLOW}Use uninstall option first if you want a fresh install.${RESET}"
        return 1
    fi

    ask "Enter panel FQDN (e.g. panel.yourdomain.com)"   PTERODACTYL_PANEL_URL
    ask "Admin email"                                    PTERODACTYL_PANEL_EGG_AUTHOR_EMAIL
    ask "SSL email (Let's Encrypt)"                      PTERODACTYL_PANEL_SSL_EMAIL "$PTERODACTYL_PANEL_EGG_AUTHOR_EMAIL"
    ask "Timezone (e.g. Europe/London)"                  PTERODACTYL_PANEL_TIMEZONE "UTC"
    ask "Database password (leave empty to generate)"    PTERODACTYL_PANEL_DB_PASSWORD "$(openssl rand -base64 32)"

    export PTERODACTYL_PANEL_DB_HOST="127.0.0.1"
    export PTERODACTYL_PANEL_DB_PORT="3306"
    export PTERODACTYL_PANEL_DB_NAME="pterodactyl"
    export PTERODACTYL_PANEL_DB_USER="pterodactyl"

    echo -e "\n${MAGENTA}➤ Running official panel installer...${RESET}"
    # The official script expects "yes" to proceed interactively if needed;
    # we pipe "yes" to make it fully automatic.
    (curl -sSL https://pterodactyl-installer.se | bash) <<< "yes" &
    spinner $!
    echo -e "\n${GREEN}✔ Panel installation finished!${RESET}"
    echo -e "${CYAN}Save the credentials shown above.${RESET}"
    read -r -p "Press Enter to continue..."
}

# ---- Install Wings (official installer) ----
install_wings() {
    banner
    echo -e "${WHITE}${BOLD}▶ WINGS INSTALLATION${RESET}"

    if wings_exists; then
        echo -e "${RED}✘ Wings already installed or running!${RESET}"
        return 1
    fi

    ask "Panel URL (https://panel.yourdomain.com)"       WINGS_PANEL_URL
    ask "Node FQDN (full domain of this node)"           WINGS_NODE_FQDN
    ask "API key (create in Admin → Application API)"    WINGS_API_KEY
    ask "Node name (e.g. node1)"                         WINGS_NODE_NAME

    echo -e "\n${MAGENTA}➤ Running Wings installer...${RESET}"
    # The wings installer needs the env vars; we call it with --wings-install
    (curl -sSL https://pterodactyl-installer.se | bash -s -- --wings-install) &
    spinner $!
    echo -e "\n${GREEN}✔ Wings installation finished!${RESET}"
    echo -e "${CYAN}Check status with: systemctl status wings${RESET}"
    read -r -p "Press Enter to continue..."
}

# ---- Install Blueprint (framework) ----
install_blueprint() {
    banner
    echo -e "${WHITE}${BOLD}▶ BLUEPRINT INSTALLATION${RESET}"

    if ! panel_exists; then
        echo -e "${RED}✘ Pterodactyl panel is not installed. Install the panel first.${RESET}"
        return 1
    fi

    echo -e "${MAGENTA}➤ Fetching Blueprint installer...${RESET}"
    (bash <(curl -s https://blueprint.zip)) &
    spinner $!
    echo -e "\n${GREEN}✔ Blueprint installed!${RESET}"
    read -r -p "Press Enter to continue..."
}

# ---- Uninstall everything ----
uninstall_all() {
    banner
    echo -e "${RED}${BOLD}⚠ FULL UNINSTALL${RESET}"
    echo -e "${YELLOW}This will completely remove Panel, Wings, databases, and configs.${RESET}"
    read -r -p "$(echo -e "${RED}Type 'yes' to confirm: ${RESET}")" confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${CYAN}Uninstall cancelled.${RESET}"
        return
    fi

    echo -e "${MAGENTA}➤ Uninstalling Panel...${RESET}"
    (curl -sSL https://pterodactyl-installer.se | bash -s -- --panel-uninstall --force) &
    spinner $!

    echo -e "${MAGENTA}➤ Uninstalling Wings...${RESET}"
    (curl -sSL https://pterodactyl-installer.se | bash -s -- --wings-uninstall --force) &
    spinner $!

    echo -e "\n${GREEN}✔ Everything has been removed.${RESET}"
    read -r -p "Press Enter to continue..."
}

# ---- Main menu ----
main_menu() {
    while true; do
        banner
        echo -e "${CYAN}${BOLD}Choose what to do:${RESET}\n"
        echo -e "  ${GREEN}1)${RESET} Install Pterodactyl Panel"
        echo -e "  ${GREEN}2)${RESET} Install Wings (Daemon)"
        echo -e "  ${GREEN}3)${RESET} Install Panel + Wings (in one go)"
        echo -e "  ${GREEN}4)${RESET} Install Blueprint extension"
        echo -e "  ${RED}5)${RESET} UNINSTALL everything (panel + wings)"
        echo -e "  ${WHITE}6)${RESET} Exit"
        echo ""
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

# ---- Entry point ----
require_root
check_os
main_menu
