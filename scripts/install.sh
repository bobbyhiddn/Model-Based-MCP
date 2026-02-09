#!/usr/bin/env bash
# ============================================================================
# Eclipse Papyrus + SysON + Model-Based-MCP — Full Install Script
# ============================================================================
#
# Installs and configures:
#   1. Eclipse Papyrus Desktop 7.1.0 (SysML 1.x modeling)
#   2. Eclipse SysON v2026.1.0 (SysML v2, Docker-based)
#   3. System dependencies (GTK libs for Eclipse)
#   4. Model-Based-MCP Python environment
#   5. Papyrus-to-YAML converter (when available)
#   6. Convenience launcher scripts in ~/bin/
#
# Usage:
#   ./install.sh              # Full install
#   ./install.sh --dry-run    # Show what would be done
#   ./install.sh --help       # Show this help
#
# Safe to run multiple times (idempotent).
# Masternode: Debian 13 (trixie), x86_64, Java 21, Docker 26.x
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PAPYRUS_VERSION="7.1.0"
PAPYRUS_RELEASE="2025-06"
PAPYRUS_URL="https://download.eclipse.org/modeling/mdt/papyrus/papyrus-desktop/downloads/releases/${PAPYRUS_RELEASE}/papyrus-desktop-${PAPYRUS_VERSION}-linux.gtk.x86_64.tar.gz"
PAPYRUS_DIR="$HOME/Apps/Papyrus-Desktop"
PAPYRUS_TARBALL="papyrus-desktop-${PAPYRUS_VERSION}.tar.gz"

SYSON_VERSION="v2026.1.0"
SYSON_IMAGE="eclipsesyson/syson:${SYSON_VERSION}"
SYSON_DIR="$HOME/Apps/SysON"
SYSON_PORT="8080"

MBMCP_DIR="$HOME/Code/Model-Based-MCP"
CONVERTER_MODULE="$MBMCP_DIR/src/model_based_mcp/papyrus.py"

BIN_DIR="$HOME/bin"

# GTK/SWT dependencies for Eclipse on Debian 13
APT_PACKAGES=(
    libgtk-3-0t64
    libwebkit2gtk-4.1-0
    libswt-gtk-4-jni
    xdg-utils
    libcanberra-gtk3-module
)

# UV binary location (Micah's standard)
UV_BIN="$HOME/.local/bin/uv"

DRY_RUN=false
VERBOSE=false

# ---------------------------------------------------------------------------
# Colors & output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[FAIL]${NC}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }
dry()     { echo -e "${YELLOW}[DRY]${NC}  Would: $*"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be done without doing it"
    echo "  --verbose    Show additional detail"
    echo "  --help       Show this help message"
    echo ""
    echo "Installs Eclipse Papyrus Desktop, SysON (Docker), system deps,"
    echo "Model-Based-MCP environment, and convenience launchers."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --verbose)  VERBOSE=true; shift ;;
        --help|-h)  usage; exit 0 ;;
        *)          err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if $DRY_RUN; then
    echo -e "${YELLOW}${BOLD}=== DRY RUN MODE — nothing will be modified ===${NC}\n"
fi

# ---------------------------------------------------------------------------
# Helper: run or dry-print a command
# ---------------------------------------------------------------------------
run() {
    if $DRY_RUN; then
        dry "$*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
step "Pre-flight checks"

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
    err "This script is built for x86_64. Detected: $ARCH"
    exit 1
fi
ok "Architecture: $ARCH"

# Check Java
if command -v java &>/dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1)
    ok "Java: $JAVA_VER"
else
    err "Java not found. Eclipse Papyrus requires JDK 21+."
    err "Install with: sudo apt install openjdk-21-jdk"
    exit 1
fi

# Check Docker
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version)
    ok "Docker: $DOCKER_VER"
else
    warn "Docker not found. SysON installation will be skipped."
fi

# Check Docker Compose
COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    ok "Docker Compose: $(docker compose version 2>&1)"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    ok "Docker Compose: $(docker-compose --version 2>&1)"
else
    warn "Docker Compose not found. SysON installation will be skipped."
