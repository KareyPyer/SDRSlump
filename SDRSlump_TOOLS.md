# SDRSlump — Outils installés par `setup-sdr-toolkit.sh`

> Script d'installation automatisée (Bash, `set -e`, exécution root requise) qui construit un environnement SDR complet sur Ubuntu : réception, démodulation, décodage et rétro-ingénierie de signaux radio (RTL-SDR, HackRF, Airspy, LimeSDR, PlutoSDR, USRP...).

## Vue d'ensemble

| # | Section | Rôle |
|---|---------|------|
| 1 | Création utilisateur `sdr` | Isolation des permissions matérielles (groupes `dialout`, `plugdev`, `usbusers`) |
| 2 | Dépendances système | Toolchain de build + Python + audio |
| 3 | Pilotes matériels SDR | Accès bas niveau aux dongles/périphériques RF |
| 4 | GNU Radio | Chaîne de traitement du signal graphique |
| 5 | Venv Python SDR | Analyse RF / DSP / Scapy en environnement isolé |
| 6 | Démodulation & visualisation | Logiciels d'écoute et de décodage |
| 7 | Rétro-ingénierie protocoles | ADS-B, IoT, capteurs 433/868 MHz |
| 8 | udev & blacklist DVB | Libération du dongle RTL2832U du pilote TV natif |
| 9 | Droits & alias | Intégration `.bashrc`, script d'activation rapide |

---

## 1. Compte utilisateur dédié

- Utilisateur `sdr` créé (`useradd -m -s /bin/bash`), membre de `dialout`, `plugdev`, `usbusers`
- Répertoires : `/tmp/sdr-builds` (build), `/home/sdr/sdr_workspace` (espace de travail)

## 2. Dépendances système de base (`apt-get`)

**Build & CLI génériques**
`software-properties-common`, `ca-certificates`, `curl`, `wget`, `git`, `unzip`, `zip`, `tar`, `p7zip-full`, `build-essential`, `cmake`, `ninja-build`, `pkg-config`, `gcc`, `g++`, `clang`, `autoconf`, `automake`, `libtool`, `doxygen`

**Bibliothèques USB / système / crypto**
`libusb-1.0-0(-dev)`, `libudev-dev`, `libssl-dev`, `libffi-dev`, `libncurses5-dev`, `libncursesw5-dev`

**Python & calcul scientifique**
`python3`, `python3-pip`, `python3-venv`, `python3-dev`, `python3-setuptools`, `python3-wheel`, `python3-numpy`, `python3-scipy`, `python3-matplotlib`, `gfortran`

**DSP (traitement du signal)**
`libfftw3-dev`, `libliquid-dev`, `libvolk-bin`, `libvolk-dev`

**Audio**
`sox`, `pulseaudio-utils`, `pavucontrol`, `portaudio19-dev`, `libasound2-dev`

**Divers / confort**
`gqrx-sdr`, `gparted`, `htop`, `tree`, `jq`, `screen`, `tmux`, `cu`, `minicom`

## 3. Pilotes & bibliothèques d'accès SDR

PPA ajouté : `ppa:myriadrf/drivers` (best-effort)

| Matériel | Paquets |
|---|---|
| RTL-SDR | `rtl-sdr`, `librtlsdr-dev` |
| HackRF | `hackrf`, `libhackrf-dev` |
| Airspy / Airspy HF+ | `airspy`, `libairspy-dev`, `airspyhf`, `libairspyhf-dev` |
| LimeSDR | `limesuite`, `liblimesuite-dev`, `limesuite-udev` |
| USRP (Ettus) | `uhd-host`, `libuhd-dev` |
| PlutoSDR (ADALM) | `libiio-dev`, `libad9361-0` |
| Couche d'abstraction | `soapysdr-tools`, `libsoapysdr-dev` + modules `soapysdr-module-{rtlsdr,hackrf,airspy,limesuite,uhd,audio}` |

Optimisation DSP : `volk_profile` exécuté pour calibrer les instructions SIMD locales.

## 4. GNU Radio & modules OOT

`gnuradio`, `gnuradio-dev`, `gr-osmosdr`, `gr-hdlc`, `gr-radar`, `gr-satellites`
→ inclut `gnuradio-companion` (éditeur graphique de flowgraphs).

## 5. Environnement Python isolé (`/opt/sdr-venv`)

