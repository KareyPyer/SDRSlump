#!/bin/bash
###############################################################################
#  TORRE BERT 2.0 — Post-Installation Ubuntu pour l'Écoute Spatiale
#  Inspiré par les frères Judica-Cordiglia
#  Cible : Ubuntu 22.04/24.04 LTS (x86_64 ou ARM64 pour Raspberry Pi 4/5)
#  Mission : Interception de communications spatiales, télémétrie satellite,
#            signaux de l'espace profond, ISS, météo spatiale, Inmarsat, Iridium
#  Matériel : RTL-SDR v3/v4, HackRF One, LimeSDR Mini, Airspy HF+, 
#             PlutoSDR ADALM-PLUTO, Nooelec Ham It Up (downconverter),
#             SPF5189Z LNA, filtres SAW, antenne QFH / Yagi / Discone
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# ═══════════════════════════════════════════════════════════════════════════
#  CONFIGURATION — À ADAPTER SELON VOTRE SHACK
# ═══════════════════════════════════════════════════════════════════════════

CALLSIGN="IK1QOD"              # Signe d'appel fictif des frères J-C
STATION_NAME="TorreBert-2.0"
INSTALL_DIR="/opt/torrebert"
SDR_USER="${SUDO_USER:-$USER}"
LOG_FILE="/var/log/torrebert_install.log"
TLE_DIR="$INSTALL_DIR/tle"
RECORDINGS_DIR="$INSTALL_DIR/enregistrements"

# Fréquences d'intérêt (référence)
FREQ_ISS_VOICE="145.800M"
FREQ_ISS_APRS="145.825M"
FREQ_ISS_SSTV="145.800M"
FREQ_NOAA15="137.620M"
FREQ_NOAA18="137.9125M"
FREQ_NOAA19="137.100M"
FREQ_METEOR_M2="137.100M"
FREQ_METEOR_M2_2="137.900M"
FREQ_GOES16="1694.1M"
FREQ_IRIDIUM="1626.5625M"
FREQ_INMARSAT="1537.47M"
FREQ_DSN_XBAND="8420M"       # Deep Space Network — nécessite downconverter

# ═══════════════════════════════════════════════════════════════════════════
#  COULEURS & LOGS
# ═══════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() {
    local level="$1"
    local msg="$2"
    local color="$NC"
    case "$level" in
        INFO)  color="$BLUE" ;;
        OK)    color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERR)   color="$RED" ;;
        SPACE) color="$CYAN" ;;
        JUDICA) color="$MAGENTA" ;;
    esac
    echo -e "${color}[${level}]${NC} $msg" | tee -a "$LOG_FILE"
}

banner() {
    clear
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════════════╗
    ║                                                                       ║
    ║     ████████╗ ██████╗ ██████╗ ██████╗ ███████╗    ██████╗ ███████╗██████╗ ████████╗    ║
    ║     ╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝    ██╔══██╗██╔════╝██╔══██╗╚══██╔══╝    ║
    ║        ██║   ██║   ██║██████╔╝██████╔╝█████╗      ██████╔╝█████╗  ██║  ██║   ██║       ║
    ║        ██║   ██║   ██║██╔══██╗██╔══██╗██╔══╝      ██╔══██╗██╔══╝  ██║  ██║   ██║       ║
    ║        ██║   ╚██████╔╝██║  ██║██║  ██║███████╗    ██████╔╝███████╗██████╔╝   ██║       ║
    ║        ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝    ╚═════╝ ╚══════╝╚═════╝    ╚═╝       ║
    ║                                                                       ║
    ║           "Les étoiles ne se taisent jamais. Il faut savoir écouter."   ║
    ║                              — Frères Judica-Cordiglia, 1960 & 2026      ║
    ║                                                                       ║
    ╚═══════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
#  FONCTIONS UTILITAIRES
# ═══════════════════════════════════════════════════════════════════════════

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERR "Ce script doit être exécuté en root. Utilisez : sudo $0"
        exit 1
    fi
}

install_apt() {
    apt-get install -y "$@" || {
        log WARN "Échec partiel pour : $*"
        return 1
    }
}

clone_or_update() {
    local repo="$1"
    local dest="$2"
    local branch="${3:-}"
    if [[ -d "$dest/.git" ]]; then
        log INFO "Mise à jour de $(basename "$dest")..."
        git -C "$dest" fetch --depth 1
        git -C "$dest" reset --hard origin/${branch:-$(git -C "$dest" rev-parse --abbrev-ref HEAD)}
    else
        log INFO "Clonage de $(basename "$dest")..."
        if [[ -n "$branch" ]]; then
            git clone --depth 1 --branch "$branch" "$repo" "$dest"
        else
            git clone --depth 1 "$repo" "$dest"
        fi
    fi
}