fi

# Check uv
if [[ -x "$UV_BIN" ]]; then
    ok "uv: $($UV_BIN --version 2>&1)"
elif command -v uv &>/dev/null; then
    UV_BIN="$(command -v uv)"
    ok "uv: $(uv --version 2>&1)"
else
    warn "uv not found at $UV_BIN or on PATH. Model-Based-MCP setup may fail."
fi

# Check port 8080
if ss -tlnp 2>/dev/null | grep -q ":${SYSON_PORT} "; then
    warn "Port ${SYSON_PORT} is already in use!"
    warn "SysON will need a different port. Edit ~/Apps/SysON/docker-compose.yml after install."
else
    ok "Port ${SYSON_PORT} is available for SysON"
fi

echo ""

# ============================================================================
# STEP 1: System Dependencies
# ============================================================================
step "Step 1/6: System dependencies (GTK/SWT libraries)"

MISSING_PKGS=()
for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null 2>&1; then
        ok "Already installed: $pkg"
    else
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    info "Need to install: ${MISSING_PKGS[*]}"
    if $DRY_RUN; then
        dry "sudo apt-get update && sudo apt-get install -y ${MISSING_PKGS[*]}"
    else
        info "This requires sudo — you may be prompted for your password."
        sudo apt-get update -qq
        sudo apt-get install -y "${MISSING_PKGS[@]}"
        ok "System dependencies installed"
    fi
else
    ok "All system dependencies already installed"
fi

# ============================================================================
# STEP 2: Eclipse Papyrus Desktop
# ============================================================================
step "Step 2/6: Eclipse Papyrus Desktop ${PAPYRUS_VERSION}"

if [[ -x "$PAPYRUS_DIR/eclipse" ]]; then
    ok "Papyrus Desktop already installed at $PAPYRUS_DIR"
else
    info "Downloading Papyrus Desktop ${PAPYRUS_VERSION}..."
    run mkdir -p "$HOME/Apps"

    if $DRY_RUN; then
        dry "Download $PAPYRUS_URL"
        dry "Extract to $PAPYRUS_DIR"
    else
        TMPDIR=$(mktemp -d)
        TARBALL="$TMPDIR/$PAPYRUS_TARBALL"

        # Download with progress
        if ! wget -q --show-progress -O "$TARBALL" "$PAPYRUS_URL"; then
            err "Download failed. The URL may have changed."
            err "Check: https://eclipse.dev/papyrus/download.html"
            err "Continuing with remaining installations..."
            rm -rf "$TMPDIR"
        else
            ok "Download complete ($(du -h "$TARBALL" | cut -f1))"

            # Extract — Papyrus archives extract to "eclipse/" directory
            info "Extracting to $PAPYRUS_DIR..."
            mkdir -p "$PAPYRUS_DIR"
            tar xzf "$TARBALL" -C "$HOME/Apps/"

            # The archive extracts as "eclipse/" — rename if needed
            if [[ -d "$HOME/Apps/eclipse" && ! -d "$PAPYRUS_DIR" ]]; then
                mv "$HOME/Apps/eclipse" "$PAPYRUS_DIR"
            elif [[ -d "$HOME/Apps/eclipse" && -d "$PAPYRUS_DIR" ]]; then
                # eclipse/ extracted but Papyrus-Desktop already exists somehow
                # Merge — the tar likely extracted INTO Papyrus-Desktop if we mkdir'd it
                # Actually let's just move the contents
                cp -rn "$HOME/Apps/eclipse/"* "$PAPYRUS_DIR/" 2>/dev/null || true
                rm -rf "$HOME/Apps/eclipse"
            fi

            rm -rf "$TMPDIR"

            if [[ -x "$PAPYRUS_DIR/eclipse" ]]; then
                ok "Papyrus Desktop installed at $PAPYRUS_DIR"
            else
                err "Installation extracted but eclipse binary not found at expected path."
                err "Check contents of $HOME/Apps/ and adjust PAPYRUS_DIR."
                # List what was extracted for debugging
                ls -la "$HOME/Apps/" 2>/dev/null || true
            fi
        fi
    fi