Venv créé via `python3 -m venv`, puis via pip :

`pyrtlsdr`, `scipy`, `numpy`, `matplotlib`, `pandas`, `jupyterlab`, `bokeh`, `plotly`, `pyqt5`, `pyserial`, `scapy`, `construct`, `pylibftdi`, `sigrok-cli`, `sounddevice`, `wave`, `pycryptodome`, `rich`

## 6. Démodulation, décodage & visualisation

**Paquets APT** (best-effort, `|| true`)
`multimon-ng`, `kalstrate`, `dsd-fme`, `sdrangel`, `dump1090-mutability`, `wireshark`, `tshark`, `sigrok`, `pulseview`, `inspectrum`

**Via le venv Python**
- `urh` (Universal Radio Hacker) — rétro-ingénierie de protocoles RF inconnus

**Compilé depuis les sources**
- `rtl_433` (clone GitHub `merbanan/rtl_433`, build CMake) — décodage domotique/capteurs 433/868 MHz

**Installé dynamiquement**
- `SDR++` (SDR-plus-plus) — le script récupère le dernier `.deb` Ubuntu amd64 via l'API GitHub Releases (`AlexandreRouxel/SDRplusplus`) et l'installe

## 7. Rétro-ingénierie de protocoles spécialisés

- `libcsdr-dev`, `csdr` (support CSDR / OpenWebRX)
- `dump1090` (clone GitHub `flightaware/dump1090`, compilé et copié dans `/usr/local/bin`) — décodage ADS-B (suivi avions, 1090 MHz)

Le script mentionne également la couverture de protocoles GSM, P25 et POCSAG via les outils déjà listés (`dsd-fme`, `multimon-ng`).

## 8. Règles udev & blacklist DVB

- Blacklist `/etc/modprobe.d/blacklist-rtlsdr.conf` : désactive les pilotes TV TNT natifs (`dvb_usb_rtl28xxu`, `rtl2830`, `rtl2832`, `rtl2832_sdr`, `dvb_usb_v2`, `dvb_core`) pour libérer les clés RTL2832U
- Règles udev `/etc/udev/rules.d/99-sdr-devices.rules` (mode `0666`, groupe `plugdev`) pour :
  - RTL-SDR Blog V3/V4 (R820T/R828D)
  - HackRF One / Jawbreaker
  - Airspy R2 / Mini / HF+
  - LimeSDR
  - PlutoSDR (ADALM-PLUTO)
  - FUNcube Dongle Pro / Pro+

## 9. Droits, alias & script d'activation

- Droits : venv en lecture pour tous, workspace appartenant à l'utilisateur `sdr`
- Alias ajoutés au `.bashrc` de `sdr` : `sdr-venv`, `test-rtlsdr` (`rtl_test -t`), `test-hackrf` (`hackrf_info`), `run-urh`, `run-sdrpp`
- Script global `/usr/local/bin/sdrslump-env` : active le venv et affiche un résumé des outils chargés

---

## Résumé des outils phares (issu du message final du script)

| Outil | Usage |
|---|---|
| `sdrpp` / `gqrx` / `sdrangel` | Waterfall, écoute FM/AM/SSB |
| `urh` | Rétro-ingénierie / analyse de protocoles RF inconnus |
| `rtl_433` | Décodage de 100+ protocoles domotiques (capteurs, météo, alarmes) |
| `inspectrum` | Analyse spectro-temporelle fine |
| `dump1090` | Suivi ADS-B (avions, 1090 MHz) |
| `multimon-ng` / `dsd-fme` | Décodage pagers (POCSAG) et radio numérique (DMR, P25) |
| `gnuradio-companion` | Création graphique de chaînes de traitement RX/TX |
| `JupyterLab` (+ `pyrtlsdr`, `scipy`, `matplotlib`) | Analyse du signal en Python |

## Notes

- Le script exige `sudo`/root et repose sur `set -e` (arrêt immédiat en cas d'erreur), sauf sur les blocs marqués `|| true` (tolérants aux échecs, ex. PPA, paquets optionnels, GNU Radio OOT).
- Après installation, un redémarrage est recommandé pour garantir le déchargement complet des pilotes DVB natifs et l'application des règles udev.
- Cible matérielle multi-vendor : RTL-SDR, HackRF, Airspy(HF+), LimeSDR, PlutoSDR, USRP, FUNcube.