build_cmake() {
    local src_dir="$1"
    local extra_args="${2:-}"
    cd "$src_dir"
    mkdir -p build && cd build
    cmake .. $extra_args
    make -j$(nproc)
    make install
    ldconfig
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 1 : PRÉPARATION DU SYSTÈME
# ═══════════════════════════════════════════════════════════════════════════

prepare_system() {
    log SPACE "=== ÉTAPE 1/12 : Préparation du système ==="
    log JUDICA "Configuration de la station $STATION_NAME pour $CALLSIGN"

    dpkg --add-architecture i386 2>/dev/null || true

    log INFO "Mise à jour des dépôts..."
    apt-get update
    apt-get upgrade -y

    log INFO "Installation des dépendances fondamentales..."
    install_apt \
        build-essential cmake git wget curl \
        libusb-1.0-0-dev libusb-1.0-0 \
        libfftw3-dev libfftw3-bin pkg-config \
        autoconf automake libtool libncurses5-dev \
        libboost-all-dev \
        python3-pip python3-dev python3-venv \
        python3-numpy python3-scipy python3-matplotlib \
        python3-pandas python3-requests python3-flask \
        qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools \
        libqt5svg5-dev libqt5widgets5 libqt5gui5 \
        libqt5network5-dev libqt5serialport5-dev \
        libqt5charts5-dev libqt5multimedia5-plugins \
        libgl1-mesa-dev libglu1-mesa-dev \
        libssl-dev zlib1g-dev libcurl4-openssl-dev \
        libxml2-dev libsqlite3-dev \
        sox libsox-fmt-all \
        libjpeg-dev libpng-dev \
        libsndfile1-dev libliquid-dev libitpp-dev \
        libpcap-dev liborc-0.4-dev \
        doxygen graphviz swig \
        xterm gnome-terminal htop iotop \
        nmap netcat-openbsd tcpdump ngrep \
        chromium-browser || google-chrome-stable || firefox || true

    # Rust (pour certains outils modernes)
    log INFO "Installation de Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null || \
        log WARN "Rust déjà installé ou échec"
    source "$HOME/.cargo/env" 2>/dev/null || true

    # Python packages essentiels
    log INFO "Installation des packages Python..."
    pip3 install --upgrade pip 2>/dev/null || true
    pip3 install pyserial pyusb construct bitstring crcmod \
        scapy ephem skyfield sgp4 \
        jupyterlab plotly dash 2>/dev/null || \
        log WARN "Certains packages Python n'ont pas pu être installés"

    # Création des répertoires de travail
    mkdir -p "$INSTALL_DIR"/{aviation,maritime,satellites,deep_space,iss,meteo,gsm,sigint,tools,scripts}
    mkdir -p "$TLE_DIR"
    mkdir -p "$RECORDINGS_DIR"/{noaa,meteor,goes,iss,iridium,inmarsat,unknown}
    chown -R "$SDR_USER:$SDR_USER" "$INSTALL_DIR"

    log OK "Système préparé. Prêt pour l'installation des outils spatiaux."
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 2 : DRIVERS SDR & DOWNCONVERTERS
# ═══════════════════════════════════════════════════════════════════════════

install_sdr_stack() {
    log SPACE "=== ÉTAPE 2/12 : Drivers SDR, Downconverters & Amplis ==="
    log JUDICA "Configuration pour RTL-SDR, HackRF, LimeSDR, Airspy, PlutoSDR"
    log JUDICA "Support des downconverters (Ham It Up, SpyVerter) et LNA"

    # RTL-SDR (version Osmocom + version Keenerd pour les bias-tee)
    log INFO "Installation RTL-SDR (Osmocom)..."
    install_apt rtl-sdr librtlsdr0 librtlsdr-dev || true

    # Règles udev RTL-SDR
    if [[ ! -f "/etc/udev/rules.d/rtl-sdr.rules" ]]; then
        curl -sL https://raw.githubusercontent.com/osmocom/rtl-sdr/master/rtl-sdr.rules \
            -o /etc/udev/rules.d/rtl-sdr.rules
    fi

    # HackRF
    log INFO "Installation HackRF..."
    install_apt hackrf libhackrf0 libhackrf-dev || true

    # BladeRF
    log INFO "Installation BladeRF..."
    install_apt bladerf libbladerf2 libbladerf-dev bladerf-firmware-hosted || true

    # LimeSDR
    log INFO "Installation LimeSDR..."
    install_apt limesuite liblimesuite-dev limesuite-udev || true

    # Airspy (R2 + HF+)
    log INFO "Installation Airspy..."
    install_apt airspy libairspy0 libairspy-dev airspyhf libairspyhf-dev || true

    # PlutoSDR (libiio)
    log INFO "Installation libiio (PlutoSDR)..."
    install_apt libiio-dev libiio0 iiotools || true

    # USRP / UHD
    log INFO "Installation UHD (USRP)..."
    install_apt libuhd-dev uhd-host || true
    uhd_images_downloader || log WARN "Images UHD non téléchargées"

    # SoapySDR (abstraction matérielle)
    log INFO "Installation SoapySDR..."
    install_apt soapysdr-tools soapysdr-module-all || true

    # SoapyRTLSDR
    install_apt soapysdr-module-rtlsdr 2>/dev/null || true

    # SoapyAirspy
    install_apt soapysdr-module-airspy 2>/dev/null || true

    # SoapyHackRF
    install_apt soapysdr-module-hackrf 2>/dev/null || true

    # SoapyLMS7 (LimeSDR)
    install_apt soapysdr-module-lms7 2>/dev/null || true

    # SoapyRemote (accès réseau au SDR)
    install_apt soapysdr-server 2>/dev/null || true

    # Règles udev globales
    udevadm control --reload-rules
    udevadm trigger

    # Groupes utilisateur
    usermod -aG plugdev "$SDR_USER" 2>/dev/null || true
    usermod -aG dialout "$SDR_USER" 2>/dev/null || true
    usermod -aG audio "$SDR_USER" 2>/dev/null || true

    log OK "Stack SDR configuré. Redémarrage nécessaire pour les règles udev."
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 3 : GNU RADIO & MODULES SPATIAUX
# ═══════════════════════════════════════════════════════════════════════════

install_gnuradio_spatial() {
    log SPACE "=== ÉTAPE 3/12 : GNU Radio & Modules Spatiaux ==="
    log JUDICA "La base de tout traitement de signal spatial"

    install_apt gnuradio gnuradio-dev || true
    install_apt gr-osmosdr gr-fcdproplus gr-iqbal || true
    install_apt gr-soapy 2>/dev/null || log WARN "gr-soapy non disponible"

    # Module correctiq (correction IQ pour réception satellite)
    log INFO "Installation de gr-correctiq..."
    clone_or_update "https://github.com/ghostop14/gr-correctiq.git" "$INSTALL_DIR/tools/gr-correctiq"
    build_cmake "$INSTALL_DIR/tools/gr-correctiq"

    # Module pour le traitement des signaux faibles (satellites lointains)
    log INFO "Installation de gr-fosphor (visualisation GPU)..."
    install_apt gr-fosphor 2>/dev/null || \
        clone_or_update "https://github.com/osmocom/gr-fosphor.git" "$INSTALL_DIR/tools/gr-fosphor" && \
        build_cmake "$INSTALL_DIR/tools/gr-fosphor" || log WARN "gr-fosphor non installé"

    log OK "GNU Radio et modules spatiaux installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 4 : SUIVI ORBITAL & PRÉDICTION (TLE)
# ═══════════════════════════════════════════════════════════════════════════

install_orbital_tracking() {
    log SPACE "=== ÉTAPE 4/12 : Suivi Orbital & TLE ==="
    log JUDICA "Sans prédictions précises, pas d'interception. Les TLE sont notre carte du ciel."

    # Gpredict
    log INFO "Installation de Gpredict..."
    install_apt gpredict || true

    # Configuration Gpredict pour le radioamateurisme spatial
    mkdir -p /home/"$SDR_USER"/.config/Gpredict
    cat > /home/"$SDR_USER"/.config/Gpredict/gpredict.cfg << EOF
[GLOBAL]
# Configuration Torre Bert 2.0
QTH_FILE=/home/$SDR_USER/.config/Gpredict/qth.dat

[MODULES]
DEFAULT=default
EOF

    # Script de mise à jour automatique des TLE
    cat > "$INSTALL_DIR/scripts/update_tle.sh" << 'EOF'
#!/bin/bash
# Mise à jour automatique des éléments orbitaux (TLE)
# Pour Torre Bert 2.0

TLE_DIR="/opt/torrebert/tle"
mkdir -p "$TLE_DIR"

echo "[$(date)] Mise à jour des TLE..."

# TLE NOAA (météo)
curl -s "https://www.celestrak.com/NORAD/elements/weather.txt" -o "$TLE_DIR/weather.txt"

# TLE Amateur radio
curl -s "https://www.celestrak.com/NORAD/elements/amateur.txt" -o "$TLE_DIR/amateur.txt"

# TLE Stations spatiales (ISS, Tiangong)
curl -s "https://www.celestrak.com/NORAD/elements/stations.txt" -o "$TLE_DIR/stations.txt"

# TLE GPS
curl -s "https://www.celestrak.com/NORAD/elements/gps-ops.txt" -o "$TLE_DIR/gps.txt"

# TLE GLONASS
curl -s "https://www.celestrak.com/NORAD/elements/glo-ops.txt" -o "$TLE_DIR/glonass.txt"

# TLE Galileo
curl -s "https://www.celestrak.com/NORAD/elements/galileo.txt" -o "$TLE_DIR/galileo.txt"

# TLE Iridium
curl -s "https://www.celestrak.com/NORAD/elements/iridium.txt" -o "$TLE_DIR/iridium.txt"

# TLE Orbcomm
curl -s "https://www.celestrak.com/NORAD/elements/orbcomm.txt" -o "$TLE_DIR/orbcomm.txt"

# TLE Inmarsat
curl -s "https://www.celestrak.com/NORAD/elements/inmarsat.txt" -o "$TLE_DIR/inmarsat.txt"

# TLE Globalstar
curl -s "https://www.celestrak.com/NORAD/elements/globalstar.txt" -o "$TLE_DIR/globalstar.txt"

# TLE GOES
curl -s "https://www.celestrak.com/NORAD/elements/goes.txt" -o "$TLE_DIR/goes.txt"

# TLE Intelsat
curl -s "https://www.celestrak.com/NORAD/elements/intelsat.txt" -o "$TLE_DIR/intelsat.txt"

# TLE SES
curl -s "https://www.celestrak.com/NORAD/elements/ses.txt" -o "$TLE_DIR/ses.txt"

# TLE Starlink
curl -s "https://www.celestrak.com/NORAD/elements/starlink.txt" -o "$TLE_DIR/starlink.txt"

# TLE Oneweb
curl -s "https://www.celestrak.com/NORAD/elements/oneweb.txt" -o "$TLE_DIR/oneweb.txt"

# TLE Active Spacecrafts (sondes, etc.)
curl -s "https://www.celestrak.com/NORAD/elements/active.txt" -o "$TLE_DIR/active.txt"

# TLE Space Stations
curl -s "https://www.celestrak.com/NORAD/elements/stations.txt" -o "$TLE_DIR/stations.txt"

echo "[$(date)] TLE mis à jour. Total fichiers : $(ls $TLE_DIR/*.txt | wc -l)"
EOF
    chmod +x "$INSTALL_DIR/scripts/update_tle.sh"

    # Exécution initiale
    "$INSTALL_DIR/scripts/update_tle.sh"

    # Cron pour mise à jour automatique (tous les jours à 6h)
    (crontab -u "$SDR_USER" -l 2>/dev/null; echo "0 6 * * * /opt/torrebert/scripts/update_tle.sh >> /var/log/tle_update.log 2>&1") | crontab -u "$SDR_USER" - || true

    # PREDICT (alternative à Gpredict, en ligne de commande)
    log INFO "Installation de PREDICT..."
    clone_or_update "https://github.com/kd2bd/predict.git" "$INSTALL_DIR/tools/predict"
    cd "$INSTALL_DIR/tools/predict"
    make
    cp predict /usr/local/bin/ 2>/dev/null || true

    # PyEphem / Skyfield (Python)
    pip3 install ephem skyfield sgp4 2>/dev/null || true

    log OK "Suivi orbital configuré. TLE téléchargés pour $(ls "$TLE_DIR"/*.txt 2>/dev/null | wc -l) constellations."
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 5 : DÉCODAGE SATELLITES AMATEURS & TÉLÉMÉTRIE
# ═══════════════════════════════════════════════════════════════════════════

install_satellite_decoders() {
    log SPACE "=== ÉTAPE 5/12 : Décodeurs Satellites & Télémétrie ==="
    log JUDICA "Chaque satellite murmure ses secrets. Il faut savoir les comprendre."

    # gr-satellites (le couteau suisse du décodage satellite)
    log INFO "Installation de gr-satellites..."
    clone_or_update "https://github.com/daniestevez/gr-satellites.git" "$INSTALL_DIR/satellites/gr-satellites" "maint-3.10"
    cd "$INSTALL_DIR/satellites/gr-satellites"
    mkdir -p build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local
    make -j$(nproc)
    make install
    ldconfig

    # SatDump (décodage météo et scientifique)
    log INFO "Installation de SatDump..."
    clone_or_update "https://github.com/SatDump/SatDump.git" "$INSTALL_DIR/satellites/SatDump"
    cd "$INSTALL_DIR/satellites/SatDump"
    mkdir -p build && cd build
    cmake .. -DBUILD_GUI=ON -DCMAKE_INSTALL_PREFIX=/usr/local
    make -j$(nproc)
    make install
    ldconfig

    # Décodeurs spécifiques

    # --- NOAA APT ---
    log INFO "Installation de noaa-apt (décodage NOAA APT)..."
    clone_or_update "https://github.com/martinber/noaa-apt.git" "$INSTALL_DIR/satellites/noaa-apt"
    cd "$INSTALL_DIR/satellites/noaa-apt"
    cargo build --release 2>/dev/null && \
        cp target/release/noaa-apt /usr/local/bin/ || \
        log WARN "noaa-apt nécessite Rust"

    # --- MeteorDemod (Meteor M2) ---
    log INFO "Installation de MeteorDemod..."
    clone_or_update "https://github.com/Digitelektro/MeteorDemod.git" "$INSTALL_DIR/satellites/MeteorDemod"
    cd "$INSTALL_DIR/satellites/MeteorDemod"
    mkdir -p build && cd build
    cmake ..
    make
    cp meteor_demod /usr/local/bin/

    # --- XRIT Decoder (GOES HRIT/ LRIT) ---
    log INFO "Installation de xrit-rx..."
    clone_or_update "https://github.com/sam210723/xrit-rx.git" "$INSTALL_DIR/satellites/xrit-rx" 2>/dev/null || \
        log WARN "xrit-rx non disponible"

    # --- GOES Tools ---
    log INFO "Installation de goestools..."
    clone_or_update "https://github.com/pietern/goestools.git" "$INSTALL_DIR/satellites/goestools"
    cd "$INSTALL_DIR/satellites/goestools"
    mkdir -p build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local
    make -j$(nproc)
    make install || log WARN "goestools compilation échouée"

    # --- SDR4Space (traitement satellite avancé) ---
    log INFO "Installation de sdr4space.lite..."
    clone_or_update "https://github.com/altillimity/sdr4space.git" "$INSTALL_DIR/satellites/sdr4space" 2>/dev/null || \
        log WARN "sdr4space non disponible"

    # --- Qfits (traitement images satellites) ---
    install_apt qfits 2>/dev/null || true

    log OK "Décodeurs satellites installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 6 : ISS — VOIX, SSTV, APRS, TÉLÉMÉTRIE
# ═══════════════════════════════════════════════════════════════════════════

install_iss_tools() {
    log SPACE "=== ÉTAPE 6/12 : Outils ISS (SSTV, Voix, APRS, Télémétrie) ==="
    log JUDICA "La Station Spatiale Internationale est notre voisine. Écoutons-la."

    # QSSTV (décodage SSTV)
    log INFO "Installation de QSSTV..."
    install_apt qsstv || true

    # Direwolf (APRS / packet radio)
    log INFO "Installation de Direwolf..."
    install_apt direwolf || true

    # Fldigi (modes numériques)
    log INFO "Installation de Fldigi..."
    install_apt fldigi flmsg flwrap flamp flnet || true

    # Script de réception ISS SSTV automatique
    cat > "$INSTALL_DIR/scripts/iss_sstv_receive.sh" << 'EOF'
#!/bin/bash
# Réception automatique SSTV depuis l'ISS
# Fréquence : 145.800 MHz (FM)
# Mode : PD120

FREQ="145800000"
DURATION=240  # 4 minutes max par passe
OUTPUT_DIR="/opt/torrebert/enregistrements/iss"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "[$TIMESTAMP] Démarrage réception ISS SSTV sur 145.800 MHz..."

# Enregistrement audio via rtl_fm
rtl_fm -f ${FREQ} -s 48000 -g 42 -p 0 -E wav -E deemp -F 9 - |
    sox -t raw -e signed -c 1 -b 16 -r 48000 - "$OUTPUT_DIR/iss_sstv_${TIMESTAMP}.wav" \
    silence 1 0.5 1% 1 10.0 1%

echo "[$TIMESTAMP] Réception terminée. Fichier : $OUTPUT_DIR/iss_sstv_${TIMESTAMP}.wav"
EOF
    chmod +x "$INSTALL_DIR/scripts/iss_sstv_receive.sh"

    # Script APRS ISS
    cat > "$INSTALL_DIR/scripts/iss_aprs_receive.sh" << 'EOF'
#!/bin/bash
# Réception APRS depuis l'ISS
# Fréquence : 145.825 MHz

FREQ="145825000"

echo "Démarrage réception APRS ISS sur 145.825 MHz..."
echo "Utilisez : direwolf -t 0 -p"

rtl_fm -f ${FREQ} -s 48000 -g 42 -p 0 - | \
    direwolf -t 0 -c /etc/direwolf.conf -r 48000 -
EOF
    chmod +x "$INSTALL_DIR/scripts/iss_aprs_receive.sh"

    log OK "Outils ISS installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 7 : IRIDIUM & INMARSAT — COMMUNICATIONS PAR SATELLITE
# ═══════════════════════════════════════════════════════════════════════════

install_iridium_inmarsat() {
    log SPACE "=== ÉTAPE 7/12 : Iridium & Inmarsat ==="
    log JUDICA "Les constellations commerciales portent aussi des secrets..."

    # --- IRIDIUM ---

    # gr-iridium
    log INFO "Installation de gr-iridium..."
    clone_or_update "https://github.com/muccc/gr-iridium.git" "$INSTALL_DIR/satellites/gr-iridium"
    cd "$INSTALL_DIR/satellites/gr-iridium"
    mkdir -p build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local
    make -j$(nproc)
    make install
    ldconfig

    # Iridium Toolkit
    log INFO "Installation de Iridium Toolkit..."
    clone_or_update "https://github.com/muccc/iridium-toolkit.git" "$INSTALL_DIR/satellites/iridium-toolkit"
    cd "$INSTALL_DIR/satellites/iridium-toolkit"
    chmod +x *.py
    ln -sf "$INSTALL_DIR/satellites/iridium-toolkit/iridium-parser.py" /usr/local/bin/iridium-parser 2>/dev/null || true
    ln -sf "$INSTALL_DIR/satellites/iridium-toolkit/iridium-extractor.py" /usr/local/bin/iridium-extractor 2>/dev/null || true

    # IridiumLive (visualisation)
    log INFO "Installation de IridiumLive..."
    clone_or_update "https://github.com/muccc/iridium-toolkit.git" "$INSTALL_DIR/satellites/iridiumlive" 2>/dev/null || true

    # --- INMARSAT ---

    # JAERO (Inmarsat Aero / ACARS satellite)
    log INFO "Installation de JAERO (Inmarsat Aero)..."
    install_apt libqt5serialport5-dev || true
    clone_or_update "https://github.com/jontio/JAERO.git" "$INSTALL_DIR/satellites/JAERO"
    cd "$INSTALL_DIR/satellites/JAERO"
    qmake JAERO.pro
    make
    cp JAERO /usr/local/bin/

    # Inmarsat-C decoder
    log INFO "Installation de inmarsatc-parser..."
    clone_or_update "https://github.com/cropinghigh/inmarsatc-parser.git" "$INSTALL_DIR/satellites/inmarsatc-parser" 2>/dev/null || \
        log WARN "inmarsatc-parser non disponible"

    # OpenSAT (Inmarsat)
    clone_or_update "https://github.com/opensat-project/opensat.git" "$INSTALL_DIR/satellites/opensat" 2>/dev/null || \
        log WARN "opensat non disponible"

    # Script de réception Iridium
    cat > "$INSTALL_DIR/scripts/iridium_receive.sh" << 'EOF'
#!/bin/bash
# Réception Iridium
# Fréquence centrale : 1626.5625 MHz
# Nécessite un SDR avec couverture > 1.6 GHz (HackRF, LimeSDR, Airspy HF+)

FREQ="1626562500"
SAMPLE_RATE="2000000"
OUTPUT_DIR="/opt/torrebert/enregistrements/iridium"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "Démarrage réception Iridium sur 1626.5625 MHz..."
echo "Matériel recommandé : HackRF, LimeSDR, ou Airspy HF+ avec downconverter"

# Extraction avec gr-iridium
iridium-extractor -D 4 --offline "$OUTPUT_DIR/iridium_${TIMESTAMP}.wav" 2>/dev/null || \
    echo "Utilisez : osmocom_fft -f $FREQ -s $SAMPLE_RATE pour visualiser"
EOF
    chmod +x "$INSTALL_DIR/scripts/iridium_receive.sh"

    log OK "Outils Iridium & Inmarsat installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 8 : MÉTÉO SPATIALE — NOAA, METEOR, GOES
# ═══════════════════════════════════════════════════════════════════════════

install_weather_satellites() {
    log SPACE "=== ÉTAPE 8/12 : Météo Spatiale (NOAA, Meteor, GOES) ==="
    log JUDICA "Les satellites météo sont les plus bavards du ciel."

    # --- NOAA APT ---
    log INFO "Configuration réception NOAA APT..."

    # wxtoimg (décodage NOAA APT — binaire legacy)
    log INFO "Téléchargement wxtoimg..."
    wget -q "https://wxtoimgrestored.xyz/downloads/wxtoimg-linux-amd64-2.11.2.tar.gz" \
        -O /tmp/wxtoimg.tar.gz 2>/dev/null && \
        tar -xzf /tmp/wxtoimg.tar.gz -C /opt/ && \
        ln -sf /opt/wxtoimg/bin/wxtoimg /usr/local/bin/wxtoimg 2>/dev/null || \
        log WARN "wxtoimg non téléchargé (legacy, peut nécessiter recherche manuelle)"

    # Script automatique NOAA
    cat > "$INSTALL_DIR/scripts/noaa_receive.sh" << 'EOF'
#!/bin/bash
# Réception automatique NOAA APT
# Fréquences : NOAA-15 (137.620), NOAA-18 (137.9125), NOAA-19 (137.100)

SAT="${1:-NOAA-19}"
FREQ="${2:-137100000}"
DURATION="${3:-900}"  # 15 min max
OUTPUT_DIR="/opt/torrebert/enregistrements/noaa"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "[$TIMESTAMP] Démarrage réception $SAT sur $(echo $FREQ | awk '{printf "%.3f", $1/1000000}') MHz..."

rtl_fm -f ${FREQ} -s 48000 -g 42 -p 0 -E wav -E deemp -F 9 - |
    sox -t raw -e signed -c 1 -b 16 -r 48000 - "$OUTPUT_DIR/${SAT}_${TIMESTAMP}.wav" \
    trim 0 ${DURATION}

echo "[$TIMESTAMP] Réception $SAT terminée."
echo "Décodage avec : noaa-apt $OUTPUT_DIR/${SAT}_${TIMESTAMP}.wav -o $OUTPUT_DIR/${SAT}_${TIMESTAMP}.png"
EOF
    chmod +x "$INSTALL_DIR/scripts/noaa_receive.sh"

    # --- METEOR M2 ---
    log INFO "Configuration réception Meteor M2..."

    cat > "$INSTALL_DIR/scripts/meteor_receive.sh" << 'EOF'
#!/bin/bash
# Réception Meteor-M2 (LRPT)
# Fréquence : 137.100 MHz (M2) ou 137.900 MHz (M2-2)

SAT="${1:-METEOR-M2}"
FREQ="${2:-137100000}"
DURATION="${3:-900}"
OUTPUT_DIR="/opt/torrebert/enregistrements/meteor"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "[$TIMESTAMP] Démarrage réception $SAT..."

# Meteor utilise un signal QPSK à 72k or 80k symboles/s
rtl_fm -f ${FREQ} -s 140000 -g 42 -p 0 -M raw - |
    sox -t raw -r 140000 -e signed -b 16 -c 1 - "$OUTPUT_DIR/${SAT}_${TIMESTAMP}.wav" \
    trim 0 ${DURATION}

echo "[$TIMESTAMP] Réception $SAT terminée."
echo "Décodage avec : meteor_demod -B -o $OUTPUT_DIR/${SAT}_${TIMESTAMP}.s $OUTPUT_DIR/${SAT}_${TIMESTAMP}.wav"
EOF
    chmod +x "$INSTALL_DIR/scripts/meteor_receive.sh"

    # --- GOES-R (HRIT) ---
    log INFO "Configuration réception GOES-R..."

    cat > "$INSTALL_DIR/scripts/goes_receive.sh" << 'EOF'
#!/bin/bash
# Réception GOES-R (HRIT)
# Fréquence : 1694.1 MHz
# NÉCESSITE : Parabole ~1m, LNA spécifique 1.7GHz, SDR stable (Airspy R2, LimeSDR)

FREQ="1694100000"
SAMPLE_RATE="2400000"
OUTPUT_DIR="/opt/torrebert/enregistrements/goes"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$OUTPUT_DIR"

echo "[$TIMESTAMP] Démarrage réception GOES sur 1694.1 MHz..."
echo "ATTENTION : Nécessite antenne parabolique et LNA 1.7GHz !"

# Avec goestools
goesrecv -v -c /etc/goesrecv/goesrecv.conf 2>/dev/null || \
    echo "goesrecv non configuré. Utilisez : rtl_fm -f $FREQ -s $SAMPLE_RATE ..."
EOF
    chmod +x "$INSTALL_DIR/scripts/goes_receive.sh"

    log OK "Outils météo spatiale installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 9 : AVIATION (ADS-B, ACARS, VDL2, HFDL)
# ═══════════════════════════════════════════════════════════════════════════

install_aviation() {
    log SPACE "=== ÉTAPE 9/12 : Aviation (ADS-B, ACARS, VDL2, HFDL) ==="
    log JUDICA "Le ciel est traversé de messages. Capturons-les."

    local AVIA_DIR="$INSTALL_DIR/aviation"
    mkdir -p "$AVIA_DIR"

    # readsb (ADS-B moderne)
    log INFO "Installation de readsb..."
    clone_or_update "https://github.com/wiedehopf/readsb.git" "$AVIA_DIR/readsb"
    cd "$AVIA_DIR/readsb"
    make BLADERF=NO RTLSDR=YES AIRCRAFT_HASH=yes
    cp readsb /usr/local/bin/

    # tar1090 (interface web ADS-B)
    log INFO "Installation de tar1090..."
    clone_or_update "https://github.com/wiedehopf/tar1090.git" "$AVIA_DIR/tar1090"
    cd "$AVIA_DIR/tar1090"
    ./install.sh /usr/local/bin/readsb 2>/dev/null || log WARN "tar1090 nécessite configuration manuelle"

    # dump978 (UAT)
    log INFO "Installation de dump978..."
    clone_or_update "https://github.com/flightaware/dump978.git" "$AVIA_DIR/dump978"
    cd "$AVIA_DIR/dump978"
    make
    cp dump978-fa /usr/local/bin/

    # ACARSdec
    log INFO "Installation de ACARSdec..."
    clone_or_update "https://github.com/TLeconte/acarsdec.git" "$AVIA_DIR/acarsdec"
    cd "$AVIA_DIR/acarsdec"
    mkdir -p build && cd build
    cmake .. -Drtl=ON
    make
    cp acarsdec /usr/local/bin/

    # dumpvdl2
    log INFO "Installation de dumpvdl2..."
    clone_or_update "https://github.com/szpajder/dumpvdl2.git" "$AVIA_DIR/dumpvdl2"
    cd "$AVIA_DIR/dumpvdl2"
    mkdir -p build && cd build
    cmake ..
    make
    cp dumpvdl2 /usr/local/bin/

    # dumphfdl
    log INFO "Installation de dumphfdl..."
    clone_or_update "https://github.com/szpajder/dumphfdl.git" "$AVIA_DIR/dumphfdl"
    cd "$AVIA_DIR/dumphfdl"
    mkdir -p build && cd build
    cmake ..
    make
    cp dumphfdl /usr/local/bin/

    # JAERO déjà installé dans la section Inmarsat

    log OK "Outils Aviation installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 10 : ANALYSE SPECTRALE & SIGINT AVANCÉ
# ═══════════════════════════════════════════════════════════════════════════

install_sigint_advanced() {
    log SPACE "=== ÉTAPE 10/12 : Analyse Spectrale & SIGINT Avancé ==="
    log JUDICA "Pour trouver ce que personne ne veut qu'on entende."

    local SIG_DIR="$INSTALL_DIR/sigint"
    mkdir -p "$SIG_DIR"

    # SDR++
    log INFO "Installation de SDR++..."
    clone_or_update "https://github.com/AlexandreRouma/SDRPlusPlus.git" "$SIG_DIR/SDRPlusPlus"
    cd "$SIG_DIR/SDRPlusPlus"
    mkdir -p build && cd build
    cmake .. \
        -DOPT_BUILD_AIRSPYHF_SOURCE=ON \
        -DOPT_BUILD_AIRSPY_SOURCE=ON \
        -DOPT_BUILD_HACKRF_SOURCE=ON \
        -DOPT_BUILD_RTL_SDR_SOURCE=ON \
        -DOPT_BUILD_RTL_TCP_SOURCE=ON \
        -DOPT_BUILD_LIMESDR_SOURCE=ON \
        -DOPT_BUILD_SDRPLAY_SOURCE=ON \
        -DOPT_BUILD_BLADERF_SOURCE=ON \
        -DOPT_BUILD_PLUTOSDR_SOURCE=ON \
        -DOPT_BUILD_AUDIO_SINK=ON \
        -DOPT_BUILD_NEW_PORTAUDIO_SINK=ON
    make -j$(nproc)
    make install
    ldconfig

    # SDRangel
    log INFO "Installation de SDRangel..."
    install_apt sdrangel 2>/dev/null || {
        clone_or_update "https://github.com/f4exb/sdrangel.git" "$SIG_DIR/sdrangel"
        cd "$SIG_DIR/sdrangel"
        mkdir -p build && cd build
        cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local
        make -j$(nproc)
        make install
    }

    # Inspectrum
    log INFO "Installation de Inspectrum..."
    clone_or_update "https://github.com/miek/inspectrum.git" "$SIG_DIR/inspectrum"
    cd "$SIG_DIR/inspectrum"
    mkdir -p build && cd build
    cmake ..
    make
    make install

    # SigDigger
    log INFO "Installation de SigDigger..."
    clone_or_update "https://github.com/BatchDrake/SigDigger.git" "$SIG_DIR/SigDigger"
    cd "$SIG_DIR/SigDigger"
    qmake SigDigger.pro
    make
    cp SigDigger /usr/local/bin/

    # Universal Radio Hacker
    log INFO "Installation de Universal Radio Hacker..."
    pip3 install urh || log WARN "URH non installé"

    # RFCat
    log INFO "Installation de RFCat..."
    pip3 install rfcat || log WARN "RFCat non installé"

    # QSpectrumAnalyzer
    log INFO "Installation de QSpectrumAnalyzer..."
    pip3 install qspectrumanalyzer || log WARN "QSpectrumAnalyzer non installé"

    # Baudline (analyseur spectral haute résolution)
    log INFO "Téléchargement de Baudline..."
    wget -q "https://www.baudline.com/baudline_1.08_linux_x86_64.tar.gz" \
        -O /tmp/baudline.tar.gz 2>/dev/null && \
        tar -xzf /tmp/baudline.tar.gz -C "$SIG_DIR/" && \
        ln -sf "$SIG_DIR/baudline_1.08_linux_x86_64/baudline" /usr/local/bin/baudline 2>/dev/null || \
        log WARN "Baudline non téléchargé (licence requise)"

    log OK "Outils SIGINT avancés installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 11 : RÉSEAU, WI-FI, BLUETOOTH & MONITORING
# ═══════════════════════════════════════════════════════════════════════════

install_network_monitoring() {
    log SPACE "=== ÉTAPE 11/12 : Réseau, Wi-Fi, Bluetooth & Monitoring ==="

    # Wi-Fi
    install_apt kismet kismon 2>/dev/null || true
    pip3 install sparrowwifi 2>/dev/null || true

    # Bluetooth
    install_apt bluez blueman ubertooth 2>/dev/null || true
    clone_or_update "https://github.com/greatscottgadgets/ubertooth.git" "$INSTALL_DIR/tools/ubertooth" 2>/dev/null || true

    # Aircrack-ng
    install_apt aircrack-ng 2>/dev/null || true

    # OpenWebRX (récepteur SDR accessible via navigateur)
    log INFO "Installation d'OpenWebRX..."
    clone_or_update "https://github.com/jketterl/openwebrx.git" "$INSTALL_DIR/tools/openwebrx"
    cd "$INSTALL_DIR/tools/openwebrx"
    pip3 install -r requirements.txt 2>/dev/null || true

    # WebSDR / KiwiSDR (clients web, rien à installer localement)

    log OK "Outils réseau installés"
}

# ═══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 12 : FINALISATION & DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════

finalize() {
    log SPACE "=== ÉTAPE 12/12 : Finalisation & Documentation ==="

    ldconfig

    # Création du manuel de la station
    cat > "$INSTALL_DIR/MANUEL_TORRE_BERT_2.0.txt" << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                    TORRE BERT 2.0 — MANUEL DE LA STATION                        ║
║                    Frères Judica-Cordiglia — 2026                              ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

RÉPERTOIRES :
  /opt/torrebert/aviation/      → Outils aviation (ADS-B, ACARS, VDL2, HFDL)
  /opt/torrebert/maritime/      → Outils maritime (AIS)
  /opt/torrebert/satellites/    → Décodeurs satellites (gr-satellites, SatDump)
  /opt/torrebert/iss/           → Outils ISS (SSTV, APRS)
  /opt/torrebert/meteo/         → Météo spatiale (NOAA, Meteor, GOES)
  /opt/torrebert/gsm/           → Outils GSM/Cellulaire
  /opt/torrebert/sigint/        → Analyse spectrale avancée
  /opt/torrebert/tools/         → GNU Radio, modules, utilitaires
  /opt/torrebert/scripts/       → Scripts de réception automatique
  /opt/torrebert/tle/           → Éléments orbitaux (TLE) — mis à jour quotidiennement
  /opt/torrebert/enregistrements/ → Archives des signaux capturés

COMMANDES RAPIDES :

  SATELLITES MÉTÉO :
    noaa_receive.sh NOAA-19 137100000 900     → Réception NOAA-19
    meteor_receive.sh METEOR-M2 137100000 900 → Réception Meteor-M2
    satdump-ui                                  → Interface SatDump
    noaa-apt input.wav -o output.png            → Décodage APT
    meteor_demod -B -o output.s input.wav       → Décodage Meteor

  ISS :
    iss_sstv_receive.sh                         → Réception SSTV ISS
    iss_aprs_receive.sh                         → Réception APRS ISS
    qsstv                                       → Décodage SSTV manuel

  AVION :
    readsb --device-type rtlsdr --interactive   → ADS-B live
    acarsdec -r 0 131.550 131.725              → ACARS VHF
    dumpvdl2 --rtlsdr 0                          → VDL Mode 2
    dumphfdl --soapysdr driver=rtlsdr ...       → HF Data Link
    JAERO                                        → Inmarsat Aero / ACARS sat

  IRIDIUM / INMARSAT :
    iridium_receive.sh                          → Réception Iridium
    iridium-extractor -D 4 input.wav | iridium-parser → Décodage Iridium
    JAERO                                       → Inmarsat Aero

  SDR GÉNÉRALISTES :
    gqrx                                        → Récepteur SDR généraliste
    sdrpp                                       → SDR++ (léger et puissant)
    sdrangel                                    → SDRangel (modes numériques)
    cubicsdr                                    → CubicSDR
    inspectrum file.wav                         → Analyse spectrale détaillée
    SigDigger                                   → Analyseur de protocoles
    urh                                         → Universal Radio Hacker

  SUIVI ORBITAL :
    gpredict                                    → Suivi orbital graphique
    predict                                     → Suivi orbital CLI
    /opt/torrebert/scripts/update_tle.sh        → Mise à jour manuelle TLE

FRÉQUENCES CLÉS (MHz) :
  ISS Voix/SSTV     : 145.800
  ISS APRS           : 145.825
  NOAA-15            : 137.620
  NOAA-18            : 137.9125
  NOAA-19            : 137.100
  Meteor-M2          : 137.100
  Meteor-M2-2        : 137.900
  GOES-16 HRIT       : 1694.1
  Iridium            : 1626.5625
  Inmarsat Aero      : 1537.47 (L-band)
  ADS-B              : 1090.0
  ACARS VHF          : 131.550, 131.725

MATÉRIEL RECOMMANDÉ (Amazon/AliExpress) :
  • RTL-SDR v4 (blog v4) — réception de base, bias-tee intégré
  • Nooelec Ham It Up v1.3 — downconverter HF (0.1-65 MHz → 125 MHz)
  • SPF5189Z LNA — amplificateur faible bruit 50-4000 MHz
  • HackRF One / Portapack H2 — transmission/réception 1 MHz - 6 GHz
  • LimeSDR Mini — SDR full-duplex, 10 MHz - 3.5 GHz
  • Airspy HF+ Discovery — HF/VHF haute dynamique
  • ADALM-PLUTO — SDR learning, 325-3800 MHz
  • Antenne QFH (Quadrifilar Helical) — satellites météo 137 MHz
  • Antenne Discone 25-1300 MHz — écoute généraliste
  • Parabole 90-120 cm + LNB 1.7 GHz — GOES/HRIT

ASTUCES :
  1. Utilisez toujours un LNA proche de l'antenne pour les satellites faibles
  2. Les downconverters (Ham It Up) permettent de recevoir le HF avec un RTL-SDR
  3. Pour l'ISS, vérifiez les passes sur https://heavens-above.com
  4. Les TLE sont mis à jour automatiquement tous les jours à 6h00
  5. Stockez les enregistrements bruts (WAV/IQ) avant décodage — on ne sait jamais

"Les étoiles ne se taisent jamais. Il faut savoir écouter."
  — Frères Judica-Cordiglia

===============================================================================
EOF

    chown -R "$SDR_USER:$SDR_USER" "$INSTALL_DIR"

    # Message final
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo -e "  ${GREEN}INSTALLATION TERMINÉE — TORRE BERT 2.0 EST PRÊTE${NC}"
    echo ""
    echo "  Station       : $STATION_NAME"
    echo "  Opérateur     : $CALLSIGN"
    echo "  Répertoire    : $INSTALL_DIR"
    echo "  Manuel        : $INSTALL_DIR/MANUEL_TORRE_BERT_2.0.txt"
    echo "  Log           : $LOG_FILE"
    echo ""
    echo -e "  ${YELLOW}ACTIONS REQUISES :${NC}"
    echo "  1. Redémarrer le système : sudo reboot"
    echo "  2. Reconnectez-vous et testez : rtl_test"
    echo "  3. Lisez le manuel : cat $INSTALL_DIR/MANUEL_TORRE_BERT_2.0.txt"
    echo ""
    echo -e "  ${CYAN}Bons écoutes, et que le ciel vous parle.${NC}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
#  POINT D'ENTRÉE
# ═══════════════════════════════════════════════════════════════════════════

main() {
    banner
    check_root

    log JUDICA "Démarrage de l'installation Torre Bert 2.0"
    log JUDICA "Date : $(date) | Utilisateur SDR : $SDR_USER"

    read -p "Appuyez sur Entrée pour commencer l'installation spatiale (Ctrl+C pour annuler)..."
    echo ""

    prepare_system
    install_sdr_stack
    install_gnuradio_spatial
    install_orbital_tracking
    install_satellite_decoders
    install_iss_tools
    install_iridium_inmarsat
    install_weather_satellites
    install_aviation
    install_sigint_advanced
    install_network_monitoring
    finalize
}

main "$@"
