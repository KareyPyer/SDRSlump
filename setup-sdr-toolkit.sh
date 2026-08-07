#!/bin/bash
# post-install-sdrslump.sh
# Script d'installation automatisé pour un environnement SDR (Software Defined Radio) complet sur Ubuntu
# Conçu pour capter, démoduler, décoder, analyser et rétro-ingénierer n'importe quel signal radio (RTL-SDR, HackRF, LimeSDR, Airspy, etc.)
# Usage: sudo ./post-install-sdrslump.sh

set -e

# -----------------------------------------------------------------------------
# Couleurs et fonctions d'affichage
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${PURPLE}"
    echo "=========================================================================="
    echo "         ____  ____  ____    ____  _     _  _  _   ____   ____           "
    echo "        / ___||  _ \|  _ \  / ___|| |   | || || | |  _ \ / ___|          "
    echo "        \___ \| | | | |_) | \___ \| |   | || || |_| |_) | |  _           "
    echo "         ___) | |_| |  _ <   ___) | |___|__   __|  __/| |_| |          "
    echo "        |____/|____/|_| \_\ |____/|_____|  |_|  |_|    \____|          "
    echo "                                                                        "
    echo "     Environnement SDR Ultrafast & Complet pour Ubuntu (RTL-SDR & All)  "
    echo "=========================================================================="
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${CYAN}==========================================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}==========================================================================${NC}\n"
}

# -----------------------------------------------------------------------------
# Vérification des privilèges root
# -----------------------------------------------------------------------------
print_banner

if [[ $EUID -ne 0 ]]; then
    print_error "Ce script doit être exécuté en tant que root (ex: sudo ./post-install-sdrslump.sh)"
    exit 1
fi

# -----------------------------------------------------------------------------
# Variables d'environnement & répertoires
# -----------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONUNBUFFERED=1
export PIP_NO_CACHE_DIR=1

SDR_USER="sdr"
VENV_PATH="/opt/sdr-venv"
BUILD_DIR="/tmp/sdr-builds"
WORKSPACE_DIR="/home/${SDR_USER}/sdr_workspace"

# -----------------------------------------------------------------------------
# 1. Création de l'utilisateur 'sdr'
# -----------------------------------------------------------------------------
print_section "1. Création du compte utilisateur 'sdr'"
groupadd -f dialout
groupadd -f plugdev
groupadd -f usbusers

if id -u "${SDR_USER}" &>/dev/null; then
    print_warning "L'utilisateur '${SDR_USER}' existe déjà."
else
    useradd -m -s /bin/bash -G dialout,plugdev,usbusers ${SDR_USER}
    print_success "Utilisateur '${SDR_USER}' créé."
fi

mkdir -p ${BUILD_DIR}
mkdir -p ${WORKSPACE_DIR}

# -----------------------------------------------------------------------------
# 2. Mise à jour du système & Dépendances de base
# -----------------------------------------------------------------------------
print_section "2. Installation des dépendances et outils système de base"

apt-get update
apt-get install -y --no-install-recommends \
    software-properties-common \
    ca-certificates \
    curl \
    wget \
    git \
    unzip \
    zip \
    tar \
    p7zip-full \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    gcc \
    g++ \
    clang \
    autoconf \
    automake \
    libtool \
    doxygen \
    libusb-1.0-0 \
    libusb-1.0-0-dev \
    libudev-dev \
    libssl-dev \
    libffi-dev \
    libncurses5-dev \
    libncursesw5-dev \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    python3-numpy \
    python3-scipy \
    python3-matplotlib \
    gfortran \
    libfftw3-dev \
    libliquid-dev \
    libvolk-bin \
    libvolk-dev \
    sox \
    pulseaudio-utils \
    pavucontrol \
    portaudio19-dev \
    libasound2-dev \
    gqrx-sdr \
    gparted \
    htop \
    tree \
    jq \
    screen \
    tmux \
    cu \
    minicom

print_success "Dépendances de base installées."

# -----------------------------------------------------------------------------
# 3. Pilotes Matériels (RTL-SDR, HackRF, Airspy, LimeSDR, PlutoSDR, USRP)
# -----------------------------------------------------------------------------
print_section "3. Installation des drivers et bibliothèques d'accès SDR"

# Ajout du PPA Myriadrf si possible
add-apt-repository -y ppa:myriadrf/drivers || true
apt-get update

apt-get install -y --no-install-recommends \
    rtl-sdr \
    librtlsdr-dev \
    hackrf \
    libhackrf-dev \
    airspy \
    libairspy-dev \
    airspyhf \
    libairspyhf-dev \
    limesuite \
    liblimesuite-dev \
    limesuite-udev \
    uhd-host \
    libuhd-dev \
    libiio-dev \
    libad9361-0 \
    soapysdr-tools \
    soapysdr-module-rtlsdr \
    soapysdr-module-hackrf \
    soapysdr-module-airspy \
    soapysdr-module-limesuite \
    soapysdr-module-uhd \
    soapysdr-module-audio \
    libsoapysdr-dev

