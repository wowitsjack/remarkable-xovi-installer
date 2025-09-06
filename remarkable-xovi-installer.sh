#!/bin/bash

# XOVI + AppLoader Installation Script for reMarkable Devices (Staged Version)
# Version: 3.0.4
# By: https://github.com/wowitsjack/
# Description: Complete automated installation of XOVI extension framework and AppLoader for rM1 & rM2
# Split into stages to handle hashtable rebuild connection termination
# Supports: reMarkable 1 & reMarkable 2 (rMPP coming soon!)

set -e  # Exit on any error

# Configuration
REMARKABLE_IP=""
REMARKABLE_PASSWORD=""
DEVICE_TYPE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_NAME=""
STAGE_FILE=".koreader_install_stage"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

highlight() {
    echo -e "${PURPLE}[SETUP]${NC} $1"
}

# Stage management functions
save_stage() {
    local stage="$1"
    local ip="$2"
    local password="$3"
    local device_type="$4"
    local backup_name="$5"
    cat > "$STAGE_FILE" << EOF
STAGE=$stage
REMARKABLE_IP=$ip
REMARKABLE_PASSWORD=$password
DEVICE_TYPE=$device_type
BACKUP_NAME=$backup_name
EOF
}

load_stage() {
    if [[ -f "$STAGE_FILE" ]]; then
        source "$STAGE_FILE"
        return 0
    fi
    return 1
}

clear_stage() {
    rm -f "$STAGE_FILE"
}

# Function to display device setup instructions
show_device_setup() {
    echo
    highlight "===================================================="
    highlight "     reMarkable Device Setup Instructions"
    highlight "===================================================="
    echo
    info "To find your device's IP address and SSH password:"
    info "1. On your reMarkable device, go to:"
    info "   Settings > Help > Copyrights and licenses"
    info "2. Scroll to the bottom of that page"
    info "3. You'll find your IP address and SSH password there"
    highlight "===================================================="
    echo
}

# Function to show WiFi setup instructions before installation
show_wifi_setup_instructions() {
    echo
    highlight "======================================================================="
    highlight "                    Pre-Installation WiFi Setup"
    highlight "======================================================================="
    echo
    warn "IMPORTANT: Before proceeding with installation, please ensure your device is properly configured."
    echo
    info "Step 1: Connect to Home WiFi (BACKUP CONNECTION)"
    info "• Go to Settings > WiFi on your reMarkable device"
    info "• Connect to your home WiFi network"
    info "• This provides a backup connection if USB ethernet fails during installation"
    info "• Make note of the WiFi IP address shown in Settings > Help > Copyrights and licenses"
    echo
    info "Step 2: Disable WiFi for Stable Installation"
    info "• After confirming WiFi connection works, DISABLE WiFi in Settings > WiFi"
    info "• This prevents connection switching during the installation process"
    info "• The installation will use the more reliable USB ethernet connection"
    echo
    info "Why this setup is important:"
    info "• WiFi provides emergency access if something goes wrong"
    info "• USB ethernet (10.11.99.1) is more stable for the installation process"
    info "• Disabling WiFi prevents IP address changes during device reboots"
    echo
    highlight "======================================================================="
    echo
    read -p "Have you connected to WiFi AND then disabled it as instructed? (y/N): " wifi_setup_confirm
    if [[ ! "$wifi_setup_confirm" =~ ^[Yy]$ ]]; then
        echo
        info "Please complete the WiFi setup steps above and run the installation again."
        info "This setup provides the most stable installation experience."
        return 1
    fi
    echo
    log "WiFi setup confirmed - proceeding with installation using USB ethernet"
    return 0
}

# Function to detect and set device type
get_device_type() {
    echo
    highlight "===================================================================="
    highlight "   reMarkable XOVI + AppLoader Installation Script v3.0.1"
    highlight "===================================================================="
    echo
    info "Detecting device architecture..."
    
    # Auto-detect device type based on architecture
    if [[ -n "$REMARKABLE_IP" ]] && [[ -n "$REMARKABLE_PASSWORD" ]]; then
        local arch_result
        arch_result=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "uname -m" 2>/dev/null || echo "unknown")
        
        case "$arch_result" in
            "armv7l")
                DEVICE_TYPE="rM2"
                info "Detected: reMarkable 2 (armv7l architecture)"
                ;;
            "armv6l")
                DEVICE_TYPE="rM1"
                info "Detected: reMarkable 1 (armv6l architecture)"
                ;;
            *)
                warn "Unable to auto-detect device type. Defaulting to rM2."
                DEVICE_TYPE="rM2"
                ;;
        esac
    else
        warn "No connection configured yet. Defaulting to rM2."
        DEVICE_TYPE="rM2"
    fi
    
    echo
    info "Supported Devices:"
    info "• reMarkable 1 (rM1) - SUPPORTED"
    info "• reMarkable 2 (rM2) - SUPPORTED"
    info "• reMarkable Paper Pro (rMPP) - COMING SOON!"
    echo
    info "Proceeding with $DEVICE_TYPE installation..."
    log "Device type set: $DEVICE_TYPE"
}