fi

# Configure Java VM in eclipse.ini if needed
if [[ -f "$PAPYRUS_DIR/eclipse.ini" ]]; then
    JAVA_HOME_PATH="/usr/lib/jvm/java-21-openjdk-amd64/bin/java"
    if [[ -x "$JAVA_HOME_PATH" ]] && ! grep -q "$JAVA_HOME_PATH" "$PAPYRUS_DIR/eclipse.ini" 2>/dev/null; then
        if $DRY_RUN; then
            dry "Add -vm $JAVA_HOME_PATH to eclipse.ini"
        else
            # Insert -vm before -vmargs line
            if grep -q "^-vmargs" "$PAPYRUS_DIR/eclipse.ini"; then
                sed -i "/^-vmargs/i -vm\n${JAVA_HOME_PATH}" "$PAPYRUS_DIR/eclipse.ini"
                ok "Configured Java 21 in eclipse.ini"
            fi
        fi
    else
        ok "eclipse.ini already configured (or Java path set)"
    fi
fi

# ============================================================================
# STEP 3: Eclipse SysON (Docker)
# ============================================================================
step "Step 3/6: Eclipse SysON ${SYSON_VERSION} (Docker)"

if [[ -z "$COMPOSE_CMD" ]]; then
    warn "Skipping SysON — Docker Compose not available"
else
    run mkdir -p "$SYSON_DIR"

    if [[ -f "$SYSON_DIR/docker-compose.yml" ]]; then
        ok "SysON docker-compose.yml already exists at $SYSON_DIR"
        info "To update, delete $SYSON_DIR/docker-compose.yml and re-run this script."
    else
        info "Generating docker-compose.yml for SysON..."

        if $DRY_RUN; then
            dry "Write docker-compose.yml to $SYSON_DIR/docker-compose.yml"
        else
            cat > "$SYSON_DIR/docker-compose.yml" << COMPOSE_EOF
# Eclipse SysON ${SYSON_VERSION} — SysML v2 Modeling Tool
# Generated by Model-Based-MCP install script
# Start: cd ~/Apps/SysON && docker compose up -d
# Stop:  cd ~/Apps/SysON && docker compose down
# Access: http://localhost:${SYSON_PORT}

services:
  database:
    image: postgres:15
    container_name: syson-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: syson
      POSTGRES_USER: syson
      POSTGRES_PASSWORD: syson
    volumes:
      - syson-pgdata:/var/lib/postgresql/data
    networks:
      - syson
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U syson"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: "${SYSON_IMAGE}"
    container_name: syson-app
    restart: unless-stopped
    ports:
      - "${SYSON_PORT}:8080"
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://database/syson
      SPRING_DATASOURCE_USERNAME: syson
      SPRING_DATASOURCE_PASSWORD: syson
      SIRIUS_COMPONENTS_CORS_ALLOWEDORIGINPATTERNS: "*"
      SERVER_PORT: 8080
    depends_on:
      database:
        condition: service_healthy
    networks:
      - syson

volumes:
  syson-pgdata:

networks:
  syson:
COMPOSE_EOF
            ok "docker-compose.yml written to $SYSON_DIR/docker-compose.yml"
        fi
    fi

    # Pre-pull images (don't start)
    if $DRY_RUN; then
        dry "docker pull postgres:15"
        dry "docker pull $SYSON_IMAGE"
    else
        info "Pre-pulling Docker images (this may take a few minutes)..."
        docker pull postgres:15 2>&1 | tail -1
        docker pull "$SYSON_IMAGE" 2>&1 | tail -1
        ok "Docker images pulled. Run 'syson-start' to launch."
    fi
fi

# ============================================================================
# STEP 4: Model-Based-MCP Python Environment
# ============================================================================
step "Step 4/6: Model-Based-MCP Python environment"

