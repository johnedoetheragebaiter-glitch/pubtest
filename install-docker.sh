#!/bin/bash
# install-docker.sh — Secure, idempotent Docker Engine installer
# Detects OS/architecture, removes conflicts, installs from official repo, verifies.
#
# Usage:
#   chmod +x install-docker.sh
#   ./install-docker.sh
#
# Supports: Ubuntu 22.04/24.04/25.10/26.04, Debian 11/12
# Architectures: amd64, arm64, armhf, s390x, ppc64el

set -euo pipefail

# ─── Colours ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_err()   { echo -e "${RED}[ERR]${NC}   $1"; }

# ─── 1. Environment Detection ───
log_info "Detecting environment..."

# Detect OS family and version
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
    OS_PRETTY_NAME="${PRETTY_NAME}"
else
    log_err "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

# Detect architecture
ARCH="$(dpkg --print-architecture)"
ARCH_SHORT="${ARCH}"

log_info "Detected OS: ${OS_PRETTY_NAME}"
log_info "Detected architecture: ${ARCH_SHORT}"

# Validate supported OS
SUPPORTED_UBUNTU="jammy noble oracular plucky"
SUPPORTED_DEBIAN="bullseye bookworm"

if [[ "${OS_ID}" == "ubuntu" ]]; then
    if [[ ! " ${SUPPORTED_UBUNTU} " =~ ${OS_VERSION_CODENAME} ]]; then
        log_warn "Untested Ubuntu version: ${OS_VERSION_CODENAME}"
        log_warn "Supported: ${SUPPORTED_UBUNTU}"
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
    REPO_SUITE="${OS_VERSION_CODENAME}"
    REPO_URL="https://download.docker.com/linux/ubuntu"
elif [[ "${OS_ID}" == "debian" ]]; then
    if [[ ! " ${SUPPORTED_DEBIAN} " =~ ${OS_VERSION_CODENAME} ]]; then
        log_warn "Untested Debian version: ${OS_VERSION_CODENAME}"
        log_warn "Supported: ${SUPPORTED_DEBIAN}"
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
    REPO_SUITE="${OS_VERSION_CODENAME}"
    REPO_URL="https://download.docker.com/linux/debian"
else
    log_err "Unsupported OS: ${OS_ID}"
    log_err "This script supports Ubuntu and Debian only."
    exit 1
fi

# Validate architecture
VALID_ARCHS="amd64 arm64 armhf s390x ppc64el"
if [[ ! " ${VALID_ARCHS} " =~ ${ARCH_SHORT} ]]; then
    log_err "Unsupported architecture: ${ARCH_SHORT}"
    log_err "Supported: ${VALID_ARCHS}"
    exit 1
fi

log_ok "Environment validated: ${OS_ID} ${REPO_SUITE} on ${ARCH_SHORT}"

# ─── 2. Uninstall Conflicting Packages ───
log_info "Checking for conflicting packages..."

CONFLICTS=(docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc)
INSTALLED_CONFLICTS=()

for pkg in "${CONFLICTS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        INSTALLED_CONFLICTS+=("$pkg")
    fi
done

if [ ${#INSTALLED_CONFLICTS[@]} -gt 0 ]; then
    log_warn "Found conflicting packages: ${INSTALLED_CONFLICTS[*]}"
    read -rp "Remove these packages? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Removing conflicting packages..."
        sudo apt-get remove -y "${INSTALLED_CONFLICTS[@]}"
        log_ok "Conflicting packages removed"
    else
        log_err "Cannot continue with conflicting packages installed."
        exit 1
    fi
else
    log_ok "No conflicting packages found"
fi

# ─── 3. Install Prerequisites ───
log_info "Installing prerequisites..."

sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https

log_ok "Prerequisites installed"

# ─── 4. Add Docker GPG Key ───
log_info "Adding Docker's official GPG key..."

sudo install -m 0755 -d /etc/apt/keyrings

if [ -f /etc/apt/keyrings/docker.asc ]; then
    log_warn "Existing Docker GPG key found. Backing up..."
    sudo cp /etc/apt/keyrings/docker.asc "/etc/apt/keyrings/docker.asc.bak.$(date +%s)"
fi

sudo curl -fsSL "${REPO_URL}/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

log_ok "GPG key added"

# ─── 5. Add Docker APT Repository ───
log_info "Adding Docker APT repository..."

REPO_FILE="/etc/apt/sources.list.d/docker.sources"

if [ -f "$REPO_FILE" ]; then
    log_warn "Existing Docker repo file found. Backing up..."
    sudo cp "$REPO_FILE" "${REPO_FILE}.bak.$(date +%s)"
    sudo rm -f "$REPO_FILE"
fi

# Use the new deb822 .sources format
sudo tee "$REPO_FILE" > /dev/null <<EOF
Types: deb
URIs: ${REPO_URL}
Suites: ${REPO_SUITE}
Components: stable
Architectures: ${ARCH_SHORT}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

log_ok "Repository added: ${REPO_URL} (${REPO_SUITE}, ${ARCH_SHORT})"

# ─── 6. Install Docker Engine ───
log_info "Updating package index..."
sudo apt-get update

log_info "Installing Docker Engine..."

# List available versions
log_info "Available Docker versions:"
apt list --all-versions docker-ce 2>/dev/null | head -5 || true

# Install latest
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

log_ok "Docker Engine installed"

# ─── 7. Enable and Start Docker ───
log_info "Enabling Docker service..."

sudo systemctl enable docker
sudo systemctl start docker

# Wait briefly for service to be ready
sleep 2

if systemctl is-active --quiet docker; then
    log_ok "Docker service is running"
else
    log_err "Docker service failed to start"
    sudo systemctl status docker --no-pager
    exit 1
fi

# ─── 8. Add Current User to docker Group ───
log_info "Adding user '$(whoami)' to docker group..."

if id -nG "$(whoami)" | grep -qw "docker"; then
    log_ok "User already in docker group"
else
    sudo usermod -aG docker "$(whoami)"
    log_ok "User added to docker group"
    log_warn "You must log out and back in for group changes to take effect"
    log_warn "Or run: newgrp docker"
fi

# ─── 9. Verify Installation ───
log_info "Verifying Docker installation..."

DOCKER_VERSION="$(docker --version)"
COMPOSE_VERSION="$(docker compose version)"

log_ok "Docker version: ${DOCKER_VERSION}"
log_ok "Docker Compose: ${COMPOSE_VERSION}"

# ─── 10. Test with hello-world ───
log_info "Running hello-world test container..."

if docker run --rm hello-world; then
    log_ok "hello-world test PASSED"
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Docker installation successful!       ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo "  OS:        ${OS_PRETTY_NAME}"
    echo "  Arch:      ${ARCH_SHORT}"
    echo "  Docker:    ${DOCKER_VERSION}"
    echo "  Compose:   ${COMPOSE_VERSION}"
    echo
    echo "  Next steps:"
    echo "    1. Log out and back in (or: newgrp docker)"
    echo "    2. Test without sudo: docker run hello-world"
    echo "    3. Continue with Phase 2: DNS Stack"
    echo
else
    log_err "hello-world test FAILED"
    log_err "Check Docker status: sudo systemctl status docker"
    exit 1
fi

# ─── Summary ───
echo
echo -e "${BLUE}Environment variables stored:${NC}"
echo "  OS_ID=${OS_ID}"
echo "  OS_VERSION_CODENAME=${OS_VERSION_CODENAME}"
echo "  ARCH=${ARCH}"
echo "  REPO_URL=${REPO_URL}"
echo "  REPO_SUITE=${REPO_SUITE}"