# Function to get reMarkable IP address
get_remarkable_ip() {
    if [[ -z "$REMARKABLE_IP" ]]; then
        echo
        info "Please enter your reMarkable device's IP address:"
        info "(Found in Settings > Help > Copyrights and licenses)"
        while true; do
            read -p "IP Address [default: 10.11.99.1]: " input_ip
            if [[ -z "$input_ip" ]]; then
                REMARKABLE_IP="10.11.99.1"
                break
            elif [[ "$input_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                REMARKABLE_IP="$input_ip"
                break
            else
                error "Invalid IP address format. Please enter a valid IP (e.g., 10.11.99.1)"
            fi
        done
    fi
    log "Using IP address: $REMARKABLE_IP"
}

# Function to force new IP address entry (for connection retry)
get_remarkable_ip_retry() {
    echo
    warn "Connection failed with IP: $REMARKABLE_IP"
    info "Please enter a NEW reMarkable device IP address:"
    info "(Found in Settings > Help > Copyrights and licenses)"
    while true; do
        read -p "New IP Address (required): " input_ip
        if [[ -z "$input_ip" ]]; then
            error "IP address cannot be empty. Please enter a valid IP address."
        elif [[ "$input_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            REMARKABLE_IP="$input_ip"
            log "Updated IP address: $REMARKABLE_IP"
            break
        else
            error "Invalid IP address format. Please enter a valid IP (e.g., 10.11.99.1)"
        fi
    done
}

# Function to force new password entry (for connection retry)
get_remarkable_password_retry() {
    echo
    warn "Password may be incorrect. Please enter a NEW SSH password:"
    info "(Found in Settings > Help > Copyrights and licenses)"
    echo -n "New Password: "
    read -s REMARKABLE_PASSWORD
    echo
    
    if [[ -z "$REMARKABLE_PASSWORD" ]]; then
        error "Password cannot be empty"
        exit 1
    fi
}

# Function to get reMarkable password securely
get_remarkable_password() {
    if [[ -z "$REMARKABLE_PASSWORD" ]]; then
        echo
        info "Please enter your reMarkable SSH password:"
        info "(Found in Settings > Help > Copyrights and licenses)"
        echo -n "Password: "
        read -s REMARKABLE_PASSWORD
        echo
        
        if [[ -z "$REMARKABLE_PASSWORD" ]]; then
            error "Password cannot be empty"
            exit 1
        fi
    fi
}

# Function to check if sshpass is available
check_sshpass() {
    if ! command -v sshpass &>/dev/null; then
        error "sshpass is required but not installed."
        error "Please install sshpass:"
        error "  Ubuntu/Debian: sudo apt-get install sshpass"
        error "  macOS: brew install sshpass"
        error "  Arch: sudo pacman -S sshpass"
        exit 1
    fi
}

# Function to check WiFi status and warn user
# COMMENTED OUT: WiFi blocking functionality disabled per user request
# check_wifi_status() {
#     log "Checking device WiFi status..."
#
#     # Check if device has WiFi enabled
#     local wifi_status
#     wifi_status=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@$REMARKABLE_IP "ip route | grep wlan0" 2>/dev/null || echo "")
#
#     if [[ -n "$wifi_status" ]]; then
#         echo
#         warn "WARNING: WiFi appears to be enabled on your reMarkable device!"
#         warn "WiFi can interfere with the staged installation process."
#         echo
#         info "WiFi interference can cause:"
#         info "• SSH connection to switch from USB to WiFi IP after reboot"
#         info "• Stage 2 connection failures due to IP address changes"
#         info "• Installation interruptions and incomplete setups"
#         echo
#         warn "STRONGLY RECOMMENDED: Disable WiFi before proceeding"
#         echo
#         info "To disable WiFi on your reMarkable:"
#         info "1. Go to Settings > WiFi"
#         info "2. Turn off WiFi completely"
#         info "3. Ensure only USB connection is active"
#         echo
#         read -p "Have you disabled WiFi and want to continue? (y/N): " wifi_confirm
#         if [[ ! "$wifi_confirm" =~ ^[Yy]$ ]]; then
#             info "Please disable WiFi and run the script again."
#             info "This will ensure a stable installation process."
#             exit 0
#         fi
#         echo
#         log "Proceeding with installation (WiFi warning acknowledged)"
#     else
#         log "WiFi disabled - good for stable installation"
#     fi
# }

# Function to check reMarkable connectivity and verify password
check_remarkable_connection() {
    log "Checking reMarkable connectivity..."
    
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@$REMARKABLE_IP "echo 'Connected'" &> /dev/null; then
            log "Successfully connected to reMarkable"
            # COMMENTED OUT: WiFi status check disabled per user request
            # check_wifi_status
            return 0
        else
            if [[ $attempt -eq $max_attempts ]]; then
                error "Cannot connect to reMarkable at $REMARKABLE_IP after $max_attempts attempts"
                error "Please check:"
                error "  1. reMarkable is connected via USB"
                error "  2. SSH is enabled on the device (Settings > Storage > USB web interface > ON)"
                error "  3. The IP address is correct ($REMARKABLE_IP)"
                error "  4. Your password is correct"
                # COMMENTED OUT: WiFi error message disabled per user request
                # error "  5. WiFi is disabled (can interfere with USB connection)"
                exit 1
            else
                warn "Connection attempt $attempt failed. Retrying..."
                echo
                info "The connection may have failed due to:"
                info "• Incorrect IP address (device may have changed networks)"
                info "• Incorrect SSH password"
                info "• Device not ready or SSH disabled"
                echo
                info "Let's reconfigure the connection details:"
                get_remarkable_ip_retry
                get_remarkable_password_retry
                ((attempt++))
            fi
        fi
    done
}

# Function to check device architecture
check_device_architecture() {
    log "Checking device architecture..."
    ARCH=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "uname -m")
    case "$ARCH" in
        "armv7l")
            log "Architecture confirmed: $ARCH (reMarkable 2)"
            ;;
        "armv6l")
            log "Architecture confirmed: $ARCH (reMarkable 1)"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            error "This script supports reMarkable 1 (armv6l) and reMarkable 2 (armv7l) only."
            exit 1
            ;;
    esac
}

# Function to create comprehensive backup
create_backup() {
    log "Creating comprehensive system backup..."
    BACKUP_NAME="koreader_backup_$(date +%Y%m%d_%H%M%S)"
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        mkdir -p /home/root/$BACKUP_NAME
        
        # Backup current state information
        echo 'KOReader Installation Backup' > /home/root/$BACKUP_NAME/backup_info.txt
        echo 'Created: \$(date)' >> /home/root/$BACKUP_NAME/backup_info.txt
        echo 'Device: $DEVICE_TYPE' >> /home/root/$BACKUP_NAME/backup_info.txt
        echo 'IP: $REMARKABLE_IP' >> /home/root/$BACKUP_NAME/backup_info.txt
        
        # Check if XOVI already exists and back it up
        if [[ -d /home/root/xovi ]]; then
            echo 'Previous XOVI installation found - backing up' >> /home/root/$BACKUP_NAME/backup_info.txt
            cp -r /home/root/xovi /home/root/$BACKUP_NAME/xovi_backup 2>/dev/null || true
        else
            echo 'No previous XOVI installation found' >> /home/root/$BACKUP_NAME/backup_info.txt
        fi
        
        # Backup shims directory if it exists
        if [[ -d /home/root/shims ]]; then
            echo 'Previous shims found - backing up' >> /home/root/$BACKUP_NAME/backup_info.txt
            cp -r /home/root/shims /home/root/$BACKUP_NAME/shims_backup 2>/dev/null || true
        fi
        
        # Backup xochitl.conf (contains SSH password and device settings)
        if [[ -f /home/root/.config/remarkable/xochitl.conf ]]; then
            echo 'Backing up xochitl.conf (contains SSH password)' >> /home/root/$BACKUP_NAME/backup_info.txt
            cp /home/root/.config/remarkable/xochitl.conf /home/root/$BACKUP_NAME/ 2>/dev/null || echo 'Failed to backup xochitl.conf' >> /home/root/$BACKUP_NAME/backup_info.txt
            
            # Extract SSH password for backup record
            if [[ -f /home/root/$BACKUP_NAME/xochitl.conf ]]; then
                ssh_password=\$(grep -E '^DeveloperPassword=' /home/root/$BACKUP_NAME/xochitl.conf | cut -d'=' -f2 2>/dev/null || echo 'not found')
                echo \"SSH Password: \$ssh_password\" >> /home/root/$BACKUP_NAME/backup_info.txt
            fi
        else
            echo 'xochitl.conf not found - SSH password not backed up' >> /home/root/$BACKUP_NAME/backup_info.txt
        fi
        
        # Record current system state
        systemctl is-active xochitl > /home/root/$BACKUP_NAME/xochitl_status.txt 2>/dev/null || echo 'unknown' > /home/root/$BACKUP_NAME/xochitl_status.txt
        ls -la /home/root/ > /home/root/$BACKUP_NAME/root_directory_before.txt 2>/dev/null || true
        
        # Create restore script
        cat > /home/root/$BACKUP_NAME/restore.sh << 'RESTORE_EOF'
#!/bin/bash
# KOReader Installation Restore Script
# This script will completely remove KOReader and XOVI installations

echo 'Starting KOReader/XOVI removal and system restore...'

# Stop XOVI services without killing USB ethernet
# Instead of using ./stop (which may disable USB gadgets), stop services individually
systemctl stop xochitl.service 2>/dev/null || true
if pidof xochitl; then
    kill -15 $(pidof xochitl) 2>/dev/null || true
fi
# Note: NOT calling ./stop to preserve USB ethernet functionality

# Remove XOVI completely
rm -rf /home/root/xovi 2>/dev/null || true

# Remove shims
rm -rf /home/root/shims 2>/dev/null || true

# Remove xovi-tripletap completely
systemctl stop xovi-tripletap 2>/dev/null || true
systemctl disable xovi-tripletap 2>/dev/null || true
rm -f /etc/systemd/system/xovi-tripletap.service 2>/dev/null || true
rm -rf /home/root/xovi-tripletap 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# Remove any leftover files
rm -f /home/root/xovi.so 2>/dev/null || true
rm -f /home/root/xovi-arm32.so 2>/dev/null || true
rm -f /home/root/install-xovi-for-rm 2>/dev/null || true
rm -f /home/root/koreader-remarkable.zip 2>/dev/null || true
rm -f /home/root/extensions-arm32-0.5.0.zip 2>/dev/null || true
rm -f /home/root/qt-resource-rebuilder.so 2>/dev/null || true
rm -f /home/root/appload.so 2>/dev/null || true
rm -f /home/root/qtfb-shim*.so 2>/dev/null || true

# Remove any KOReader directories that might exist
rm -rf /home/root/koreader 2>/dev/null || true

# Restore previous installations if they existed
if [[ -d ./xovi_backup ]]; then
    echo 'Restoring previous XOVI installation...'
    cp -r ./xovi_backup /home/root/xovi
fi

if [[ -d ./shims_backup ]]; then
    echo 'Restoring previous shims...'
    cp -r ./shims_backup /home/root/shims
fi

# Restart UI to ensure clean state
systemctl restart xochitl

echo 'System restore completed!'
echo 'All KOReader and XOVI traces have been removed.'
RESTORE_EOF

        chmod +x /home/root/$BACKUP_NAME/restore.sh
    "
    
    # Extract and display SSH password information locally
    local ssh_password_info=""
    if sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -f /home/root/$BACKUP_NAME/xochitl.conf" 2>/dev/null; then
        ssh_password_info=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "grep -E '^DeveloperPassword=' /home/root/$BACKUP_NAME/xochitl.conf 2>/dev/null | cut -d'=' -f2 || echo 'Not found'" 2>/dev/null)
    fi
    
    log "Comprehensive backup created: $BACKUP_NAME"
    
    if [[ -n "$ssh_password_info" && "$ssh_password_info" != "Not found" ]]; then
        echo
        highlight "======================================================================"
        highlight "           Device Credentials Backed Up"
        highlight "======================================================================"
        echo
        info "SSH Password extracted from device: $ssh_password_info"
        info "This password is also saved in: /home/root/$BACKUP_NAME/backup_info.txt"
        echo
    fi
    
    log "To restore/remove everything later, run: ssh root@$REMARKABLE_IP '/home/root/$BACKUP_NAME/restore.sh'"
}

# Function to show restore options
show_restore_options() {
    echo
    highlight "====================================================="
    highlight "            Backup and Restore Options"
    highlight "====================================================="
    echo
    info "A comprehensive backup has been created on your device."
    echo
    info "To completely remove KOReader and XOVI later:"
    info "  1. SSH into your device: ssh root@$REMARKABLE_IP"
    info "  2. Run the restore script: /home/root/$BACKUP_NAME/restore.sh"
    echo
    info "This will:"
    info "  • Remove all KOReader files and directories"
    info "  • Remove all XOVI components completely"
    info "  • Remove all shim files and extensions"
    info "  • Restore any previous installations (if they existed)"
    info "  • Restart the reMarkable UI for a clean state"
    echo
}