if [[ ! -d "$MBMCP_DIR" ]]; then
    err "Model-Based-MCP not found at $MBMCP_DIR"
    err "Clone it first: gh repo clone bobbyhiddn/Model-Based-MCP ~/Code/Model-Based-MCP"
    # Don't exit — continue with other steps
else
    if [[ -d "$MBMCP_DIR/.venv" ]]; then
        ok "Virtual environment already exists at $MBMCP_DIR/.venv"
    else
        if $DRY_RUN; then
            dry "cd $MBMCP_DIR && uv sync"
        else
            info "Setting up Python environment with uv..."
            (cd "$MBMCP_DIR" && "$UV_BIN" sync)
            ok "Python environment ready"
        fi
    fi

    # Verify the MCP server can at least import
    if $DRY_RUN; then
        dry "Verify Model-Based-MCP imports correctly"
    else
        info "Verifying Model-Based-MCP..."
        if (cd "$MBMCP_DIR" && "$UV_BIN" run python -c "from model_based_mcp import server; print('OK')" 2>&1); then
            ok "Model-Based-MCP verified working"
        else
            warn "Model-Based-MCP import check had issues (may need deps installed)"
        fi
    fi
fi

# ============================================================================
# STEP 5: Papyrus-to-YAML Converter (Delta's integration module)
# ============================================================================
step "Step 5/6: Papyrus-to-YAML converter"

DESIGN_DOC="$HOME/Code/Rhode.Notes/analysis/papyrus-mbmcp-integration-design.md"

if [[ -f "$CONVERTER_MODULE" ]]; then
    ok "Converter module already exists: $CONVERTER_MODULE"
    # Ensure lxml is available
    if $DRY_RUN; then
        dry "Ensure lxml is in Model-Based-MCP dependencies"
    else
        if (cd "$MBMCP_DIR" && "$UV_BIN" run python -c "import lxml; print('OK')" 2>/dev/null); then
            ok "lxml dependency available"
        else
            info "Adding lxml to Model-Based-MCP dependencies..."
            (cd "$MBMCP_DIR" && "$UV_BIN" add lxml 2>&1) || warn "Could not add lxml — add manually to pyproject.toml"
        fi
    fi
elif [[ -f "$DESIGN_DOC" ]]; then
    info "Delta's design doc found at $DESIGN_DOC"
    info "Converter module not yet implemented at $CONVERTER_MODULE"
    info "When the converter is added, re-run this script to install its dependencies."
    # Proactively install lxml since Delta said it's needed
    if $DRY_RUN; then
        dry "Pre-install lxml dependency for future converter"
    else
        if (cd "$MBMCP_DIR" && "$UV_BIN" run python -c "import lxml" 2>/dev/null); then
            ok "lxml already available"
        else
            info "Pre-installing lxml (needed by converter)..."
            (cd "$MBMCP_DIR" && "$UV_BIN" add lxml 2>&1) || warn "Could not add lxml"
        fi
    fi
else
    info "Converter not yet available (Delta's design in progress)."
    info "Design doc expected at: $DESIGN_DOC"
    info "Converter module expected at: $CONVERTER_MODULE"
    info "Re-run this script after the converter is implemented."
    warn "Skipping converter setup — will be available in a future run."
fi

# ============================================================================
# STEP 6: Convenience Launcher Scripts
# ============================================================================
step "Step 6/6: Convenience launcher scripts"

run mkdir -p "$BIN_DIR"

# --- ~/bin/papyrus ---
PAPYRUS_LAUNCHER="$BIN_DIR/papyrus"
if [[ -f "$PAPYRUS_LAUNCHER" ]]; then
    ok "Launcher already exists: $PAPYRUS_LAUNCHER"
else
    if $DRY_RUN; then
        dry "Create $PAPYRUS_LAUNCHER"
    else
        cat > "$PAPYRUS_LAUNCHER" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Launch Eclipse Papyrus Desktop
# Usage: papyrus [eclipse args...]
set -euo pipefail

PAPYRUS_HOME="$HOME/Apps/Papyrus-Desktop"

