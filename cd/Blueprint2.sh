
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN} $1 ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Function to print status messages
print_status() {
    echo -e "${YELLOW}⏳ $1...${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${MAGENTA}⚠️  $1${NC}"
}

# Function to check if command succeeded
check_success() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$2"
        return 1
    fi
}

# Function to animate progress
animate_progress() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\'
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Welcome animation
welcome_animation() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}"
    echo "██████╗ ██╗  ██╗ █████╗ ██████╗ ███╗   ███╗"
    echo "██╔══██╗██║  ██║██╔══██╗██╔══██╗████╗ ████║"
    echo "██║  ██║███████║███████║██████╔╝██╔████╔██║"
    echo "██║  ██║██╔══██║██╔══██║██╔══██╗██║╚██╔╝██║"
    echo "██████╔╝██║  ██║██║  ██║██║  ██║██║ ╚═╝ ██║"
    echo "╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝"
    echo -e "${NC}"
    echo -e "${CYAN}              Blueprint Installer${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    sleep 2
}

# Function: Install (Fresh Setup)
install_nobita() {
# ================= VARIABLES =================
export PTERODACTYL_DIRECTORY=/www/wwwroot/panel.obsidianhosting.in

# ================= START =================
header
step "Installing base dependencies (curl, wget, unzip)"
apt update -y && apt install -y curl wget unzip ca-certificates git gnupg zip || fail "Deps install failed"
ok "Base dependencies installed"

step "Switching to Pterodactyl directory"
cd "$PTERODACTYL_DIRECTORY" || fail "Pterodactyl directory not found"

step "Downloading Blueprint Framework (latest)"
wget "$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | grep 'release.zip' | cut -d '"' -f 4)" -O "$PTERODACTYL_DIRECTORY/release.zip"
unzip -o release.zip || fail "Unzip failed"
ok "Blueprint downloaded & extracted"

# ================= NODE.JS =================
step "Installing Node.js 20.x"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
> /etc/apt/sources.list.d/nodesource.list

apt update -y && apt install -y nodejs || fail "Node.js install failed"
ok "Node.js installed"

# ================= YARN & DEPENDENCIES =================
step "Installing Yarn & Node dependencies"
npm i -g yarn || fail "Yarn install failed"
yarn install || fail "Yarn dependencies failed"
ok "Node dependencies ready"

# ================= BLUEPRINT CONFIG =================
step "Creating .blueprintrc configuration"
cat <<EOF > "$PTERODACTYL_DIRECTORY/.blueprintrc"
WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";
EOF
ok ".blueprintrc created"

# ================= PERMISSIONS =================
step "Setting permissions"
chmod +x "$PTERODACTYL_DIRECTORY/blueprint.sh" || fail "Permission failed"
chown -R www-data:www-data "$PTERODACTYL_DIRECTORY"
ok "Permissions fixed"

# ================= RUN BLUEPRINT =================
step "Launching Blueprint installer"
bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

# ================= DONE =================
echo -e "\n${G}🎉 Blueprint UI Installation Complete!${N}"
echo -e "${Y}Panel breathe kar raha hai… theme lagao, flex maro 😏${N}"
}

# Function: Reinstall (Rerun Only)
reinstall_nobita() {
    print_header "REINSTALLING DHARM HOSTING"
    print_status "Starting reinstallation"
    blueprint -rerun-install > /dev/null 2>&1 &
    animate_progress $! "Reinstalling"
    check_success "Reinstallation completed" "Reinstallation failed"
}

# Function: Update Nobita Hosting
update_nobita() {
    print_header "UPDATING DHARM HOSTING"
    print_status "Starting update"
    blueprint -upgrade > /dev/null 2>&1 &
    animate_progress $! "Updating"
    check_success "Update completed" "Update failed"
}

# Function to display the main menu
show_menu() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}           🔧 BLUEPRINT INSTALLER               ${NC}"
    echo -e "${CYAN}              Dharm Hosting                   ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e ""
    echo -e "${WHITE}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                📋 MAIN MENU                   ║${NC}"
    echo -e "${WHITE}╠═══════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║   ${GREEN}1)${NC} ${CYAN}Fresh Install${NC}                         ${WHITE}║${NC}"
    echo -e "${WHITE}║   ${GREEN}2)${NC} ${CYAN}Reinstall (Rerun Only)${NC}                ${WHITE}║${NC}"
    echo -e "${WHITE}║   ${GREEN}3)${NC} ${CYAN}Update Dharm Hosting${NC}                 ${WHITE}║${NC}"
    echo -e "${WHITE}║   ${GREEN}0)${NC} ${RED}Exit${NC}                               ${WHITE}║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📝 Select an option [0-3]: ${NC}"
}

# Main execution
welcome_animation

while true; do
    show_menu
    read -r choice
    
    case $choice in
        1) install_nobita ;;
        2) reinstall_nobita ;;
        3) update_nobita ;;
        0) 
            echo -e "${GREEN}Exiting Blueprint Installer...${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${CYAN}           Thank you for using our tools!       ${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            sleep 2
            exit 0 
            ;;
        *) 
            print_error "Invalid option! Please choose between 0-3"
            sleep 2
            ;;
    esac
    
    echo -e ""
    read -p "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" -n 1
done