# Function to download required files
download_files() {
    log "Downloading required files..."
    
    # Create local directory for downloads
    mkdir -p downloads
    cd downloads
    
    # Download XOVI extensions package (ARM32) - using working URLs
    if [[ ! -f "extensions-arm32-testing.zip" ]]; then
        info "Downloading XOVI extensions package..."
        curl -L -o "extensions-arm32-testing.zip" "https://github.com/asivery/rm-xovi-extensions/releases/download/v12-12082025/extensions-arm32-testing.zip"
    fi
    
    # Download AppLoad package
    if [[ ! -f "appload-arm32.zip" ]]; then
        info "Downloading AppLoad package..."
        curl -L -o "appload-arm32.zip" "https://github.com/asivery/rm-appload/releases/download/v0.2.4/appload-arm32.zip"
    fi
    
    # Download XOVI binary
    if [[ ! -f "xovi-arm32.so" ]]; then
        info "Downloading XOVI binary..."
        curl -L -o "xovi-arm32.so" "https://github.com/asivery/xovi/releases/latest/download/xovi-arm32.so"
    fi
    
    # Download KOReader
    if [[ ! -f "koreader-remarkable.zip" ]]; then
        info "Downloading KOReader v2025.08..."
        curl -L -o "koreader-remarkable.zip" "https://github.com/koreader/koreader/releases/download/v2025.08/koreader-remarkable-v2025.08.zip"
    fi
    
    # COMMENTED OUT: Download xovi-tripletap for power button integration (disabled temporarily)
    # if [[ ! -f "xovi-tripletap-main.zip" ]]; then
    #     info "Downloading xovi-tripletap (power button integration)..."
    #     curl -L -o "xovi-tripletap-main.zip" "https://github.com/rmitchellscott/xovi-tripletap/archive/refs/heads/main.zip"
    # fi
    
    # Extract packages if not already done (suppress prompts)
    if [[ ! -d "xovi" ]]; then
        info "Extracting XOVI extensions..."
        unzip -o -q "extensions-arm32-testing.zip"
    fi
    
    if [[ ! -d "appload" ]] && [[ -f "appload-arm32.zip" ]]; then
        info "Extracting AppLoad package..."
        unzip -o -q "appload-arm32.zip"
    fi
    
    # COMMENTED OUT: Extract xovi-tripletap (disabled temporarily)
    # if [[ ! -d "xovi-tripletap-main" ]] && [[ -f "xovi-tripletap-main.zip" ]]; then
    #     info "Extracting xovi-tripletap..."
    #     unzip -o -q "xovi-tripletap-main.zip"
    # fi
    
    cd ..
    log "All files downloaded and prepared"
}

# Function to install XOVI
install_xovi() {
    log "Installing XOVI..."
    
    # Copy all downloaded files to device
    sshpass -p "$REMARKABLE_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null downloads/install-xovi-for-rm downloads/xovi-arm32.so downloads/qt-resource-rebuilder.so downloads/appload.so downloads/qtfb-shim.so downloads/qtfb-shim-32bit.so root@$REMARKABLE_IP:/home/root/
    
    # Run XOVI installation
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root
        chmod +x install-xovi-for-rm
        cp xovi-arm32.so xovi.so
        ./install-xovi-for-rm
        echo 'XOVI installation script completed'
    "
    
    log "XOVI installation completed"
}

# Function to install extensions
install_extensions() {
    log "Installing qt-resource-rebuilder and AppLoad extensions..."
    
    # Copy extensions directly to XOVI extensions directory - this is the correct method
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root
        
        # Ensure extensions directory exists
        mkdir -p /home/root/xovi/extensions.d
        
        # Install qt-resource-rebuilder.so directly into extensions directory
        if [[ -f qt-resource-rebuilder.so ]]; then
            cp qt-resource-rebuilder.so /home/root/xovi/extensions.d/
            chmod +x /home/root/xovi/extensions.d/qt-resource-rebuilder.so
            echo 'qt-resource-rebuilder.so copied to extensions directory'
        else
            echo 'ERROR: qt-resource-rebuilder.so not found'
            exit 1
        fi
        
        # Install appload.so directly into extensions directory
        if [[ -f appload.so ]]; then
            cp appload.so /home/root/xovi/extensions.d/
            chmod +x /home/root/xovi/extensions.d/appload.so
            echo 'appload.so copied to extensions directory'
        else
            echo 'ERROR: appload.so not found'
            exit 1
        fi
        
        # Verify both extensions are properly installed
        if [[ -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]] && [[ -f /home/root/xovi/extensions.d/appload.so ]]; then
            echo 'Both extensions successfully installed in XOVI extensions directory'
            ls -la /home/root/xovi/extensions.d/
        else
            echo 'ERROR: One or more extensions failed to install'
            exit 1
        fi
    "
    
    log "Extensions installed and verified"
}

# Function to setup shim files
setup_shims() {
    log "Setting up qtfb-shim files..."
    
    # Create shims directory and copy shim files
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        mkdir -p /home/root/shims
        cp /home/root/qtfb-shim.so /home/root/shims/ 2>/dev/null || echo 'qtfb-shim.so not found'
        cp /home/root/qtfb-shim-32bit.so /home/root/shims/ 2>/dev/null || echo 'qtfb-shim-32bit.so not found'
        echo 'Shim files setup completed'
    "
    
    log "Shim files configured"
}

# Function to configure AppLoad
configure_appload() {
    log "Configuring AppLoad extension..."
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        echo 'enabled=1' > /home/root/xovi/extensions.d/appload.so.conf
    "
    
    log "AppLoad extension configured"
}

# Function to install xovi-tripletap
install_xovi_tripletap() {
    log "Installing xovi-tripletap (power button integration)..."
    
    # Copy xovi-tripletap files to device
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        mkdir -p /home/root/xovi-tripletap
    "
    
    # Copy all necessary files from extracted directory
    sshpass -p "$REMARKABLE_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r downloads/xovi-tripletap-main/* root@$REMARKABLE_IP:/home/root/xovi-tripletap/
    
    # Setup xovi-tripletap on device
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root/xovi-tripletap
        
        # Detect device architecture and select appropriate evtest binary
        ARCH=\$(uname -m)
        case \$ARCH in
            armv7l|armhf)
                EVTEST_ARCH='arm32'
                ;;
            aarch64|arm64)
                EVTEST_ARCH='arm64'
                ;;
            armv6l)
                # reMarkable 1 uses ARM32 evtest
                EVTEST_ARCH='arm32'
                ;;
            *)
                echo 'Unsupported architecture: \$ARCH, defaulting to arm32'
                EVTEST_ARCH='arm32'
                ;;
        esac
        
        # Copy and setup the appropriate evtest binary
        cp evtest.\$EVTEST_ARCH evtest
        chmod +x evtest
        
        # Make scripts executable
        chmod +x main.sh
        chmod +x enable.sh
        chmod +x uninstall.sh
        
        # Create version file
        echo 'main-\$(date +%Y%m%d)' > version.txt
        
        echo 'xovi-tripletap files prepared successfully'
    "
    
    log "xovi-tripletap installation completed"
}

# Function to enable xovi-tripletap service
enable_xovi_tripletap() {
    log "Enabling xovi-tripletap service..."
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root/xovi-tripletap
        
        # Detect device type for filesystem mounting (rMPP specific)
        if grep -qE 'reMarkable (Ferrari|Chiappa)' /proc/device-tree/model 2>/dev/null; then
            echo 'Detected reMarkable Paper Pro family - remounting filesystem...'
            mount -o remount,rw /
            umount -R /etc || true
        fi
        
        # Install systemd service
        cp xovi-tripletap.service /etc/systemd/system/
        
        # Reload systemd daemon
        systemctl daemon-reload
        
        # Enable and start the service
        systemctl enable xovi-tripletap --now
        
        echo 'xovi-tripletap service enabled and started successfully'
    "
    
    log "xovi-tripletap service enabled and running"
}

# Function to install ethernet fix service
install_ethernet_fix() {
    log "Fixing USB Ethernet Adapter..."
    
    # Get connection details if not already set
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$REMARKABLE_PASSWORD" ]]; then
        echo
        info "Device connection required for ethernet fix..."
        get_remarkable_ip
        get_remarkable_password
    fi
    
    check_sshpass
    
    # Try connecting via current IP first
    if ! sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "echo 'connected'" &>/dev/null; then
        error "Cannot connect to device. Make sure WiFi is enabled and device is accessible."
        return 1
    fi
    
    echo
    info "Executing ethernet fix on device..."
    
    # Execute the ethernet fix directly
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        echo 'Loading g_ether module...'
        modprobe g_ether
        
        echo 'Bringing up usb0 interface...'
        ip link set usb0 up
        
        echo 'Configuring IP address...'
        ip addr add 10.11.99.1/27 dev usb0 2>/dev/null || echo 'IP already configured'
        
        echo 'USB Ethernet Fix completed successfully!'
        echo 'You can now connect via USB at 10.11.99.1'
    "
    
    echo
    log "USB Ethernet fix completed!"
    echo
    info "USB ethernet adapter should now be working at 10.11.99.1"
    info "Try connecting via USB cable if you were using WiFi before"
}