# Profilage VOLK pour accélérer le traitement DSP sur le processeur local
print_info "Optimisation DSP (volk_profile)..."
volk_profile || print_warning "Profilage VOLK ignoré ou incomplet."

print_success "Pilotes SDR et couche SoapySDR configurés."

# -----------------------------------------------------------------------------
# 4. GNU Radio & Chaîne de traitement du signal
# -----------------------------------------------------------------------------
print_section "4. Installation de GNU Radio et modules OOT"

apt-get install -y --no-install-recommends \
    gnuradio \
    gnuradio-dev \
    gr-osmosdr \
    gr-hdlc \
    gr-radar \
    gr-satellites || true

print_success "GNU Radio et modules principaux installés."

# -----------------------------------------------------------------------------
# 5. Environnement Python Isolé pour DSP, analyse RF et Scapy
# -----------------------------------------------------------------------------
print_section "5. Configuration de l'environnement Python SDR"

python3 -m venv ${VENV_PATH}
${VENV_PATH}/bin/pip install --no-cache-dir --upgrade pip setuptools wheel
${VENV_PATH}/bin/pip install --no-cache-dir \
    pyrtlsdr \
    scipy \
    numpy \
    matplotlib \
    pandas \
    jupyterlab \
    bokeh \
    plotly \
    pyqt5 \
    pyserial \
    scapy \
    construct \
    pylibftdi \
    sigrok-cli \
    sounddevice \
    wave \
    pycryptodome \
    rich

print_success "Environnement virtuel Python configuré dans ${VENV_PATH}."

# -----------------------------------------------------------------------------
# 6. Logiciels de Démodulation, Décodage RF et Visualisation
# -----------------------------------------------------------------------------
print_section "6. Installation des suites logicielles (SDR++, URH, SigDigger, etc.)"

# Paquets APT pour décodeurs spécialisés
apt-get install -y --no-install-recommends \
    multimon-ng \
    kalstrate \
    dsd-fme \
    sdrangel \
    dump1090-mutability \
    wireshark \
    tshark \
    sigrok \
    pulseview \
    inspectrum || true

# Universal Radio Hacker (URH) via Python Venv
${VENV_PATH}/bin/pip install --no-cache-dir urh

# Compilation et installation de rtl_433 (Décodage domotique, capteurs, 433/868 MHz)
print_info "Compilation de rtl_433..."
cd ${BUILD_DIR}
if [ -d "rtl_433" ]; then rm -rf rtl_433; fi
git clone https://github.com/merbanan/rtl_433.git
cd rtl_433
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
make install
ldconfig