if [[ ! -x "$PAPYRUS_HOME/eclipse" ]]; then
    echo "Error: Papyrus Desktop not found at $PAPYRUS_HOME"
    echo "Run ~/Code/Model-Based-MCP/scripts/install.sh to install."
    exit 1
fi

# Ensure display is set
export DISPLAY="${DISPLAY:-:0}"

# Default workspace
WORKSPACE="${PAPYRUS_WORKSPACE:-$HOME/eclipse-workspace}"

echo "Starting Papyrus Desktop..."
echo "  Install: $PAPYRUS_HOME"
echo "  Workspace: $WORKSPACE"
echo "  Display: $DISPLAY"

exec "$PAPYRUS_HOME/eclipse" -data "$WORKSPACE" "$@"
LAUNCHER_EOF
        chmod +x "$PAPYRUS_LAUNCHER"
        ok "Created $PAPYRUS_LAUNCHER"
    fi
fi

# --- ~/bin/syson-start ---
SYSON_START="$BIN_DIR/syson-start"
if [[ -f "$SYSON_START" ]]; then
    ok "Launcher already exists: $SYSON_START"
else
    if $DRY_RUN; then
        dry "Create $SYSON_START"
    else
        cat > "$SYSON_START" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Start Eclipse SysON (SysML v2 web tool)
# Usage: syson-start
set -euo pipefail

SYSON_DIR="$HOME/Apps/SysON"
COMPOSE_FILE="$SYSON_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Error: SysON not set up — docker-compose.yml not found at $SYSON_DIR"
    echo "Run ~/Code/Model-Based-MCP/scripts/install.sh to set up."
    exit 1
fi

# Determine compose command
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    echo "Error: Docker Compose not found."
    exit 1
fi

# Check if already running
if $COMPOSE -f "$COMPOSE_FILE" ps --status running 2>/dev/null | grep -q "syson-app"; then
    echo "SysON is already running."
    echo "Access at: http://localhost:$(grep -oP '"\K\d+(?=:8080")' "$COMPOSE_FILE" || echo 8080)"
    exit 0
fi

# Check port
PORT=$(grep -oP '"\K\d+(?=:8080")' "$COMPOSE_FILE" 2>/dev/null || echo "8080")
if ss -tlnp 2>/dev/null | grep -q ":${PORT} "; then
    echo "Warning: Port $PORT is already in use by another service."
    echo "Edit $COMPOSE_FILE to change the port mapping, then try again."
    exit 1
fi

echo "Starting SysON..."
$COMPOSE -f "$COMPOSE_FILE" up -d

echo ""
echo "SysON is starting up (may take 30-60 seconds)..."
echo "Access at: http://localhost:${PORT}"
echo ""
echo "Check logs: docker compose -f $COMPOSE_FILE logs -f app"
echo "Stop:       syson-stop"
LAUNCHER_EOF
        chmod +x "$SYSON_START"
        ok "Created $SYSON_START"
    fi
fi

# --- ~/bin/syson-stop ---
SYSON_STOP="$BIN_DIR/syson-stop"
if [[ -f "$SYSON_STOP" ]]; then
    ok "Launcher already exists: $SYSON_STOP"
else
    if $DRY_RUN; then
        dry "Create $SYSON_STOP"
    else
        cat > "$SYSON_STOP" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Stop Eclipse SysON
# Usage: syson-stop [--clean]
#   --clean: Also remove database volume (lose all models)
set -euo pipefail

SYSON_DIR="$HOME/Apps/SysON"
COMPOSE_FILE="$SYSON_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Error: SysON not set up at $SYSON_DIR"
    exit 1
fi

# Determine compose command
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    echo "Error: Docker Compose not found."
    exit 1
fi

if [[ "${1:-}" == "--clean" ]]; then
    echo "Stopping SysON and removing data volumes..."
    $COMPOSE -f "$COMPOSE_FILE" down -v
    echo "SysON stopped. All model data has been removed."
else
    echo "Stopping SysON (data preserved)..."
    $COMPOSE -f "$COMPOSE_FILE" down
    echo "SysON stopped. Data preserved — run 'syson-start' to resume."
fi
LAUNCHER_EOF
        chmod +x "$SYSON_STOP"
        ok "Created $SYSON_STOP"
    fi
fi

# --- ~/bin/mbmcp (Model-Based-MCP server) ---
MBMCP_LAUNCHER="$BIN_DIR/mbmcp"
if [[ -f "$MBMCP_LAUNCHER" ]]; then
    ok "Launcher already exists: $MBMCP_LAUNCHER"
else
    if $DRY_RUN; then
        dry "Create $MBMCP_LAUNCHER"
    else
        cat > "$MBMCP_LAUNCHER" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Launch Model-Based-MCP server
# Usage: mbmcp [args...]
set -euo pipefail

MBMCP_DIR="$HOME/Code/Model-Based-MCP"
UV_BIN="${UV_BIN:-$HOME/.local/bin/uv}"

if [[ ! -d "$MBMCP_DIR" ]]; then
    echo "Error: Model-Based-MCP not found at $MBMCP_DIR"
    exit 1
fi

if [[ ! -x "$UV_BIN" ]] && command -v uv &>/dev/null; then
    UV_BIN="$(command -v uv)"
fi

cd "$MBMCP_DIR"
exec "$UV_BIN" run model-based-mcp "$@"
LAUNCHER_EOF
        chmod +x "$MBMCP_LAUNCHER"
        ok "Created $MBMCP_LAUNCHER"
    fi
fi

# Ensure ~/bin is on PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not on your PATH"
    info "Add this to your ~/.bashrc or ~/.profile:"
    info "  export PATH=\"\$HOME/bin:\$PATH\""
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}  Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""