# Function to rebuild hashtable with automatic input
rebuild_hashtable() {
    log "Rebuilding hashtable..."
    warn "This process may take several minutes and will restart the UI..."
    warn "The SSH connection will be terminated - this is normal!"
    echo
    highlight "HASHING. PLEASE WAIT. THIS MAY TAKE A FEW MINUTES"
    echo

    # Verify qt-resource-rebuilder is installed before attempting hashtable rebuild
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        if [[ ! -f /home/root/xovi/extensions.d/qt-resource-rebuilder.so ]]; then
            echo 'ERROR: qt-resource-rebuilder.so not found in extensions directory!'
            echo 'Hashtable rebuild cannot proceed without qt-resource-rebuilder'
            exit 1
        fi
        
        cd /home/root/xovi
        if [[ -f rebuild_hashtable ]]; then
            chmod +x rebuild_hashtable
            
            # Create a modified version of rebuild_hashtable that suppresses interactive prompts
            cat > rebuild_hashtable_auto << 'REBUILD_EOF'
#!/bin/bash

if [[ ! -e '/home/root/xovi/extensions.d/qt-resource-rebuilder.so' ]]; then
    echo \"Please install qt-resource-rebuilder before updating the hashtable\"
    exit 1
fi

# stop systemwide gui process
systemctl stop xochitl.service

if pidof xochitl; then
  kill -15 \$(pidof xochitl)
fi

# make sure the resource-rebuilder folder exists.
mkdir -p /home/root/xovi/exthome/qt-resource-rebuilder

# remove the actual hashtable
rm -f /home/root/xovi/exthome/qt-resource-rebuilder/hashtab

# start update hashtab process - AUTOMATED VERSION (no user prompts)
QMLDIFF_HASHTAB_CREATE=/home/root/xovi/exthome/qt-resource-rebuilder/hashtab QML_DISABLE_DISK_CACHE=1 LD_PRELOAD=/home/root/xovi/xovi.so /usr/bin/xochitl 2>&1 | while IFS= read line; do
  if [[ \"\$line\" == \"[qmldiff]: Hashtab saved to /home/root/xovi/exthome/qt-resource-rebuilder/hashtab\" ]]; then
    # found the completion line, kill the process
    kill -15 \$(pidof xochitl)
  fi
done

# wait then restart systemd service
sleep 5
systemctl start xochitl.service
REBUILD_EOF
            
            chmod +x rebuild_hashtable_auto
            ./rebuild_hashtable_auto
        else
            echo 'rebuild_hashtable script not found, skipping'
        fi
    " 2>/dev/null || true
    
    log "Hashtable rebuild initiated (connection will terminate)"
}

# Enhanced device wait with user interaction
wait_for_device_ready() {
    log "Waiting for device to be ready after restart..."
    info "The device may take 30-60 seconds to fully reboot and accept SSH connections."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "echo 'ready'" &>/dev/null; then
            echo
            log "Device is ready!"
            return 0
        fi
        info "Waiting for device... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
        
        # Offer options halfway through timeout
        if [[ $attempt -eq 15 && $max_attempts -gt 15 ]]; then
            echo
            warn "Device still not responding after 30 seconds..."
            echo
            info "What would you like to do?"
            echo "  1) Keep waiting (recommended - device may still be booting)"
            echo "  2) Wait longer (extend timeout to 60 attempts)"
            echo "  3) Skip and continue (advanced users only)"
            echo "  4) Exit and retry later"
            echo
            
            read -p "Enter your choice (1-4) or press Enter to keep waiting: " choice
            case $choice in
                1|"")
                    info "Continuing to wait..."
                    ;;
                2)
                    max_attempts=60
                    info "Extended timeout to 60 attempts (120 seconds)"
                    ;;
                3)
                    echo
                    warn "Skipping device wait. The device may not be ready!"
                    warn "This may cause the next stage to fail."
                    return 0
                    ;;
                4)
                    info "Exiting. Please ensure your device is powered on and try again."
                    exit 0
                    ;;
                *)
                    info "Invalid choice, continuing to wait..."
                    ;;
            esac
            echo
        fi
    done
    
    echo
    warn "Device not ready after $max_attempts attempts!"
    echo
    info "The device might still be starting up. What would you like to do?"
    echo "  1) Wait another 30 attempts (60 seconds)"
    echo "  2) Continue anyway (may fail)"
    echo "  3) Exit and retry manually"
    echo
    
    while true; do
        read -p "Enter your choice (1-3): " choice
        case $choice in
            1)
                info "Waiting another 30 attempts..."
                wait_for_device_ready
                return $?
                ;;
            2)
                warn "Continuing without device confirmation. Next steps may fail."
                return 0
                ;;
            3)
                info "Exiting. Please check your device and network connection."
                exit 0
                ;;
            *)
                error "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Function to install KOReader
install_koreader() {
    log "Installing KOReader..."
    
    # Copy KOReader to device
    sshpass -p "$REMARKABLE_PASSWORD" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null downloads/koreader-remarkable.zip root@$REMARKABLE_IP:/home/root/
    
    # Extract and setup KOReader - handle existing directory properly
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root
        
        # Remove old KOReader if it exists
        rm -rf koreader 2>/dev/null || true
        
        # Extract KOReader
        unzip -q koreader-remarkable.zip
        
        # Create AppLoad directory structure
        mkdir -p /home/root/xovi/exthome/appload
        
        # Remove old KOReader from AppLoad directory
        rm -rf /home/root/xovi/exthome/appload/koreader 2>/dev/null || true
        
        # Move KOReader to AppLoad directory
        mv /home/root/koreader /home/root/xovi/exthome/appload/
        
        echo 'KOReader extracted and moved to AppLoad directory'
    "
    
    log "KOReader installed and configured"
}

# Function to start XOVI
start_xovi() {
    log "Starting XOVI services..."
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        cd /home/root/xovi
        if [[ -f start ]]; then
            chmod +x start
            ./start
            echo 'XOVI start script executed'
        else
            echo 'XOVI start script not found, may need manual startup'
        fi
    "
    
    log "XOVI services started"
}

# Function to restart reMarkable UI
restart_ui() {
    log "Restarting reMarkable UI..."
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        systemctl restart xochitl
    "
    
    # Wait for UI to restart
    sleep 5
    log "reMarkable UI restarted"
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    # Check if all components are in place
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        echo 'Checking installation components:'
        echo '- XOVI directory:' && ls -la /home/root/xovi/ | head -5
        echo '- Extensions:' && ls -la /home/root/xovi/extensions.d/
        echo '- AppLoad config:' && cat /home/root/xovi/extensions.d/appload.so.conf
        echo '- KOReader:' && ls -la /home/root/xovi/exthome/appload/
        echo '- Shims:' && ls -la /home/root/shims/
    "
    
    log "Installation verification completed"
}

# Function to clean up temporary files
cleanup() {
    log "Cleaning up temporary files..."
    
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        rm -f /home/root/koreader-remarkable.zip
        rm -f /home/root/extensions-arm32-testing.zip
        rm -f /home/root/appload-arm32.zip
        rm -f /home/root/install-xovi-for-rm
        rm -f /home/root/qt-resource-rebuilder.so
        rm -f /home/root/appload.so
        rm -f /home/root/qtfb-shim.so
        rm -f /home/root/qtfb-shim-32bit.so
        rm -f /home/root/xovi-arm32.so
    " 2>/dev/null || true
    
    log "Cleanup completed"
}

# Function for launcher-only installation (XOVI + AppLoad without KOReader)
run_launcher_only() {
    log "======================================================================="
    log "LAUNCHER INSTALLATION: XOVI + AppLoad framework (no apps)"
    log "======================================================================="
    
    # Device and connection setup
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$DEVICE_TYPE" ]]; then
        show_device_setup
        get_device_type
        get_remarkable_ip
        get_remarkable_password
    fi
    
    # Save stage information early
    save_stage "1" "$REMARKABLE_IP" "$REMARKABLE_PASSWORD" "$DEVICE_TYPE" "$BACKUP_NAME"
    
    # Pre-flight checks
    check_sshpass
    check_remarkable_connection
    check_device_architecture
    
    # Create comprehensive backup
    create_backup
    show_restore_options
    
    # Ask for final confirmation (unless forced)
    if [[ "$FORCE_INSTALL" != true ]]; then
        echo
        warn "This will install XOVI + AppLoad launcher framework on your $DEVICE_TYPE device."
        warn "This will modify system files and restart the UI after hashtable rebuild."
        echo
        read -p "Do you want to continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Installation cancelled by user."
            clear_stage
            exit 0
        fi
    else
        log "Skipping confirmation (--force flag used)"
    fi
    
    # Download and prepare files
    download_files
    
    # Installation steps for launcher framework
    install_xovi
    install_extensions  # This must happen BEFORE hashtable rebuild
    setup_shims
    configure_appload
    # install_xovi_tripletap  # COMMENTED OUT: Install power button integration (disabled temporarily)
    rebuild_hashtable   # This will terminate the connection
    
    # Wait for device to be ready after hashtable rebuild
    wait_for_device_ready
    
    # Start XOVI services to make AppLoad available
    start_xovi
    # enable_xovi_tripletap  # COMMENTED OUT: Enable power button service (disabled temporarily)
    restart_ui
    
    # Verify launcher installation
    log "Verifying launcher installation..."
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        echo 'Checking launcher installation components:'
        echo '- XOVI directory:' && ls -la /home/root/xovi/ | head -5
        echo '- Extensions:' && ls -la /home/root/xovi/extensions.d/
        echo '- AppLoad config:' && cat /home/root/xovi/extensions.d/appload.so.conf
        echo '- AppLoad directory structure:' && ls -la /home/root/xovi/exthome/
    "
    
    # Cleanup temporary files
    cleanup
    
    log "======================================================================="
    log "LAUNCHER INSTALLATION COMPLETED SUCCESSFULLY!"
    log "======================================================================="
    echo
    info "AppLoad launcher framework has been installed and configured."
    echo
    info "How to access AppLoad:"
    info "1. Look for 'AppLoad' in the reMarkable sidebar menu"
    info "2. Tap on AppLoad to open the application menu"
    info "3. The menu will be empty until you install applications"
    echo
    info "To install KOReader later, run option 1 (Full Install) or option 9 (Stage 2 only)."
    echo
    info "If AppLoad doesn't appear immediately:"
    info "- Try restarting your reMarkable device completely"
    info "- Wait a few minutes for all services to initialize"
    echo
    
    # Clear stage file on successful completion
    clear_stage
    log "Launcher installation completed!"
}