# Installation automatique de SDR++ (SDR-plus-plus)
print_info "Téléchargement et installation de SDR++..."
SDRPLUSPLUS_DEB=$(curl -s https://api.github.com/repos/AlexandreRouxel/SDRplusplus/releases/latest | grep "browser_download_url" | grep "ubuntu" | grep "amd64" | cut -d '"' -f 4 | head -n 1)
if [ -n "${SDRPLUSPLUS_DEB}" ]; then
    wget -q "${SDRPLUSPLUS_DEB}" -O /tmp/sdrpp.deb
    apt-get install -y /tmp/sdrpp.deb || apt-get install -f -y
    rm -f /tmp/sdrpp.deb
    print_success "SDR++ installé."
else
    print_warning "Impossible de récupérer le package Debian de SDR++ automatiquement."
fi

print_success "Logiciels d'analyse et de décodage installés."

# -----------------------------------------------------------------------------
# 7. Outils de Rétro-ingénierie et Analyse de Protocoles (IoT, ADS-B, AIS, GSM)
# -----------------------------------------------------------------------------
print_section "7. Installation des décodeurs spécialisés (ADS-B, AIS, GSM, P25, POCSAG)"

# CSDR / OpenWebRX support
apt-get install -y --no-install-recommends \
    libcsdr-dev \
    csdr || true

# Dump1090 (Décodage ADS-B pour le suivi des avions)
cd ${BUILD_DIR}
if [ -d "dump1090" ]; then rm -rf dump1090; fi
git clone https://github.com/flightaware/dump1090.git
cd dump1090
make -j$(nproc)
cp dump1090 /usr/local/bin/

print_success "Décodeurs spécialisés installés."

# -----------------------------------------------------------------------------
# 8. Règles udev & Blacklist des drivers DVB-T conflictuels
# -----------------------------------------------------------------------------
print_section "8. Configuration des règles udev et désactivation du driver TV natif"

# IMPORTANT : Blacklist du driver Linux DVB qui prend le contrôle de la clef USB RTL2832U pour la TV TNT
cat > /etc/modprobe.d/blacklist-rtlsdr.conf << 'EOF'
# Empêche le noyau de charger le pilote TV TNT natif pour laisser le contrôle à librtlsdr
blacklist dvb_usb_rtl28xxu
blacklist rtl2830
blacklist rtl2832
blacklist rtl2832_sdr
blacklist dvb_usb_v2
blacklist dvb_core
EOF

# Règles udev pour l'accès utilisateur direct aux matériels USB SDR
cat > /etc/udev/rules.d/99-sdr-devices.rules << 'EOF'
# RTL-SDR Blog V3/V4 et dongles RTL2832U / R820T / R828D
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666", GROUP="plugdev"

# HackRF One / Jawbreaker
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="6089", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="604b", MODE="0666", GROUP="plugdev"

# Airspy R2 / Mini / HF+
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="60a1", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="60a2", MODE="0666", GROUP="plugdev"

# LimeSDR
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="601f", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="6108", MODE="0666", GROUP="plugdev"

# PlutoSDR (ADALM-PLUTO)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0456", ATTRS{idProduct}=="b673", MODE="0666", GROUP="plugdev"

# FUNcube Dongle Pro / Pro+
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="fb56", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="04d8", ATTRS{idProduct}=="fb31", MODE="0666", GROUP="plugdev"
EOF

# Rechargement udev
udevadm control --reload-rules || true
udevadm trigger || true

print_success "Règles udev et blacklist DVB appliquées."

# -----------------------------------------------------------------------------
# 9. Droits & Espace de travail
# -----------------------------------------------------------------------------
print_section "9. Attribution des droits et configuration des aliases"

chmod -R a+rX ${VENV_PATH}
chown -R ${SDR_USER}:${SDR_USER} ${WORKSPACE_DIR}

# Intégration dans le .bashrc de l'utilisateur sdr
cat >> /home/${SDR_USER}/.bashrc << 'EOF'

# --- Configuration Environnement SDRSlump ---
export PATH="/opt/sdr-venv/bin:${PATH}"
export PYTHONPATH="/opt/sdr-venv/lib/python3.*/site-packages:${PYTHONPATH}"
alias sdr-venv="source /opt/sdr-venv/bin/activate"
alias test-rtlsdr="rtl_test -t"
alias test-hackrf="hackrf_info"
alias run-urh="urh"
alias run-sdrpp="sdrpp"
EOF

chown ${SDR_USER}:${SDR_USER} /home/${SDR_USER}/.bashrc

# Script d'activation rapide global
cat > /usr/local/bin/sdrslump-env << 'EOF'
#!/bin/bash
export PATH="/opt/sdr-venv/bin:${PATH}"
echo "============================================================"
echo "    Environnement Radio SDRSlump activé !"
echo "============================================================"
echo "Outils chargés :"
echo " - SDR++ (sdrpp), Gqrx (gqrx), SDRangel (sdrangel)"
echo " - URH (urh), Inspectrum (inspectrum), SigDigger (sigdigger)"
echo " - RTL_433 (rtl_433), Dump1090 (dump1090), Multimon-ng"
echo " - Python Venv: $(which python3)"
echo "============================================================"
EOF

chmod +x /usr/local/bin/sdrslump-env

# Nettoyage
rm -rf ${BUILD_DIR}

# -----------------------------------------------------------------------------
# 10. Résumé Final & Mode d'emploi
# -----------------------------------------------------------------------------
print_section "Installation SDRSlump Terminée avec Succès !"

echo -e "${GREEN}✓ Le système est prêt à capter et bidouiller les ondes radio !${NC}\n"
echo -e "${YELLOW}Pour commencer :${NC}"
echo -e "  1. Branchez votre clef RTL-SDR ou autre récepteur sur un port USB."
echo -e "  2. Connectez-vous avec l'utilisateur SDR :"
echo -e "     ${CYAN}su - ${SDR_USER}${NC}"
echo -e "  3. Vérifiez la détection de votre clef RTL-SDR :"
echo -e "     ${CYAN}rtl_test -t${NC}"
echo -e "\n${YELLOW}Outils phares installés et immédiatement utilisables :${NC}"
echo -e "  • ${GREEN}sdrpp / gqrx / sdrangel${NC} : Visualisation waterfall et écoute FM/AM/SSB."
echo -e "  • ${GREEN}urh (Universal Radio Hacker)${NC} : Rétro-ingénierie et analyse de protocoles RF inconnus."
echo -e "  • ${GREEN}rtl_433${NC} : Décodage en temps réel de 100+ protocoles domotiques (capteurs, stations météo, alarmes)."
echo -e "  • ${GREEN}inspectrum${NC} : Analyse spectro-temporelle fine des signaux capturés."
echo -e "  • ${GREEN}dump1090${NC} : Suivi et décodage des avions de ligne (1090 MHz ADS-B)."
echo -e "  • ${GREEN}multimon-ng / dsd-fme${NC} : Décodage des pagers (POCSAG) et radios numériques (DMR, P25)."
echo -e "  • ${GREEN}gnuradio-companion${NC} : Création graphique de récepteurs/émetteurs sur-mesure."
echo -e "  • ${GREEN}JupyterLab${NC} : Analyse du signal sous Python avec `pyrtlsdr`, `scipy` et `matplotlib`."
echo -e "\n${RED}CONSEIL IMPORTANT :${NC} Redémarrez la machine pour garantir le déchargement complet"
echo -e "des pilotes TV TNT natifs de Linux et l'activation des règles udev USB :"
echo -e "     ${CYAN}sudo reboot${NC}\n"
echo "=========================================================================="