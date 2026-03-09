#!/bin/bash
set -euo pipefail

# ========================================================================
# ZynoxPlayzYT - Enhanced Multi-VM Manager
# ========================================================================

# --- Configuration ---
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Supported OS options: OS_NAME="Distro|Codename|URL|Hostname|User|Pass"
declare -A OS_OPTIONS=(
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
)

# --- UI & Utilities ---

print_status() {
    local type=$1; local msg=$2
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $msg" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $msg" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $msg" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $msg" ;;
        "INPUT") echo -ne "\033[1;36m[INPUT]\033[0m $msg" ;;
    esac
}

display_header() {
    clear
    echo "========================================================================"
    echo "                            ZynoxPlayzYT                                "
    echo "========================================================================"
}

check_deps() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "openssl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_status "ERROR" "Missing $dep. Install via: sudo apt install qemu-system cloud-image-utils wget openssl"
            exit 1
        fi
    done
}

cleanup() { rm -f user-data meta-data; }
trap cleanup EXIT

# --- VM Operations ---

get_vms() { find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; | sort; }

save_config() {
    local cfg="$VM_DIR/$VM_NAME.conf"
    cat > "$cfg" <<EOF
VM_NAME="$VM_NAME";HOSTNAME="$HOSTNAME";USERNAME="$USERNAME";PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE";MEMORY="$MEMORY";CPUS="$CPUS";SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE";PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE";SEED_FILE="$SEED_FILE"
EOF
}

setup_image() {
    print_status "INFO" "Ensuring image exists..."
    [[ ! -f "$IMG_FILE" ]] && wget -q --show-progress "$IMG_URL" -O "$IMG_FILE"
    qemu-img resize "$IMG_FILE" "$DISK_SIZE" &>/dev/null || true

    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD")
EOF
    echo "instance-id: iid-$VM_NAME" > meta-data
    cloud-localds "$SEED_FILE" user-data meta-data
}

create_vm() {
    display_header
    local keys=("${!OS_OPTIONS[@]}")
    for i in "${!keys[@]}"; do echo "  $((i+1))) ${keys[$i]}"; done
    print_status "INPUT" "Select OS: "; read -r idx
    local key="${keys[$((idx-1))]}"
    IFS='|' read -r _ _ IMG_URL _ USERNAME PASSWORD <<< "${OS_OPTIONS[$key]}"

    print_status "INPUT" "VM Name: "; read -r VM_NAME
    HOSTNAME="$VM_NAME"; DISK_SIZE="20G"; MEMORY="2048"; CPUS="2"; SSH_PORT="2222"
    GUI_MODE=false; PORT_FORWARDS=""
    IMG_FILE="$VM_DIR/$VM_NAME.qcow2"; SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

    setup_image && save_config
    print_status "SUCCESS" "VM $VM_NAME created!"
}

start_vm() {
    local name=$1
    if [[ -f "$VM_DIR/$name.conf" ]]; then
        source "$VM_DIR/$name.conf"
        local net="user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        # Add custom port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra fwd_list <<< "$PORT_FORWARDS"
            for f in "${fwd_list[@]}"; do net+=",hostfwd=tcp::${f%:*}-:${f#*:}"; done
        fi

        local args=(
            qemu-system-x86_64 -enable-kvm -m "$MEMORY" -smp "$CPUS" -cpu host
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -device virtio-net-pci,netdev=n0 -netdev "$net"
        )
        [[ "$GUI_MODE" == "true" ]] && args+=(-display gtk) || args+=(-nographic)
        
        print_status "SUCCESS" "Booting $name. Connect via: ssh -p $SSH_PORT $USERNAME@localhost"
        "${args[@]}"
    fi
}

# --- Main Menu ---

while true; do
    display_header
    vms=($(get_vms))
    [[ ${#vms[@]} -gt 0 ]] && echo -e "Existing VMs: \033[1;32m${vms[*]}\033[0m"
    echo -e "\n1) Create VM\n2) Start VM\n3) Delete VM\n0) Exit"
    print_status "INPUT" "Choice: "; read -r choice
    case $choice in
        1) create_vm ;;
        2) print_status "INPUT" "Name: "; read -r n; start_vm "$n" ;;
        3) print_status "INPUT" "Name: "; read -r n; rm -f "$VM_DIR/$n"* && print_status "SUCCESS" "Deleted." ;;
        0) exit 0 ;;
    esac
    read -p "Press Enter to continue..."
done