# Stage 1: Setup, backup, XOVI installation, hashtable rebuild
run_stage1() {
    log "======================================================================="
    log "STAGE 1: Setup, backup, XOVI installation, and hashtable rebuild"
    log "======================================================================="
    
    # Device and connection setup
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$DEVICE_TYPE" ]]; then
        show_device_setup
        get_device_type
        get_remarkable_ip
        get_remarkable_password
    fi
    
    # Save stage information early
    save_stage "1" "$REMARKABLE_IP" "$REMARKABLE_PASSWORD" "$DEVICE_TYPE" "$BACKUP_NAME"
    
    # Pre-flight checks
    check_sshpass
    check_remarkable_connection
    check_device_architecture
    
    # Create comprehensive backup
    create_backup
    show_restore_options
    
    # Ask for final confirmation (unless forced)
    if [[ "$FORCE_INSTALL" != true ]]; then
        echo
        warn "This will run Stage 1 for KOReader and XOVI on your $DEVICE_TYPE device."
        warn "Stage 1 will modify system files and restart the UI after hashtable rebuild."
        echo
        read -p "Do you want to continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Installation cancelled by user."
            clear_stage
            exit 0
        fi
    else
        log "Skipping confirmation (--force flag used)"
    fi
    
    # Download and prepare files
    download_files
    
    # Installation steps for Stage 1
    install_xovi
    install_extensions  # This must happen BEFORE hashtable rebuild
    setup_shims
    configure_appload
    # install_xovi_tripletap  # COMMENTED OUT: Install power button integration (disabled temporarily)
    rebuild_hashtable   # This will terminate the connection
    
    # Save stage information for Stage 2
    save_stage "2" "$REMARKABLE_IP" "$REMARKABLE_PASSWORD" "$DEVICE_TYPE" "$BACKUP_NAME"
    
    log "======================================================================="
    log "STAGE 1 COMPLETED SUCCESSFULLY!"
    log "======================================================================="
    echo
    info "The device UI has been restarted after hashtable rebuild."
    info "Waiting 30 seconds for the device to fully reboot and load..."
    sleep 30
    echo
    highlight "======================================================================"
    highlight "           IMPORTANT: Stage 2 Instructions"
    highlight "======================================================================"
    echo
    info "Stage 1 is complete. Your device should now have:"
    info "• XOVI framework installed and running"
    info "• AppLoad launcher available in the sidebar"
    # info "• xovi-tripletap power button integration active"  # COMMENTED OUT: disabled temporarily
    echo
    warn "BEFORE CONTINUING TO STAGE 2:"
    # COMMENTED OUT: WiFi warnings disabled per user request
    # warn "1. Ensure WiFi is still DISABLED on your device"
    warn "1. Keep the USB cable connected"
    warn "2. Do not change the device's network settings"
    echo
    info "Stage 2 will install KOReader and complete the setup."
    echo
    info "To complete the installation, run:"
    info "  $0 --continue"
    info "  or"
    info "  $0 --stage2"
    info "  or use option 1 (Full Install) from the main menu"
    echo
    info "If you experience connection issues in Stage 2:"
    # COMMENTED OUT: WiFi troubleshooting disabled per user request
    # info "• Check that WiFi is disabled (Settings > WiFi > OFF)"
    info "• Verify USB cable is securely connected"
    info "• Ensure device IP is still: $REMARKABLE_IP"
    echo
    highlight "======================================================================"
}

# Stage 2: KOReader installation and final configuration  
run_stage2() {
    log "=============================================================="
    log "STAGE 2: KOReader installation and final configuration"
    log "=============================================================="
    
    # Load saved stage information or get device connection
    if ! load_stage; then
        error "No saved stage information found. Please run Stage 1 first or provide connection details."
        exit 1
    fi
    
    # Pre-flight checks
    check_sshpass
    
    # Wait for device to be ready
    wait_for_device_ready
    
    # Stage 2 installation steps
    start_xovi          # This must happen AFTER hashtable rebuild
    # enable_xovi_tripletap  # COMMENTED OUT: Enable power button service (disabled temporarily)
    install_koreader
    restart_ui
    
    # Verification and cleanup
    verify_installation
    cleanup
    
    log "=============================================================="
    log "STAGE 2 COMPLETED SUCCESSFULLY!"
    log "=============================================================="
    echo
    log "XOVI installation completed successfully!"
    log "=============================================================="
    echo
    info "How to access KOReader:"
    info "1. Look for 'AppLoad' in the reMarkable sidebar menu"
    info "2. Tap on AppLoad to open the application menu"
    info "3. Select KOReader to launch it"
    echo
    info "If AppLoad doesn't appear immediately:"
    info "- Try restarting your reMarkable device completely"
    info "- Wait a few minutes for all services to initialize"
    echo
    show_restore_options
    
    # Clear stage file on successful completion
    clear_stage
    log "Installation script completed!"
}

# Intelligent stage determination with user interaction
determine_stage() {
    # Check for explicit stage flags
    if [[ "$STAGE1_ONLY" == true ]]; then
        CURRENT_STAGE="1"
        return
    elif [[ "$STAGE2_ONLY" == true ]]; then
        CURRENT_STAGE="2"
        return
    elif [[ "$CONTINUE_INSTALL" == true ]]; then
        if load_stage; then
            CURRENT_STAGE="$STAGE"
            info "Continuing installation from Stage $CURRENT_STAGE"
            return
        else
            info "No saved stage found, starting from Stage 1"
            CURRENT_STAGE="1"
            return
        fi
    fi
    
    # Smart auto-detection with user interaction
    if load_stage; then
        echo
        highlight "===================================================================="
        highlight "           Installation Progress Detection"
        highlight "===================================================================="
        echo
        info "Found previous installation state: Stage $STAGE"
        echo
        case "$STAGE" in
            "1")
                info "Stage 1 was interrupted. This typically happens during hashtable rebuild."
                info "The device may have rebooted and lost SSH connection."
                echo
                ;;
            "2")
                info "Stage 1 completed. Ready to continue with KOReader installation."
                echo
                ;;
        esac
        
        info "What would you like to do?"
        echo "  1) Continue from Stage $STAGE (recommended)"
        echo "  2) Restart from Stage 1 (fresh installation)"
        echo "  3) Skip to Stage 2 (if Stage 1 completed manually)"
        echo
        while true; do
            read -p "Enter your choice (1-3): " choice
            case $choice in
                1)
                    CURRENT_STAGE="$STAGE"
                    info "Continuing from Stage $CURRENT_STAGE"
                    return
                    ;;
                2)
                    CURRENT_STAGE="1"
                    clear_stage
                    info "Starting fresh installation from Stage 1"
                    return
                    ;;
                3)
                    CURRENT_STAGE="2"
                    info "Proceeding to Stage 2"
                    return
                    ;;
                *)
                    error "Invalid choice. Please enter 1, 2, or 3."
                    ;;
            esac
        done
    fi
    
    # Check device state intelligently
    echo
    highlight "===================================================================="
    highlight "           Intelligent Installation Detection"
    highlight "===================================================================="
    echo
    
    # First check if we can connect to get device state
    if [[ -n "$REMARKABLE_IP" ]] && [[ -n "$REMARKABLE_PASSWORD" ]]; then
        info "Checking device state to determine installation stage..."
        
        # Check if XOVI already exists
        if sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -d /home/root/xovi" 2>/dev/null; then
            # Check if KOReader is installed
            if sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -d /home/root/xovi/exthome/appload/koreader" 2>/dev/null; then
                echo
                warn "XOVI and KOReader appear to already be installed on your device!"
                echo
                info "What would you like to do?"
                echo "  1) Reinstall everything (fresh installation)"
                echo "  2) Only reinstall KOReader (Stage 2 only)"
                echo "  3) Exit and check device manually"
                echo
                while true; do
                    read -p "Enter your choice (1-3): " choice
                    case $choice in
                        1)
                            CURRENT_STAGE="1"
                            info "Starting fresh installation"
                            return
                            ;;
                        2)
                            CURRENT_STAGE="2"
                            info "Proceeding to KOReader installation only"
                            return
                            ;;
                        3)
                            info "Exiting. Check your device and run the script again."
                            exit 0
                            ;;
                        *)
                            error "Invalid choice. Please enter 1, 2, or 3."
                            ;;
                    esac
                done
            else
                echo
                info "XOVI is installed but KOReader is missing."
                info "Proceeding to Stage 2 (KOReader installation)."
                CURRENT_STAGE="2"
                return
            fi
        fi
    fi
    
    # Default to Stage 1 for fresh installations
    echo
    info "No previous installation detected. Starting fresh installation."
    CURRENT_STAGE="1"
}

# Function to show usage
show_usage() {
    echo "wowitsjack's XOVI Installer for reMarkable 1 & 2 (Staged Version)"
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -i, --ip IP_ADDRESS     Set reMarkable IP address"
    echo "  -p, --password PASSWORD Set SSH password (not recommended)"
    echo "  --backup-menu           Interactive backup and restore management"
    echo "  --backup-only           Create backup only, don't install"
    echo "  --restore BACKUP_NAME   Restore from backup (remove installation)"
    echo "  --force                 Skip confirmation prompts"
    echo "  --stage1                Run only Stage 1 (setup through hashtable rebuild)"
    echo "  --stage2                Run only Stage 2 (KOReader installation)"
    echo "  --continue              Continue from where the installation left off"
    echo
    echo "The installation is split into stages:"
    echo "  Stage 1: Device setup, backup, XOVI installation, and hashtable rebuild"
    echo "  Stage 2: KOReader installation and final configuration"
    echo
    echo "After Stage 1 completes and the device restarts, run the script again"
    echo "with --continue or --stage2 to complete the installation."
    echo
    echo "Examples:"
    echo "  $0                              # Full installation (auto-detects stages)"
    echo "  $0 --stage1                     # Run Stage 1 only"
    echo "  $0 --continue                   # Continue from saved stage"
    echo "  $0 -i 192.168.1.100           # Set custom IP"
    echo "  $0 --backup-menu               # Interactive backup/restore management"
    echo "  $0 --backup-only               # Create backup only"
    echo "  $0 --restore backup_name       # Restore from backup"
    echo
}