# Papyrus status
if [[ -x "$PAPYRUS_DIR/eclipse" ]]; then
    echo -e "  ${GREEN}*${NC} Papyrus Desktop: ${GREEN}Installed${NC} at $PAPYRUS_DIR"
    echo -e "    Launch: ${CYAN}papyrus${NC}"
else
    echo -e "  ${YELLOW}*${NC} Papyrus Desktop: ${YELLOW}Not installed${NC} (download may have failed)"
fi

# SysON status
if [[ -f "$SYSON_DIR/docker-compose.yml" ]]; then
    echo -e "  ${GREEN}*${NC} SysON:           ${GREEN}Ready${NC} at $SYSON_DIR"
    echo -e "    Start: ${CYAN}syson-start${NC}  |  Stop: ${CYAN}syson-stop${NC}"
    echo -e "    Access: ${CYAN}http://localhost:${SYSON_PORT}${NC}"
else
    echo -e "  ${YELLOW}*${NC} SysON:           ${YELLOW}Not configured${NC}"
fi

# Model-Based-MCP status
if [[ -d "$MBMCP_DIR/.venv" ]]; then
    echo -e "  ${GREEN}*${NC} Model-Based-MCP: ${GREEN}Ready${NC} at $MBMCP_DIR"
    echo -e "    Launch: ${CYAN}mbmcp${NC}"
else
    echo -e "  ${YELLOW}*${NC} Model-Based-MCP: ${YELLOW}Not configured${NC}"
fi

# Converter status
if [[ -f "$CONVERTER_MODULE" ]]; then
    echo -e "  ${GREEN}*${NC} Papyrus Converter: ${GREEN}Installed${NC}"
else
    echo -e "  ${YELLOW}*${NC} Papyrus Converter: ${YELLOW}Pending${NC} (Delta's design in progress)"
fi

# Launchers
echo ""
echo -e "  ${BOLD}Launcher scripts in $BIN_DIR:${NC}"
for script in papyrus syson-start syson-stop mbmcp; do
    if [[ -x "$BIN_DIR/$script" ]]; then
        echo -e "    ${GREEN}*${NC} $script"
    fi
done

echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo -e "    papyrus          # Launch Papyrus Desktop GUI"
echo -e "    syson-start       # Start SysON web app (Docker)"
echo -e "    syson-stop        # Stop SysON"
echo -e "    mbmcp             # Run Model-Based-MCP server"
echo ""
