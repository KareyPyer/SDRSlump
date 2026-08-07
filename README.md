# SDRSlump

**Environnement SDR (Software Defined Radio) complet et automatisé pour Ubuntu.**
Un seul script pour transformer une machine fraîchement installée en poste de capture, démodulation, décodage, analyse et rétro-ingénierie de signaux radio — RTL-SDR, HackRF, LimeSDR, Airspy, PlutoSDR, USRP.

![SDRSlump](SDRSlump.png)

## Objectif

`setup-sdr-toolkit.sh` (alias `post-install-sdrslump.sh`) automatise entièrement le montage d'un environnement SDR "prêt à l'emploi" : drivers matériels, GNU Radio, chaîne DSP Python isolée, logiciels de démodulation/décodage, décodeurs de protocoles spécialisés (ADS-B, domotique 433/868 MHz, POCSAG, DMR/P25...), règles udev et blacklist des pilotes DVB-T concurrents.

Pensé pour aller vite du "carte SDR neuve dans le port USB" au "waterfall à l'écran et signal décodé", sans réglages manuels à rallonge.

## Ce que le script installe

**1. Compte dédié**
Création d'un utilisateur `sdr` (groupes `dialout`, `plugdev`, `usbusers`) avec son propre espace de travail (`~/sdr_workspace`), pour isoler l'environnement radio du reste du système.

**2. Dépendances système**
Toolchain de compilation (build-essential, cmake, ninja, autoconf...), libs DSP (`libfftw3`, `libliquid`, `libvolk`), Python 3 + numpy/scipy/matplotlib, audio (`sox`, `portaudio`, `pulseaudio-utils`), et utilitaires courants (`tmux`, `screen`, `htop`, `jq`...).

**3. Pilotes matériels SDR**
`rtl-sdr`, `hackrf`, `airspy`/`airspyhf`, `limesuite`, `uhd-host` (USRP), `libiio`/`libad9361` (PlutoSDR), plus toute la couche SoapySDR avec ses modules. Profilage VOLK automatique pour optimiser le DSP sur le CPU local.

**4. GNU Radio**
`gnuradio` + `gnuradio-dev` et modules OOT (`gr-osmosdr`, `gr-hdlc`, `gr-radar`, `gr-satellites`).

**5. Environnement Python isolé**
Venv dédié (`/opt/sdr-venv`) avec `pyrtlsdr`, `scapy`, `construct`, `jupyterlab`, `bokeh`, `plotly`, `pycryptodome`, `sounddevice`, etc. — pour l'analyse de signal et le scripting sans polluer le Python système.

**6. Suites logicielles de démodulation / visualisation**
`gqrx`, `sdrangel`, `SDR++` (récupéré et installé automatiquement depuis les releases GitHub), `multimon-ng`, `dsd-fme`, Universal Radio Hacker (`urh`), `inspectrum`, `wireshark`/`tshark`, `sigrok`/`pulseview`.

**7. Rétro-ingénierie et décodage de protocoles**
Compilation depuis les sources de `rtl_433` (capteurs domotiques 433/868 MHz) et `dump1090` (ADS-B, suivi d'avions), plus `libcsdr`/`csdr`.

**8. udev & blacklist DVB-T**
Blacklist des modules noyau (`dvb_usb_rtl28xxu`, `rtl2832`, etc.) qui monopolisent les clés RTL2832U pour la TNT, et règles udev pour un accès utilisateur direct (sans root) aux périphériques USB : RTL-SDR Blog V3/V4, HackRF One/Jawbreaker, Airspy R2/Mini/HF+, LimeSDR, PlutoSDR, FUNcube Dongle Pro/Pro+.

**9. Confort d'utilisation**
Alias shell (`sdr-venv`, `test-rtlsdr`, `test-hackrf`, `run-urh`, `run-sdrpp`) et script global `sdrslump-env` pour activer rapidement l'environnement et lister les outils disponibles.

## Prérequis

- Ubuntu (testé pour une installation "post-install" propre)
- Accès root / `sudo`
- Connexion Internet (paquets APT, clonage GitHub, téléchargement du `.deb` SDR++)

## Installation

```bash
git clone https://github.com/KareyPyer/SDRSlump.git
cd SDRSlump
chmod +x setup-sdr-toolkit.sh
sudo ./setup-sdr-toolkit.sh
```

À la fin de l'installation, **redémarrez la machine** pour garantir le déchargement complet des pilotes TV TNT natifs et l'activation des règles udev :

```bash
sudo reboot
```

## Premiers pas

```bash
# Passer sur le compte dédié
su - sdr

# Vérifier la détection de la clé RTL-SDR
rtl_test -t

# Activer l'environnement Python SDR
sdr-venv

# Lister les outils installés
sdrslump-env
```

## Outils phares une fois installés

| Outil | Usage |
|---|---|
| `sdrpp` / `gqrx` / `sdrangel` | Waterfall, écoute FM/AM/SSB |
| `urh` (Universal Radio Hacker) | Rétro-ingénierie de protocoles RF inconnus |
| `rtl_433` | Décodage temps réel de 100+ protocoles domotiques |
| `inspectrum` | Analyse spectro-temporelle fine des captures |
| `dump1090` | Décodage ADS-B, suivi d'avions (1090 MHz) |
| `multimon-ng` / `dsd-fme` | Pagers (POCSAG), radio numérique (DMR, P25) |
| `gnuradio-companion` | Construction graphique de récepteurs/émetteurs sur-mesure |
| JupyterLab | Analyse de signal en Python (`pyrtlsdr`, `scipy`, `matplotlib`) |

## Matériel supporté (règles udev incluses)

- RTL-SDR Blog V3 / V4 (RTL2832U + R820T/R828D)
- HackRF One / Jawbreaker
- Airspy R2 / Mini / HF+
- LimeSDR
- PlutoSDR (ADALM-PLUTO)
- FUNcube Dongle Pro / Pro+

## Avertissement

Ce script installe des outils de réception et d'analyse radio à des fins d'expérimentation, d'apprentissage et de rétro-ingénierie. L'écoute et le décodage de certaines bandes de fréquences sont soumis à réglementation selon les pays. À l'utilisateur de vérifier la légalité de ses usages.

## Licence

Non spécifiée pour le moment.