# Function to list available backups on device
list_backups() {
    log "Checking for available backups on device..."
    
    local backups_output
    backups_output=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
        "ls -1d /home/root/koreader_backup_* 2>/dev/null | xargs -I {} basename {}" 2>/dev/null || echo "")
    
    if [[ -z "$backups_output" ]]; then
        return 1
    fi
    
    echo "$backups_output"
    return 0
}

# Function to show interactive backup/restore menu
show_backup_restore_menu() {
    echo
    highlight "====================================================================="
    highlight "           Backup and Restore Management Menu"
    highlight "====================================================================="
    echo
    
    # Only get connection details if not already set, and handle connection gracefully
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$REMARKABLE_PASSWORD" ]]; then
        info "Device connection not configured yet."
        echo
        get_remarkable_ip
        get_remarkable_password
    fi
    
    check_sshpass
    
    # Try to connect, but don't fail if it doesn't work
    local connection_ok=false
    if check_remarkable_connection 2>/dev/null; then
        connection_ok=true
        log "Device connection verified successfully"
    else
        warn "Device connection failed - some options may require reconfiguring connection"
        info "You can still use most backup/restore functions"
    fi
    
    echo
    info "What would you like to do?"
    echo "  1) Create new backup"
    echo "  2) Restore from existing backup"
    echo "  3) List all available backups"
    echo "  4) Delete old backups"
    echo "  5) Uninstall without backup (DANGEROUS)"
    echo "  6) Configure device connection"
    echo "  7) Return to main menu"
    echo
    
    while true; do
        read -p "Enter your choice (1-6): " choice
        case $choice in
            1)
                log "Creating new backup..."
                check_device_architecture
                create_backup
                show_restore_options
                break
                ;;
            2)
                echo
                info "Checking for available backups..."
                if backup_list=$(list_backups); then
                    echo
                    info "Available backups on your device:"
                    echo
                    
                    # Convert to array for numbering
                    declare -a backup_array
                    local i=1
                    while IFS= read -r backup; do
                        echo "  $i) $backup"
                        backup_array[$i]="$backup"
                        ((i++))
                    done <<< "$backup_list"
                    
                    if [[ ${#backup_array[@]} -eq 0 ]]; then
                        warn "No backups found on device."
                        break
                    fi
                    
                    echo "  $i) Cancel"
                    echo
                    
                    while true; do
                        read -p "Select backup to restore (1-$i): " backup_choice
                        if [[ "$backup_choice" == "$i" ]]; then
                            info "Restore cancelled."
                            break 2
                        elif [[ "$backup_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$backup_choice" -le $((i-1)) ]]; then
                            selected_backup="${backup_array[$backup_choice]}"
                            echo
                            warn "This will COMPLETELY REMOVE KOReader and XOVI from your device!"
                            warn "Selected backup: $selected_backup"
                            echo
                            read -p "Are you sure you want to restore? (y/N): " confirm
                            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                restore_from_backup "$selected_backup"
                            else
                                info "Restore cancelled."
                            fi
                            break 2
                        else
                            error "Invalid selection. Please enter a number between 1 and $i."
                        fi
                    done
                else
                    warn "No backups found on your device."
                    info "Create a backup first with option 1, or run a full installation to automatically create one."
                    echo
                    read -p "Press Enter to continue..."
                fi
                break
                ;;
            3)
                echo
                info "Available backups on your device:"
                if backup_list=$(list_backups); then
                    echo
                    while IFS= read -r backup; do
                        echo "  • $backup"
                        # Show backup info if available
                        backup_info=$(sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
                            "cat /home/root/$backup/backup_info.txt 2>/dev/null | head -4" 2>/dev/null || echo "")
                        if [[ -n "$backup_info" ]]; then
                            echo "$backup_info" | sed 's/^/    /'
                        fi
                        echo
                    done <<< "$backup_list"
                else
                    warn "No backups found on your device."
                    info "Create a backup first with option 1, or run a full installation to automatically create one."
                    echo
                    read -p "Press Enter to continue..."
                fi
                break
                ;;
            4)
                echo
                info "Available backups to delete:"
                if backup_list=$(list_backups); then
                    echo
                    
                    # Convert to array for numbering
                    declare -a backup_array
                    local i=1
                    while IFS= read -r backup; do
                        echo "  $i) $backup"
                        backup_array[$i]="$backup"
                        ((i++))
                    done <<< "$backup_list"
                    
                    echo "  $i) Delete all backups"
                    echo "  $((i+1))) Cancel"
                    echo
                    
                    while true; do
                        read -p "Select backup to delete (1-$((i+1))): " delete_choice
                        if [[ "$delete_choice" == "$((i+1))" ]]; then
                            info "Delete cancelled."
                            break 2
                        elif [[ "$delete_choice" == "$i" ]]; then
                            echo
                            warn "This will delete ALL backups from your device!"
                            read -p "Are you absolutely sure? (y/N): " confirm
                            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                log "Deleting all backups..."
                                sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
                                    "rm -rf /home/root/koreader_backup_*" 2>/dev/null || true
                                log "All backups deleted."
                            else
                                info "Delete cancelled."
                            fi
                            break 2
                        elif [[ "$delete_choice" =~ ^[1-9][0-9]*$ ]] && [[ "$delete_choice" -le $((i-1)) ]]; then
                            selected_backup="${backup_array[$delete_choice]}"
                            echo
                            warn "This will permanently delete: $selected_backup"
                            read -p "Are you sure? (y/N): " confirm
                            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                log "Deleting backup: $selected_backup"
                                sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
                                    "rm -rf /home/root/$selected_backup" 2>/dev/null || true
                                log "Backup deleted: $selected_backup"
                            else
                                info "Delete cancelled."
                            fi
                            break 2
                        else
                            error "Invalid selection. Please enter a number between 1 and $((i+1))."
                        fi
                    done
                else
                    warn "No backups found on your device."
                    info "Use option 5 to uninstall without requiring a backup, or create one with option 1 first."
                    echo
                    read -p "Press Enter to continue..."
                fi
                break
                ;;
            5)
                echo
                warn "DANGEROUS OPERATION: Uninstall without backup"
                echo
                warn "This option will PERMANENTLY REMOVE all KOReader and XOVI components"
                warn "WITHOUT creating any backup. This action CANNOT be undone!"
                echo
                info "Use this only if:"
                info "• You don't care about preserving any data"
                info "• You want to completely clean your device"
                info "• No backups exist and you want to force removal"
                echo
                read -p "Do you want to proceed with dangerous uninstall? (y/N): " dangerous_confirm
                if [[ "$dangerous_confirm" =~ ^[Yy]$ ]]; then
                    uninstall_without_backup
                    echo
                    read -p "Press Enter to return to menu..."
                else
                    info "Dangerous uninstall cancelled."
                fi
                break
                ;;
            6)
                echo
                info "Configuring device connection..."
                REMARKABLE_IP=""
                REMARKABLE_PASSWORD=""
                get_remarkable_ip
                get_remarkable_password
                check_sshpass
                if check_remarkable_connection; then
                    log "Device connection configured successfully!"
                else
                    warn "Connection test failed. Please verify your device settings."
                fi
                echo
                read -p "Press Enter to continue..."
                break
                ;;
            7)
                info "Returning to main menu..."
                return 0
                ;;
            *)
                error "Invalid choice. Please enter 1, 2, 3, 4, 5, 6, or 7."
                ;;
        esac
    done
}

# Function to restore from backup
restore_from_backup() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        error "Backup name is required for restore operation"
        exit 1
    fi
    
    log "Restoring system from backup: $backup_name"
    
    # Check if backup exists
    if ! sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
        "test -f /home/root/$backup_name/restore.sh" 2>/dev/null; then
        error "Backup '$backup_name' not found or restore script missing"
        exit 1
    fi
    
    log "Running restore script on device..."
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP \
        "/home/root/$backup_name/restore.sh"
    
    log "Restore completed successfully!"
    clear_stage  # Clear any saved stage information
    exit 0
}

