#!/bin/bash
###############################################################################
# Post-Installation SIGINT sur Ubuntu
# Cible : Ubuntu 22.04 LTS / 24.04 LTS (x86_64)
# Domaines : HF, VHF, UHF, Maritime, Aviation, Iridium, Inmarsat, GSM
# Auteur  : Généré pour projet radioamateur/SIGINT
# Usage   : sudo chmod +x install_sigint.sh && sudo ./install_sigint.sh
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/sigint_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Variables
INSTALL_DIR="/opt/sigint"
SDR_RULES_DIR="/etc/udev/rules.d"
USER_SDR="${SUDO_USER:-$USER}"

###############################################################################
# Fonctions utilitaires
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_err() {
    echo -e "${RED}[ERR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_err "Ce script doit être exécuté en root (sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -qE "Ubuntu" /etc/os-release; then
        log_warn "Distribution non-Ubuntu détectée. Le script est optimisé pour Ubuntu."
    fi
    log_info "Distribution : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
}

install_pkgs() {
    apt-get install -y "$@" || {
        log_err "Échec installation de : $*"
        return 1
    }
}

clone_or_pull() {
    local repo_url="$1"
    local dest_dir="$2"
    if [[ -d "$dest_dir/.git" ]]; then
        log_info "Mise à jour de $(basename "$dest_dir")..."
        git -C "$dest_dir" pull --ff-only
    else
        log_info "Clonage de $(basename "$dest_dir")..."
        git clone --depth 1 "$repo_url" "$dest_dir"
    fi
}

###############################################################################
# 1. Préparation système
###############################################################################

prepare_system() {
    log_info "=== ÉTAPE 1/10 : Préparation du système ==="

    dpkg --add-architecture i386 2>/dev/null || true

    apt-get update
    apt-get upgrade -y

    # Dépendances essentielles de compilation
    install_pkgs build-essential cmake git wget curl \
        libusb-1.0-0-dev libusb-1.0-0 libfftw3-dev libfftw3-bin \
        pkg-config autoconf automake libtool libncurses5-dev \
        libboost-all-dev python3-pip python3-dev python3-venv \
        python3-numpy python3-scipy python3-matplotlib \
        qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools \
        libqt5svg5-dev libqt5widgets5 libqt5gui5 libqt5network5-dev \
        libqt5serialport5-dev libqt5charts5-dev \
        libgl1-mesa-dev libglu1-mesa-dev \
        libssl-dev zlib1g-dev libcurl4-openssl-dev \
        libxml2-dev libsqlite3-dev \
        sox libsox-fmt-all \
        wireshark tshark \
        gqrx-sdr \
        libjpeg-dev libpng-dev \
        libairspy-dev libairspyhf-dev \
        libhackrf-dev librtlsdr-dev \
        libbladerf-dev liblimesuite-dev \
        libuhd-dev uhd-host \
        libosmosdr-dev \
        libsndfile1-dev libliquid-dev \
        libitpp-dev libpcap-dev \
        liborc-0.4-dev \
        doxygen graphviz \
        swig3.0 || swig \
        xterm gnome-terminal \
        htop iotop nethogs \
        nmap netcat-openbsd \
        tcpdump ngrep \
        aircrack-ng kismet \
        chromium-browser || google-chrome-stable || true

    # Python packages globaux utiles
    pip3 install --upgrade pip
    pip3 install pyserial requests flask numpy scipy matplotlib \
        pyusb construct bitstring crcmod \
        scapy pandas jupyter \
        2>/dev/null || log_warn "Certains paquets Python n'ont pas pu être installés"

    mkdir -p "$INSTALL_DIR"
    chown "$USER_SDR:$USER_SDR" "$INSTALL_DIR"

    log_ok "Système préparé"
}

###############################################################################
# 2. Drivers SDR et règles udev
###############################################################################

install_sdr_drivers() {
    log_info "=== ÉTAPE 2/10 : Drivers SDR et règles udev ==="

    # RTL-SDR
    log_info "Installation des outils RTL-SDR..."
    install_pkgs rtl-sdr librtlsdr0 librtlsdr-dev || true

    # Règles udev pour RTL-SDR
    if [[ ! -f "$SDR_RULES_DIR/rtl-sdr.rules" ]]; then
        curl -sL https://raw.githubusercontent.com/osmocom/rtl-sdr/master/rtl-sdr.rules \
            -o "$SDR_RULES_DIR/rtl-sdr.rules"
    fi

    # HackRF
    log_info "Installation des outils HackRF..."
    install_pkgs hackrf libhackrf0 libhackrf-dev || true

    # BladeRF
    log_info "Installation des outils BladeRF..."
    install_pkgs bladerf libbladerf2 libbladerf-dev bladerf-firmware-hosted || true

    # LimeSDR
    log_info "Installation des outils LimeSDR..."
    install_pkgs limesuite liblimesuite-dev limesuite-udev || true

    # Airspy
    log_info "Installation des outils Airspy..."
    install_pkgs airspy libairspy0 libairspy-dev airspyhf libairspyhf-dev || true

    # PlutoSDR (libiio)
    install_pkgs libiio-dev libiio0 iiotools || true

    # USRP / UHD
    log_info "Configuration UHD..."
    uhd_images_downloader || log_warn "Téléchargement des images UHD a échoué"

    # SoapySDR
    log_info "Installation de SoapySDR..."
    install_pkgs soapysdr-tools soapysdr-module-all || true

    # Rechargement des règles udev
    udevadm control --reload-rules
    udevadm trigger

    # Ajout de l'utilisateur au groupe plugdev
    usermod -aG plugdev "$USER_SDR" 2>/dev/null || true
    usermod -aG dialout "$USER_SDR" 2>/dev/null || true

    log_ok "Drivers SDR installés"
}

###############################################################################
# 3. GNU Radio
###############################################################################

install_gnuradio() {
    log_info "=== ÉTAPE 3/10 : GNU Radio ==="

    install_pkgs gnuradio gnuradio-dev || true

    # OOT modules courants
    install_pkgs gr-osmosdr gr-fcdproplus gr-iqbal || true

    # Gr-soapy (si disponible)
    install_pkgs gr-soapy 2>/dev/null || log_warn "gr-soapy non disponible dans les dépôts"

    log_ok "GNU Radio installé"
}

###############################################################################
# 4. Aviation (ADS-B, ACARS, VDL2, HFDL)
###############################################################################

install_aviation() {
    log_info "=== ÉTAPE 4/10 : Outils Aviation ==="

    local AVIA_DIR="$INSTALL_DIR/aviation"
    mkdir -p "$AVIA_DIR"

    # Dump1090 (Mutability ou readsb)
    log_info "Installation de readsb (ADS-B)..."
    clone_or_pull "https://github.com/wiedehopf/readsb.git" "$AVIA_DIR/readsb"
    cd "$AVIA_DIR/readsb"
    make BLADERF=NO RTLSDR=YES AIRCRAFT_HASH=yes
    cp readsb "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/readsb" /usr/local/bin/readsb 2>/dev/null || true

    # Dump978 (UAT)
    log_info "Installation de dump978..."
    clone_or_pull "https://github.com/flightaware/dump978.git" "$AVIA_DIR/dump978"
    cd "$AVIA_DIR/dump978"
    make
    cp dump978-fa "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/dump978-fa" /usr/local/bin/dump978-fa 2>/dev/null || true

    # ACARSdec (VHF ACARS)
    log_info "Installation de ACARSdec..."
    clone_or_pull "https://github.com/TLeconte/acarsdec.git" "$AVIA_DIR/acarsdec"
    cd "$AVIA_DIR/acarsdec"
    mkdir -p build && cd build
    cmake .. -Drtl=ON
    make
    cp acarsdec "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/acarsdec" /usr/local/bin/acarsdec 2>/dev/null || true

    # DumpVDL2 (VDL Mode 2)
    log_info "Installation de dumpvdl2..."
    clone_or_pull "https://github.com/szpajder/dumpvdl2.git" "$AVIA_DIR/dumpvdl2"
    cd "$AVIA_DIR/dumpvdl2"
    mkdir -p build && cd build
    cmake ..
    make
    cp dumpvdl2 "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/dumpvdl2" /usr/local/bin/dumpvdl2 2>/dev/null || true

    # DumpHFDL (HF Data Link)
    log_info "Installation de dumpHFDL..."
    clone_or_pull "https://github.com/szpajder/dumphfdl.git" "$AVIA_DIR/dumphfdl"
    cd "$AVIA_DIR/dumphfdl"
    mkdir -p build && cd build
    cmake ..
    make
    cp dumphfdl "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/dumphfdl" /usr/local/bin/dumphfdl 2>/dev/null || true

    # JAERO (Inmarsat Aero / ACARS sat)
    log_info "Installation de JAERO..."
    install_pkgs libqt5multimedia5-plugins libqt5serialport5-dev || true
    clone_or_pull "https://github.com/jontio/JAERO.git" "$AVIA_DIR/JAERO"
    cd "$AVIA_DIR/JAERO"
    # JAERO utilise qmake
    qmake JAERO.pro
    make
    cp JAERO "$AVIA_DIR/"
    ln -sf "$AVIA_DIR/JAERO" /usr/local/bin/JAERO 2>/dev/null || true

    # Acarsdeco2 (binaire précompilé si disponible)
    log_info "Téléchargement Acarsdeco2..."
    wget -q "https://github.com/TLeconte/acarsdeco2/releases/download/0.40/acarsdeco2" \
        -O "$AVIA_DIR/acarsdeco2" 2>/dev/null && chmod +x "$AVIA_DIR/acarsdeco2" || \
        log_warn "Acarsdeco2 non téléchargé"

    log_ok "Outils Aviation installés"
}

###############################################################################
# 5. Maritime (AIS)
###############################################################################

install_maritime() {
    log_info "=== ÉTAPE 5/10 : Outils Maritime (AIS) ==="

    local MAR_DIR="$INSTALL_DIR/maritime"
    mkdir -p "$MAR_DIR"

    # AISdeco2 / AISrecorder
    log_info "Téléchargement AISdeco2..."
    wget -q "https://github.com/aisdeco2/aisdeco2/releases/download/2.0/aisdeco2" \
        -O "$MAR_DIR/aisdeco2" 2>/dev/null && chmod +x "$MAR_DIR/aisdeco2" || \
        log_warn "AISdeco2 non téléchargé"

    # gr-ais (GNU Radio AIS)
    log_info "Installation de gr-ais..."
    clone_or_pull "https://github.com/bistromath/gr-ais.git" "$MAR_DIR/gr-ais"
    cd "$MAR_DIR/gr-ais"
    mkdir -p build && cd build
    cmake ..
    make
    make install
    ldconfig

    # rtl-ais (décodeur AIS léger pour RTL-SDR)
    log_info "Installation de rtl-ais..."
    clone_or_pull "https://github.com/dgiardini/rtl-ais.git" "$MAR_DIR/rtl-ais"
    cd "$MAR_DIR/rtl-ais"
    make
    cp rtl_ais "$MAR_DIR/"
    ln -sf "$MAR_DIR/rtl_ais" /usr/local/bin/rtl_ais 2>/dev/null || true

    # aisdispatcher (optionnel)
    log_info "Téléchargement AISDispatcher..."
    wget -q "https://www.aishub.net/downloads/aisdispatcher" \
        -O "$MAR_DIR/aisdispatcher" 2>/dev/null && chmod +x "$MAR_DIR/aisdispatcher" || \
        log_warn "AISDispatcher non téléchargé"

    log_ok "Outils Maritime installés"
}

###############################################################################
# 6. Satellites (Iridium, Inmarsat, NOAA, Meteor)
###############################################################################

install_satellites() {
    log_info "=== ÉTAPE 6/10 : Outils Satellites ==="

    local SAT_DIR="$INSTALL_DIR/satellites"
    mkdir -p "$SAT_DIR"

    # Gpredict (suivi orbital)
    log_info "Installation de Gpredict..."
    install_pkgs gpredict || true

    # gr-satellites (décodage satellites amateurs)
    log_info "Installation de gr-satellites..."
    clone_or_pull "https://github.com/daniestevez/gr-satellites.git" "$SAT_DIR/gr-satellites"
    cd "$SAT_DIR/gr-satellites"
    git checkout maint-3.10 2>/dev/null || git checkout main
    mkdir -p build && cd build
    cmake ..
    make
    make install
    ldconfig

    # Iridium Toolkit
    log_info "Installation de Iridium Toolkit..."
    clone_or_pull "https://github.com/muccc/iridium-toolkit.git" "$SAT_DIR/iridium-toolkit"
    cd "$SAT_DIR/iridium-toolkit"
    # Le toolkit est principalement Python, pas besoin de compilation
    chmod +x *.py
    ln -sf "$SAT_DIR/iridium-toolkit/iridium-parser.py" /usr/local/bin/iridium-parser 2>/dev/null || true
    ln -sf "$SAT_DIR/iridium-toolkit/iridium-extractor.py" /usr/local/bin/iridium-extractor 2>/dev/null || true

    # gr-iridium (GNU Radio Iridium)
    log_info "Installation de gr-iridium..."
    clone_or_pull "https://github.com/muccc/gr-iridium.git" "$SAT_DIR/gr-iridium"
    cd "$SAT_DIR/gr-iridium"
    mkdir -p build && cd build
    cmake ..
    make
    make install
    ldconfig

    # IridiumLive (visualisation)
    log_info "Installation de IridiumLive..."
    clone_or_pull "https://github.com/muccc/iridium-toolkit.git" "$SAT_DIR/iridiumlive" 2>/dev/null || true
    # IridiumLive est souvent intégré au toolkit

    # Inmarsat / STD-C
    log_info "Installation de inmarsat-c decoder..."
    clone_or_pull "https://github.com/cropinghigh/inmarsatc-parser.git" "$SAT_DIR/inmarsatc-parser" 2>/dev/null || \
        log_warn "inmarsatc-parser non disponible"

    # Inmarsat Aero déjà couvert par JAERO (section aviation)

    # SatDump (décodage météo et autres)
    log_info "Installation de SatDump..."
    clone_or_pull "https://github.com/SatDump/SatDump.git" "$SAT_DIR/SatDump"
    cd "$SAT_DIR/SatDump"
    mkdir -p build && cd build
    cmake .. -DBUILD_GUI=ON
    make -j$(nproc)
    make install
    ldconfig

    # NOAA-APT (décodage NOAA APT simple)
    log_info "Installation de noaa-apt..."
    clone_or_pull "https://github.com/martinber/noaa-apt.git" "$SAT_DIR/noaa-apt"
    cd "$SAT_DIR/noaa-apt"
    cargo build --release 2>/dev/null || log_warn "noaa-apt nécessite Rust, compilation ignorée"

    # MeteorDemod (Meteor M2)
    log_info "Installation de MeteorDemod..."
    clone_or_pull "https://github.com/Digitelektro/MeteorDemod.git" "$SAT_DIR/MeteorDemod"
    cd "$SAT_DIR/MeteorDemod"
    mkdir -p build && cd build
    cmake ..
    make
    cp meteor_demod "$SAT_DIR/"
    ln -sf "$SAT_DIR/meteor_demod" /usr/local/bin/meteor_demod 2>/dev/null || true

    # XRIT Decoder (GOES/HRIT)
    log_info "Installation de xrit-rx..."
    clone_or_pull "https://github.com/sam210723/xrit-rx.git" "$SAT_DIR/xrit-rx" 2>/dev/null || \
        log_warn "xrit-rx non disponible"

    log_ok "Outils Satellites installés"
}

###############################################################################
# 7. Modes numériques & Ham Radio
###############################################################################

install_hamradio() {
    log_info "=== ÉTAPE 7/10 : Modes numériques & Ham Radio ==="

    # Fldigi suite
    log_info "Installation de la suite Fldigi..."
    install_pkgs fldigi flrig flmsg flwrap flamp flnet fllog || true

    # WSJT-X
    log_info "Installation de WSJT-X..."
    install_pkgs wsjtx || true

    # Direwolf (TNC logiciel / APRS)
    log_info "Installation de Direwolf..."
    install_pkgs direwolf || true

    # Linpac (packet radio)
    install_pkgs linpac || true

    # Xastir (APRS)
    install_pkgs xastir || true

    # QSSTV (SSTV)
    install_pkgs qsstv || true

    # FreeDV
    install_pkgs freedv || true

    # CHIRP (programmation émetteurs)
    log_info "Installation de CHIRP..."
    pip3 install chirp 2>/dev/null || \
        wget -q "https://archive.chirp.danplanet.com/download/1.0/chirp" -O /usr/local/bin/chirp && chmod +x /usr/local/bin/chirp || \
        log_warn "CHIRP non installé"

    # CQRLog
    install_pkgs cqrlog || true

    # TQSL (LoTW)
    install_pkgs trustedqsl || true

    # Multimon-ng (décodage POCSAG, FLEX, etc.)
    log_info "Installation de multimon-ng..."
    clone_or_pull "https://github.com/EliasOenal/multimon-ng.git" "$INSTALL_DIR/multimon-ng"
    cd "$INSTALL_DIR/multimon-ng"
    mkdir -p build && cd build
    qmake ..
    make
    cp multimon-ng "$INSTALL_DIR/"
    ln -sf "$INSTALL_DIR/multimon-ng" /usr/local/bin/multimon-ng 2>/dev/null || true

    log_ok "Modes numériques installés"
}

###############################################################################
# 8. GSM / Cellulaire
###############################################################################

install_gsm() {
    log_info "=== ÉTAPE 8/10 : Outils GSM / Cellulaire ==="

    local GSM_DIR="$INSTALL_DIR/gsm"
    mkdir -p "$GSM_DIR"

    # gr-gsm
    log_info "Installation de gr-gsm..."
    install_pkgs gr-gsm 2>/dev/null || {
        log_warn "gr-gsm non dans les dépôts, compilation depuis les sources..."
        clone_or_pull "https://github.com/ptrkrysik/gr-gsm.git" "$GSM_DIR/gr-gsm"
        cd "$GSM_DIR/gr-gsm"
        mkdir -p build && cd build
        cmake ..
        make
        make install
        ldconfig
    }

    # IMSI-catcher
    log_info "Installation de IMSI-catcher..."
    clone_or_pull "https://github.com/Oros42/IMSI-catcher.git" "$GSM_DIR/IMSI-catcher"
    cd "$GSM_DIR/IMSI-catcher"
    pip3 install -r requirements.txt 2>/dev/null || true
    chmod +x *.py
    ln -sf "$GSM_DIR/IMSI-catcher/simple_IMSI-catcher.py" /usr/local/bin/imsi-catcher 2>/dev/null || true

    # Yate / YateBTS
    log_info "Installation de YateBTS..."
    install_pkgs yate yate-bts 2>/dev/null || log_warn "YateBTS non disponible dans les dépôts"

    # srsRAN (anciennement srsLTE)
    log_info "Installation de srsRAN 4G..."
    clone_or_pull "https://github.com/srsran/srsran_4g.git" "$GSM_DIR/srsran_4g"
    cd "$GSM_DIR/srsran_4g"
    mkdir -p build && cd build
    cmake ..
    make
    make install
    ldconfig
    srsran_install_configs.sh user 2>/dev/null || true

    # LTE-Cell-Scanner
    log_info "Installation de LTE-Cell-Scanner..."
    clone_or_pull "https://github.com/JiaoXianjun/LTE-Cell-Scanner.git" "$GSM_DIR/LTE-Cell-Scanner"
    cd "$GSM_DIR/LTE-Cell-Scanner"
    mkdir -p build && cd build
    cmake ..
    make
    cp CellSearch "$GSM_DIR/"
    ln -sf "$GSM_DIR/CellSearch" /usr/local/bin/CellSearch 2>/dev/null || true

    # Kalibrate-RTL
    log_info "Installation de kalibrate-rtl..."
    clone_or_pull "https://github.com/steve-m/kalibrate-rtl.git" "$GSM_DIR/kalibrate-rtl"
    cd "$GSM_DIR/kalibrate-rtl"
    ./bootstrap && ./configure && make
    cp src/kal "$GSM_DIR/"
    ln -sf "$GSM_DIR/kal" /usr/local/bin/kal-rtl 2>/dev/null || true

    log_ok "Outils GSM installés"
}

###############################################################################
# 9. Outils d'analyse spectrale et SIGINT
###############################################################################

install_sigint_tools() {
    log_info "=== ÉTAPE 9/10 : Outils d'analyse spectrale et SIGINT ==="

    local SIG_DIR="$INSTALL_DIR/sigint"
    mkdir -p "$SIG_DIR"

    # SDR++
    log_info "Installation de SDR++..."
    clone_or_pull "https://github.com/AlexandreRouma/SDRPlusPlus.git" "$SIG_DIR/SDRPlusPlus"
    cd "$SIG_DIR/SDRPlusPlus"
    mkdir -p build && cd build
    cmake .. -DOPT_BUILD_AIRSPYHF_SOURCE=ON \
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
    log_info "Installation de SDRangel..."
    install_pkgs sdrangel 2>/dev/null || {
        log_warn "SDRangel non dans les dépôts, compilation depuis les sources..."
        clone_or_pull "https://github.com/f4exb/sdrangel.git" "$SIG_DIR/sdrangel"
        cd "$SIG_DIR/sdrangel"
        mkdir -p build && cd build
        cmake ..
        make -j$(nproc)
        make install
    }

    # SDRTrunk
    log_info "Installation de SDRTrunk..."
    clone_or_pull "https://github.com/DSheirer/sdrtrunk.git" "$SIG_DIR/sdrtrunk"
    cd "$SIG_DIR/sdrtrunk"
    # SDRTrunk nécessite Gradle/Java
    install_pkgs default-jdk gradle || true
    gradle build 2>/dev/null || log_warn "Compilation SDRTrunk échouée (nécessite Java/Gradle)"

    # Universal Radio Hacker (URH)
    log_info "Installation de Universal Radio Hacker..."
    pip3 install urh || log_warn "URH non installé via pip"

    # Inspectrum (visualiseur de signaux)
    log_info "Installation de Inspectrum..."
    clone_or_pull "https://github.com/miek/inspectrum.git" "$SIG_DIR/inspectrum"
    cd "$SIG_DIR/inspectrum"
    mkdir -p build && cd build
    cmake ..
    make
    make install

    # SigDigger
    log_info "Installation de SigDigger..."
    clone_or_pull "https://github.com/BatchDrake/SigDigger.git" "$SIG_DIR/SigDigger"
    cd "$SIG_DIR/SigDigger"
    # SigDigger utilise qmake
    qmake SigDigger.pro
    make
    cp SigDigger "$SIG_DIR/"
    ln -sf "$SIG_DIR/SigDigger" /usr/local/bin/SigDigger 2>/dev/null || true

    # RFCrack / RFCat
    log_info "Installation de RFCat..."
    pip3 install rfcat || log_warn "RFCat non installé"

    # TempestSDR
    log_info "Installation de TempestSDR..."
    clone_or_pull "https://github.com/martinmarinov/TempestSDR.git" "$SIG_DIR/TempestSDR" 2>/dev/null || \
        log_warn "TempestSDR non disponible"

    # RFCrack
    clone_or_pull "https://github.com/cclabsInc/RFCrack.git" "$SIG_DIR/RFCrack" 2>/dev/null || \
        log_warn "RFCrack non disponible"

    # QSpectrumAnalyzer
    log_info "Installation de QSpectrumAnalyzer..."
    pip3 install qspectrumanalyzer || log_warn "QSpectrumAnalyzer non installé"

    # Baudline (analyseur spectral)
    log_info "Téléchargement de Baudline..."
    wget -q "https://www.baudline.com/baudline_1.08_linux_x86_64.tar.gz" \
        -O /tmp/baudline.tar.gz 2>/dev/null && \
        tar -xzf /tmp/baudline.tar.gz -C "$SIG_DIR/" && \
        ln -sf "$SIG_DIR/baudline_1.08_linux_x86_64/baudline" /usr/local/bin/baudline 2>/dev/null || \
        log_warn "Baudline non téléchargé (nécessite licence)"

    log_ok "Outils SIGINT installés"
}

###############################################################################
# 10. Outils réseau, Wi-Fi et finalisation
###############################################################################

install_network_wifi() {
    log_info "=== ÉTAPE 10/10 : Outils réseau, Wi-Fi et finalisation ==="

    # Wi-Fi
    install_pkgs kismet kismon sparrow-wifi 2>/dev/null || true

    # Bluetooth
    install_pkgs bluez blueman ubertooth 2>/dev/null || true

    # Ubertooth tools
    clone_or_pull "https://github.com/greatscottgadgets/ubertooth.git" "$INSTALL_DIR/ubertooth" 2>/dev/null || true

    # Sparrow-WiFi (si non installé via apt)
    pip3 install sparrowwifi 2>/dev/null || true

    # OpenWebRX (récepteur SDR web)
    log_info "Installation d'OpenWebRX..."
    clone_or_pull "https://github.com/jketterl/openwebrx.git" "$INSTALL_DIR/openwebrx"
    cd "$INSTALL_DIR/openwebrx"
    pip3 install -r requirements.txt 2>/dev/null || true

    # WebSDR / KiwiSDR clients (via navigateur, rien à installer)

    # Mise à jour ldconfig
    ldconfig

    # Création d'un résumé
    cat > "$INSTALL_DIR/README.txt" << 'EOF'
===============================================================================
ENVIRONNEMENT SIGINT - POST-INSTALLATION UBUNTU
===============================================================================

Répertoire d'installation : /opt/sigint/

STRUCTURE :
  /opt/sigint/aviation/    -> Outils aviation (ADS-B, ACARS, VDL2, HFDL, JAERO)
  /opt/sigint/maritime/    -> Outils maritime (AIS)
  /opt/sigint/satellites/  -> Outils satellites (Iridium, Inmarsat, NOAA, Meteor)
  /opt/sigint/gsm/         -> Outils GSM/Cellulaire (gr-gsm, srsRAN, IMSI-catcher)
  /opt/sigint/sigint/      -> Outils analyse spectrale (SDR++, URH, Inspectrum)

UTILISATEUR SDR : $USER_SDR
  Ajouté aux groupes : plugdev, dialout

LOG D'INSTALLATION : /var/log/sigint_install.log

COMMANDES UTILES :
  readsb --device-type rtlsdr --interactive          # ADS-B
  acarsdec -r 0 131.550 131.725                     # ACARS VHF
  dumpvdl2 --rtlsdr 0                                 # VDL Mode 2
  rtl_ais -p 0                                       # AIS Maritime
  iridium-extractor -D 4 /dev/stdin | iridium-parser  # Iridium
  grgsm_livemon -f 935.4M                             # GSM live monitor
  kal-rtl -s GSM900                                  # Calibration GSM
  multimon-ng -a POCSAG512 -f alpha ...              # POCSAG

===============================================================================
EOF

    chown -R "$USER_SDR:$USER_SDR" "$INSTALL_DIR"

    log_ok "Installation terminée !"
    log_info "Redémarrage recommandé pour appliquer les règles udev et groupes"
    log_info "Consultez $INSTALL_DIR/README.txt pour un résumé"
}

###############################################################################
# Menu principal
###############################################################################

main() {
    clear
    echo "==============================================================================="
    echo "  POST-INSTALLATION SIGINT - UBUNTU"
    echo "  HF | VHF | UHF | Maritime | Aviation | Iridium | Inmarsat | GSM"
    echo "==============================================================================="
    echo ""

    check_root
    check_ubuntu

    log_info "Début de l'installation à $(date)"
    log_info "Utilisateur SDR cible : $USER_SDR"
    log_info "Répertoire d'installation : $INSTALL_DIR"
    echo ""

    read -p "Appuyez sur Entrée pour commencer l'installation (Ctrl+C pour annuler)..."
    echo ""

    prepare_system
    install_sdr_drivers
    install_gnuradio
    install_aviation
    install_maritime
    install_satellites
    install_hamradio
    install_gsm
    install_sigint_tools
    install_network_wifi

    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}INSTALLATION TERMINÉE AVEC SUCCÈS${NC}"
    echo "==============================================================================="
    echo ""
    echo "Redémarrez votre système pour finaliser la configuration."
    echo "Puis reconnectez-vous et testez vos dongles SDR :"
    echo "  rtl_test        # Test RTL-SDR"
    echo "  hackrf_info     # Test HackRF"
    echo "  limeutil --find # Test LimeSDR"
    echo ""
    echo "Pour lancer GQRX : gqrx"
    echo "Pour lancer SDR++ : sdrpp"
    echo "Pour lire le résumé : cat /opt/sigint/README.txt"
    echo ""
}

main "$@"