# Function to uninstall without backup (complete removal)
uninstall_without_backup() {
    log "======================================================================="
    log "COMPLETE UNINSTALL: Removing XOVI and KOReader (WITHOUT BACKUP)"
    log "======================================================================="
    
    warn "WARNING: This will completely remove KOReader and XOVI from your device!"
    warn "This operation CANNOT be undone and NO BACKUP will be created!"
    echo
    warn "All installed components will be permanently deleted:"
    info "• XOVI framework and extensions"
    info "• AppLoad launcher"
    info "• KOReader application"
    # info "• xovi-tripletap power button integration"  # COMMENTED OUT: disabled temporarily
    info "• All configuration files"
    info "• All shim files"
    echo
    
    read -p "Are you absolutely sure you want to proceed? (yes/NO): " confirm
    if [[ ! "$confirm" == "yes" ]]; then
        info "Uninstall cancelled. No changes were made."
        return 0
    fi
    
    echo
    warn "Last chance to cancel - this will permanently remove everything!"
    read -p "Type 'DELETE' to confirm permanent removal: " final_confirm
    if [[ ! "$final_confirm" == "DELETE" ]]; then
        info "Uninstall cancelled. No changes were made."
        return 0
    fi
    
    log "Proceeding with complete uninstall..."
    
    # Get device connection if not already set - with proper error handling
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$REMARKABLE_PASSWORD" ]]; then
        echo
        info "Device connection required for uninstall..."
        get_remarkable_ip
        get_remarkable_password
    fi
    
    check_sshpass
    
    # Try to connect, retry if failed
    local connection_attempts=0
    while [[ $connection_attempts -lt 3 ]]; do
        if check_remarkable_connection; then
            break
        else
            ((connection_attempts++))
            if [[ $connection_attempts -lt 3 ]]; then
                echo
                warn "Connection failed. Let's try again with fresh credentials."
                info "Attempt $((connection_attempts + 1)) of 3"
                echo
                get_remarkable_ip_retry
                get_remarkable_password_retry
            else
                error "Failed to connect after 3 attempts. Uninstall cannot proceed."
                error "Please check your device connection and try again."
                return 1
            fi
        fi
    done
    
    log "Removing all KOReader and XOVI components..."
    
    # Run the complete removal script
    sshpass -p "$REMARKABLE_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "
        echo 'Starting complete KOReader/XOVI removal...'
        
        # Stop XOVI services without killing USB ethernet
        # Instead of using ./stop (which may disable USB gadgets), stop services individually
        systemctl stop xochitl.service 2>/dev/null || true
        if pidof xochitl; then
            kill -15 $(pidof xochitl) 2>/dev/null || true
        fi
        echo 'XOVI services stopped (USB ethernet preserved)'
        # Note: NOT calling ./stop to preserve USB ethernet functionality
        
        # Remove XOVI completely
        if [[ -d /home/root/xovi ]]; then
            rm -rf /home/root/xovi 2>/dev/null || true
            echo 'XOVI directory removed'
        fi
        
        # Remove shims
        if [[ -d /home/root/shims ]]; then
            rm -rf /home/root/shims 2>/dev/null || true
            echo 'Shims directory removed'
        fi
        
        # Remove xovi-tripletap completely
        systemctl stop xovi-tripletap 2>/dev/null || true
        systemctl disable xovi-tripletap 2>/dev/null || true
        rm -f /etc/systemd/system/xovi-tripletap.service 2>/dev/null || true
        if [[ -d /home/root/xovi-tripletap ]]; then
            rm -rf /home/root/xovi-tripletap 2>/dev/null || true
            echo 'xovi-tripletap directory and service removed'
        fi
        systemctl daemon-reload 2>/dev/null || true
        
        # Remove any leftover files
        rm -f /home/root/xovi.so 2>/dev/null || true
        rm -f /home/root/xovi-arm32.so 2>/dev/null || true
        rm -f /home/root/install-xovi-for-rm 2>/dev/null || true
        rm -f /home/root/koreader-remarkable.zip 2>/dev/null || true
        rm -f /home/root/extensions-arm32-*.zip 2>/dev/null || true
        rm -f /home/root/qt-resource-rebuilder.so 2>/dev/null || true
        rm -f /home/root/appload.so 2>/dev/null || true
        rm -f /home/root/qtfb-shim*.so 2>/dev/null || true
        
        # Remove any KOReader directories that might exist
        rm -rf /home/root/koreader 2>/dev/null || true
        
        # Restart UI to ensure clean state
        systemctl restart xochitl
        
        echo 'Complete uninstall finished!'
        echo 'All KOReader and XOVI components have been permanently removed.'
    "
    
    # Clear any saved stage information
    clear_stage
    
    log "======================================================================="
    log "COMPLETE UNINSTALL SUCCESSFUL!"
    log "======================================================================="
    echo
    info "All KOReader and XOVI components have been permanently removed."
    info "Your device has been restored to its original state."
    echo
    info "The reMarkable UI has been restarted to ensure clean operation."
    info "No traces of the installation remain on your device."
    
    return 0
}

# Function to create backup only
backup_only() {
    log "Creating backup only (no installation)..."
    
    show_device_setup
    get_device_type
    get_remarkable_ip
    get_remarkable_password
    check_sshpass
    check_remarkable_connection
    check_device_architecture
    create_backup
    show_restore_options
    
    log "Backup created successfully!"
    exit 0
}

# Parse command line arguments
FORCE_INSTALL=false
BACKUP_ONLY=false
BACKUP_MENU=false
RESTORE_BACKUP=""
STAGE1_ONLY=false
STAGE2_ONLY=false
CONTINUE_INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -i|--ip)
            REMARKABLE_IP="$2"
            shift 2
            ;;
        -p|--password)
            REMARKABLE_PASSWORD="$2"
            warn "Password provided via command line. This is not secure!"
            shift 2
            ;;
        --backup-menu)
            BACKUP_MENU=true
            shift
            ;;
        --backup-only)
            BACKUP_ONLY=true
            shift
            ;;
        --restore)
            RESTORE_BACKUP="$2"
            shift 2
            ;;
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --stage1)
            STAGE1_ONLY=true
            shift
            ;;
        --stage2)
            STAGE2_ONLY=true
            shift
            ;;
        --continue)
            CONTINUE_INSTALL=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Error handling
trap 'error "Operation failed on line $LINENO. Check the output above for details."; exit 1' ERR

# Check if expect is available (for hashtable rebuild)
if ! command -v expect &>/dev/null; then
    warn "expect is not installed. Hashtable rebuild may require manual intervention."
    warn "Install expect for fully automatic operation:"
    warn "  Ubuntu/Debian: sudo apt-get install expect"
    warn "  macOS: brew install expect"
    warn "  Arch: sudo pacman -S expect"
fi

# Function to check installation status (non-blocking with timeout)
check_installation_status() {
    if [[ -z "$REMARKABLE_IP" ]] || [[ -z "$REMARKABLE_PASSWORD" ]]; then
        return 2  # No connection info
    fi
    
    # Quick connection test with very short timeout to avoid hanging
    if ! timeout 3 sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "echo 'connected'" &>/dev/null; then
        return 3  # Cannot connect
    fi
    
    # Check XOVI installation with timeout
    local xovi_installed=false
    if timeout 3 sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -d /home/root/xovi" 2>/dev/null; then
        xovi_installed=true
    fi
    
    # Check KOReader installation with timeout
    local koreader_installed=false
    if timeout 3 sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -d /home/root/xovi/exthome/appload/koreader" 2>/dev/null; then
        koreader_installed=true
    fi
    
    if [[ "$xovi_installed" == true && "$koreader_installed" == true ]]; then
        return 0  # Fully installed
    elif [[ "$xovi_installed" == true ]]; then
        return 1  # Partially installed
    else
        return 4  # Not installed
    fi
}

# Function to check for interrupted installation at startup
check_startup_state() {
    # Check for saved stage file first
    if load_stage; then
        echo
        highlight "======================================================================"
        highlight "           INTERRUPTED INSTALLATION DETECTED"
        highlight "======================================================================"
        echo
        info "Found previous installation state: Stage $STAGE"
        echo
        
        case "$STAGE" in
            "1")
                info "Stage 1 was interrupted (likely during hashtable rebuild)."
                info "Checking if Stage 1 actually completed..."
                
                # Try to connect and check installation state
                if [[ -n "$REMARKABLE_IP" ]] && [[ -n "$REMARKABLE_PASSWORD" ]]; then
                    if sshpass -p "$REMARKABLE_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMARKABLE_IP "test -d /home/root/xovi && test -f /home/root/xovi/extensions.d/appload.so" 2>/dev/null; then
                        echo
                        log "Stage 1 completed successfully! XOVI and AppLoad are installed."
                        info "Ready to proceed with Stage 2 (KOReader installation)."
                        # Update stage file to reflect reality
                        save_stage "2" "$REMARKABLE_IP" "$REMARKABLE_PASSWORD" "$DEVICE_TYPE" "$BACKUP_NAME"
                        echo
                        info "Would you like to continue with Stage 2 now?"
                        echo "  1) Yes, continue with KOReader installation (Stage 2)"
                        echo "  2) No, show main menu"
                        echo
                        read -p "Enter your choice (1-2): " startup_choice
                        case $startup_choice in
                            1)
                                info "Starting Stage 2..."
                                run_stage2
                                exit 0
                                ;;
                            2|*)
                                info "Returning to main menu. Use option 3 (Continue Installation) when ready."
                                ;;
                        esac
                    else
                        warn "Stage 1 was interrupted and needs to be completed."
                        info "XOVI installation is incomplete."
                    fi
                else
                    warn "Cannot connect to device to check installation state."
                    info "You'll need to configure device connection first."
                fi
                ;;
            "2")
                log "Stage 1 completed. Ready to continue with Stage 2 (KOReader installation)."
                echo
                info "Would you like to continue with Stage 2 now?"
                echo "  1) Yes, continue with KOReader installation (Stage 2)"
                echo "  2) No, show main menu"
                echo
                read -p "Enter your choice (1-2): " startup_choice
                case $startup_choice in
                    1)
                        info "Starting Stage 2..."
                        run_stage2
                        exit 0
                        ;;
                    2|*)
                        info "Returning to main menu. Use option 3 (Continue Installation) when ready."
                        ;;
                esac
                ;;
        esac
        
        echo
        info "Press Enter to continue to main menu..."
        read
    fi
}

# Function to show main menu
show_main_menu() {
    while true; do
        clear
        echo
        highlight "======================================================================"
        highlight "    reMarkable XOVI + AppLoader Installation & Management Script v3.0.4"
        highlight "======================================================================"
        echo
        info "This script installs XOVI extension framework and AppLoader on reMarkable devices."
        echo
        info "SUPPORTED DEVICES:"
        info "• reMarkable 1 (rM1) - FULLY SUPPORTED"
        info "• reMarkable 2 (rM2) - FULLY SUPPORTED"
        info "• reMarkable Paper Pro (rMPP) - COMING SOON!"
        echo
        info "What XOVI + AppLoader provides:"
        info "• XOVI: Powerful extension framework for reMarkable devices"
        info "• AppLoader: Application launcher that appears in your sidebar"
        # info "• xovi-tripletap: Triple-press power button to start XOVI quickly"  # COMMENTED OUT: disabled temporarily
        info "• Enables installation of custom applications and tools"
        info "• Safe extension management with proper UI integration"
        info "• Foundation for running apps like KOReader"
        echo
        
        # Check and display current status (non-blocking)
        info "Checking device status..."
        if [[ -n "$REMARKABLE_IP" ]] && [[ -n "$REMARKABLE_PASSWORD" ]]; then
            # Run status check in background to avoid hanging the menu
            if check_installation_status; then
                status_code=$?
                case $status_code in
                    0)
                        echo -e "   ${GREEN}[OK] Status: KOReader is fully installed and ready${NC}"
                        ;;
                    1)
                        echo -e "   ${YELLOW}[WARN] Status: XOVI installed, KOReader missing${NC}"
                        ;;
                    2)
                        echo -e "   ${BLUE}[INFO] Status: No device connection configured${NC}"
                        ;;
                    3)
                        echo -e "   ${RED}[ERROR] Status: Cannot connect to device${NC}"
                        ;;
                    4)
                        echo -e "   ${BLUE}[INFO] Status: KOReader not installed${NC}"
                        ;;
                esac
            else
                # Handle timeout or other errors gracefully
                status_code=$?
                case $status_code in
                    3)
                        echo -e "   ${RED}[ERROR] Status: Device connection timeout${NC}"
                        ;;
                    *)
                        echo -e "   ${YELLOW}[WARN] Status: Unable to check device (timeout or error)${NC}"
                        ;;
                esac
            fi
        else
            echo -e "   ${BLUE}[INFO] Status: No device connection configured${NC}"
        fi
        
        echo
        highlight "======================================================================"
        info "Available Options:"
        echo
        echo "  DEVICE MANAGEMENT:"
        echo "     1) XOVI + AppLoad + KOReader (Full Install)"
        echo "     2) XOVI + AppLoad (Launcher, no apps)"
        echo "     3) Continue Interrupted Installation"
        echo "     4) Remove KOReader & XOVI (Complete Uninstall)"
        echo "     5) Check Installation Status"
        echo
        echo "  ADVANCED OPTIONS:"
        echo "     6) Backup & Restore Management"
        echo "     7) Download Required Files Only"
        echo "     8) Manual Stage 1 (XOVI & Extensions)"
        echo "     9) Manual Stage 2 (KOReader Only)"
        echo
        echo "  SYSTEM OPTIONS:"
        echo "     10) Configure Device Connection"
        echo "     11) View System Information"
        echo "     12) Ethernet Fix (USB adapter repair)"
        echo "     13) Show Help & Documentation"
        echo "     14) Exit"
        echo
        highlight "======================================================================"
        echo
        
        read -p "Enter your choice (1-14): " choice
        
        case $choice in
            1)
                echo
                info "Starting full KOReader installation (XOVI + AppLoad + KOReader)..."
                sleep 1
                
                # Show WiFi setup instructions before installation
                if ! show_wifi_setup_instructions; then
                    continue
                fi
                
                determine_stage
                case "$CURRENT_STAGE" in
                    "1")
                        run_stage1
                        # After Stage 1 completes successfully, offer to continue to Stage 2
                        echo
                        info "Stage 1 completed successfully!"
                        info "Would you like to continue immediately with Stage 2 (KOReader installation)?"
                        echo "  1) Yes, continue with Stage 2 now"
                        echo "  2) No, I'll run it later"
                        echo
                        read -p "Enter your choice (1-2): " continue_choice
                        case $continue_choice in
                            1)
                                info "Continuing with Stage 2..."
                                sleep 2
                                run_stage2
                                ;;
                            2|*)
                                info "Stage 2 will be available when you restart the script."
                                info "Run option 1 (Full Install) or option 3 (Continue Installation) to proceed."
                                ;;
                        esac
                        ;;
                    "2")
                        run_stage2
                        ;;
                    *)
                        error "Invalid stage: $CURRENT_STAGE"; exit 1
                        ;;
                esac
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            2)
                echo
                info "Installing launcher framework only (XOVI + AppLoad, no apps)..."
                sleep 1
                
                # Show WiFi setup instructions before installation
                if ! show_wifi_setup_instructions; then
                    continue
                fi
                
                # Run the specialized launcher-only installation
                run_launcher_only
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            3)
                echo
                info "Continuing interrupted installation..."
                sleep 1
                CONTINUE_INSTALL=true
                determine_stage
                case "$CURRENT_STAGE" in
                    "1") run_stage1 ;;
                    "2") run_stage2 ;;
                    *) warn "No interrupted installation found. Use option 1 for full installation."; sleep 3 ;;
                esac
                ;;
            4)
                echo
                show_backup_restore_menu
                ;;
            5)
                echo
                info "Checking installation status..."
                get_remarkable_ip
                get_remarkable_password
                check_sshpass
                check_remarkable_connection
                
                check_installation_status
                status_code=$?
                
                echo
                highlight "======================================================================"
                highlight "           Installation Status Report"
                highlight "======================================================================"
                echo
                
                case $status_code in
                    0)
                        log "KOReader is fully installed and ready to use!"
                        info "[OK] XOVI framework installed"
                        info "[OK] Required extensions installed"
                        info "[OK] KOReader installed in AppLoad"
                        echo
                        info "To access KOReader:"
                        info "1. Look for 'AppLoad' in your reMarkable sidebar"
                        info "2. Tap AppLoad to open the application menu"
                        info "3. Select KOReader to launch"
                        ;;
                    1)
                        warn "Partial installation detected!"
                        info "[OK] XOVI framework installed"
                        info "[MISS] KOReader missing from AppLoad"
                        echo
                        info "Recommendation: Run option 2 (Continue Installation) or option 8 (Stage 2 only)"
                        ;;
                    4)
                        info "KOReader is not installed on this device."
                        info "[MISS] XOVI framework not found"
                        info "[MISS] KOReader not found"
                        echo
                        info "Recommendation: Run option 1 (Full Installation)"
                        ;;
                    *)
                        error "Unable to determine installation status"
                        ;;
                esac
                
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            6)
                show_backup_restore_menu
                ;;
            7)
                echo
                info "Downloading required files..."
                download_files
                log "All required files downloaded to ./downloads/"
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            8)
                echo
                info "Running Stage 1 (XOVI & Extensions) only..."
                sleep 1
                
                # Show WiFi setup instructions before installation
                if ! show_wifi_setup_instructions; then
                    continue
                fi
                
                STAGE1_ONLY=true
                run_stage1
                ;;
            9)
                echo
                info "Running Stage 2 (KOReader) only..."
                sleep 1
                STAGE2_ONLY=true
                run_stage2
                ;;
            10)
                echo
                info "Configuring device connection..."
                REMARKABLE_IP=""
                REMARKABLE_PASSWORD=""
                get_remarkable_ip
                get_remarkable_password
                check_sshpass
                check_remarkable_connection
                log "Device connection configured successfully!"
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            11)
                echo
                highlight "======================================================================"
                highlight "                System Information"
                highlight "======================================================================"
                echo
                info "Script Information:"
                info "• Version: wowitsjack's XOVI Installer v3.0.4"
                info "• Supported Devices: reMarkable 1 & reMarkable 2"
                info "• Installation Method: XOVI + AppLoad framework"
                echo
                info "What gets installed:"
                info "• XOVI: Extension manager for reMarkable devices"
                info "• qt-resource-rebuilder: Required for UI modifications"
                info "• AppLoad: Application launcher extension"
                # info "• xovi-tripletap: Power button integration (triple-press to start XOVI)"  # COMMENTED OUT: disabled temporarily
                info "• KOReader: Advanced document reader application"
                echo
                info "System Requirements:"
                info "• reMarkable 1 or 2 device with SSH enabled"
                info "• USB connection to computer"
                info "• sshpass installed on your system"
                echo
                info "File Locations on Device:"
                info "• XOVI: /home/root/xovi/"
                info "• Extensions: /home/root/xovi/extensions.d/"
                # info "• xovi-tripletap: /home/root/xovi-tripletap/"  # COMMENTED OUT: disabled temporarily
                info "• KOReader: /home/root/xovi/exthome/appload/koreader/"
                info "• Backups: /home/root/koreader_backup_*/"
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            12)
                echo
                info "Installing USB Ethernet Fix service..."
                sleep 1
                install_ethernet_fix
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            13)
                show_usage
                echo
                read -p "Press Enter to return to main menu..."
                ;;
            14)
                echo
                info "Thank you for using wowitsjack's XOVI installer!"
                info "If you encounter any issues, please check the backup/restore options."
                exit 0
                ;;
            *)
                error "Invalid choice. Please enter a number between 1-14."
                sleep 2
                ;;
        esac
    done
}

# Check for interrupted installations at startup (before showing menu)
check_startup_state

# Handle special modes or show main menu
if [[ "$BACKUP_MENU" == true ]]; then
    show_backup_restore_menu
elif [[ "$BACKUP_ONLY" == true ]]; then
    backup_only
elif [[ -n "$RESTORE_BACKUP" ]]; then
    restore_from_backup "$RESTORE_BACKUP"
elif [[ "$STAGE1_ONLY" == true ]]; then
    run_stage1
elif [[ "$STAGE2_ONLY" == true ]]; then
    run_stage2
elif [[ "$CONTINUE_INSTALL" == true ]]; then
    determine_stage
    case "$CURRENT_STAGE" in
        "1") run_stage1 ;;
        "2") run_stage2 ;;
        *) error "Invalid stage: $CURRENT_STAGE"; exit 1 ;;
    esac
else
    # Show main menu by default
    show_main_menu
fi