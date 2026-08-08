#!/bin/bash
###############################################################################
#  TORRE BERT 2.0 — Installation du Dashboard Web
#  Déploie un serveur Flask + interface temps réel pour la station SIGINT
#  Service systemd inclus — démarre automatiquement au boot
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[TB-DASH]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }

INSTALL_DIR="/opt/torrebert/dashboard"
SERVICE_NAME="torrebert-dashboard"
USER_SDR="${SUDO_USER:-$USER}"
PORT=8080

# ═══════════════════════════════════════════════════════════════════════════
#  1. PRÉPARATION
# ═══════════════════════════════════════════════════════════════════════════

log "Installation du Dashboard Torre Bert 2.0"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Exécutez avec sudo${NC}"
    exit 1
fi

apt-get update
apt-get install -y python3 python3-pip python3-venv python3-flask \
    python3-requests python3-numpy python3-ephem \
    libjs-bootstrap5 || true

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/static"
mkdir -p "$INSTALL_DIR/templates"
mkdir -p "$INSTALL_DIR/data"

# ═══════════════════════════════════════════════════════════════════════════
#  2. APPLICATION FLASK
# ═══════════════════════════════════════════════════════════════════════════

cat > "$INSTALL_DIR/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Torre Bert 2.0 — Dashboard Web SIGINT
Serveur Flask avec WebSocket-like polling pour données temps réel
"""

import os
import json
import time
import random
import math
import threading
import subprocess
from datetime import datetime, timezone
from flask import Flask, render_template, jsonify

app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# ─── Données simulées / réelles ───
class StationData:
    def __init__(self):
        self.satellites = [
            {"name": "ISS", "type": "iss", "freq": 145.800, "active": True,
             "elevation": 34.2, "azimuth": 128.5, "next_pass": "01:23 UTC",
             "signal_db": -42},
            {"name": "NOAA-19", "type": "noaa", "freq": 137.100, "active": True,
             "elevation": 18.7, "azimuth": 245.3, "next_pass": "En cours",
             "signal_db": -55},
            {"name": "Meteor-M2-2", "type": "meteor", "freq": 137.900, "active": False,
             "elevation": -12.0, "azimuth": 310.1, "next_pass": "01:13 UTC",
             "signal_db": -999},
            {"name": "GOES-16", "type": "goes", "freq": 1694.100, "active": False,
             "elevation": 52.0, "azimuth": 220.0, "next_pass": "Fixe géo",
             "signal_db": -68},
            {"name": "Iridium 97", "type": "iridium", "freq": 1626.5625, "active": False,
             "elevation": 8.3, "azimuth": 15.2, "next_pass": "00:47 UTC",
             "signal_db": -78},
            {"name": "Iridium 98", "type": "iridium", "freq": 1626.5625, "active": False,
             "elevation": 5.1, "azimuth": 340.7, "next_pass": "02:15 UTC",
             "signal_db": -82},
            {"name": "NOAA-18", "type": "noaa", "freq": 137.9125, "active": False,
             "elevation": -5.2, "azimuth": 90.4, "next_pass": "03:42 UTC",
             "signal_db": -999},
        ]
        self.sdr_devices = [
            {"name": "RTL-SDR v4", "id": "rtl0", "status": "online", "freq": 137.100,
             "gain": 42, "temp_c": 38, "sample_rate": 2048000},
            {"name": "HackRF One", "id": "hackrf0", "status": "online", "freq": 1626.562,
             "gain": 16, "temp_c": 45, "sample_rate": 20000000},
            {"name": "LimeSDR Mini", "id": "lime0", "status": "online", "freq": 145.800,
             "gain": 30, "temp_c": 52, "sample_rate": 10000000},
            {"name": "PlutoSDR", "id": "pluto0", "status": "offline", "freq": 0,
             "gain": 0, "temp_c": 0, "sample_rate": 0},
        ]
        self.logs = [
            {"time": "01:01:12", "msg": "ISS en vue — élévation 34° — signal SSTV détecté", "level": "highlight"},
            {"time": "01:00:45", "msg": "TLE mis à jour — 15 constellations", "level": ""},
            {"time": "00:58:22", "msg": "NOAA-19 — début décode APT — SNR 18 dB", "level": "warn"},
            {"time": "00:55:01", "msg": "ADS-B — 24 avions trackés — max FL410", "level": ""},
            {"time": "00:52:18", "msg": "HackRF calibré — PPM 0.3", "level": ""},
        ]
        self.spectrum = []
        self.lock = threading.Lock()
        self._update_thread = threading.Thread(target=self._background_update, daemon=True)
        self._update_thread.start()

    def _background_update(self):
        """Met à jour les données en arrière-plan (simulation / lecture SDR réel)"""
        while True:
            with self.lock:
                # Animation satellites
                for sat in self.satellites:
                    if sat["active"]:
                        sat["elevation"] += random.uniform(-0.5, 0.8)
                        sat["azimuth"] += random.uniform(-1, 1.5)
                        sat["signal_db"] += random.randint(-3, 2)
                        sat["signal_db"] = max(-90, min(-30, sat["signal_db"]))
                        if sat["elevation"] < 0:
                            sat["active"] = False
                            sat["signal_db"] = -999
                    else:
                        sat["elevation"] += random.uniform(-0.3, 0.3)

                # Spectre RF
                self.spectrum = []
                for i in range(128):
                    val = random.randint(5, 25)
                    if i < 10: val = random.randint(30, 70)      # NOAA
                    if 55 < i < 62: val = random.randint(25, 55) # ISS/Meteor
                    if i > 115: val = random.randint(20, 50)     # Iridium
                    self.spectrum.append(val)

                # Températures SDR
                for sdr in self.sdr_devices:
                    if sdr["status"] == "online":
                        sdr["temp_c"] += random.randint(-1, 2)
                        sdr["temp_c"] = max(25, min(75, sdr["temp_c"]))

            time.sleep(1.5)

    def get_state(self):
        with self.lock:
            return {
                "satellites": list(self.satellites),
                "sdr_devices": list(self.sdr_devices),
                "logs": list(self.logs[-20:]),
                "spectrum": list(self.spectrum),
                "utc": datetime.now(timezone.utc).strftime("%H:%M:%S"),
                "local": datetime.now().strftime("%H:%M:%S"),
                "lat": 45.07,
                "lon": 7.69,
            }

    def add_log(self, msg, level=""):
        with self.lock:
            self.logs.append({
                "time": datetime.now().strftime("%H:%M:%S"),
                "msg": msg,
                "level": level
            })

    def tune_sdr(self, sdr_id, freq_mhz):
        with self.lock:
            for sdr in self.sdr_devices:
                if sdr["id"] == sdr_id and sdr["status"] == "online":
                    sdr["freq"] = freq_mhz
                    self.add_log(f"{sdr['name']} accordé sur {freq_mhz} MHz", "highlight")
                    return True
        return False

    def start_reception(self, target):
        targets = {
            "noaa": ("rtl0", 137.100, "Démarrage réception NOAA APT"),
            "meteor": ("rtl0", 137.900, "Démarrage réception Meteor M2-2"),
            "iss": ("lime0", 145.800, "Capture SSTV ISS en cours"),
            "iridium": ("hackrf0", 1626.5625, "Scan Iridium démarré"),
            "goes": ("hackrf0", 1694.100, "Réception GOES-16 HRIT"),
        }
        if target in targets:
            sdr_id, freq, msg = targets[target]
            self.tune_sdr(sdr_id, freq)
            self.add_log(msg, "highlight")
            # Ici on pourrait lancer vraiment : subprocess.Popen([...])
            return True
        return False

station = StationData()

# ─── Routes Flask ───

@app.route("/")
def index():
    return render_template("dashboard.html")

@app.route("/api/state")
def api_state():
    return jsonify(station.get_state())

@app.route("/api/tune/<sdr_id>/<float:freq>")
def api_tune(sdr_id, freq):
    ok = station.tune_sdr(sdr_id, freq)
    return jsonify({"success": ok, "sdr": sdr_id, "freq": freq})

@app.route("/api/receive/<target>")
def api_receive(target):
    ok = station.start_reception(target)
    return jsonify({"success": ok, "target": target})

@app.route("/api/update-tle")
def api_update_tle():
    # Lance le script de mise à jour TLE en arrière-plan
    try:
        subprocess.Popen(
            ["/opt/torrebert/scripts/update_tle.sh"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        station.add_log("Mise à jour TLE lancée", "highlight")
        return jsonify({"success": True, "message": "TLE update started"})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})

@app.route("/api/sdr/scan")
def api_sdr_scan():
    """Détecte les SDR connectés (rtl_test, hackrf_info, etc.)"""
    devices = []
    try:
        r = subprocess.run(["rtl_test", "-t"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0 or "Found" in r.stderr:
            devices.append({"type": "rtl-sdr", "status": "detected", "detail": r.stderr.strip()[:100]})
    except:
        pass
    try:
        r = subprocess.run(["hackrf_info"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            devices.append({"type": "hackrf", "status": "detected", "detail": "HackRF One trouvé"})
    except:
        pass
    try:
        r = subprocess.run(["LimeUtil", "--find"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and "LimeSDR" in r.stdout:
            devices.append({"type": "limesdr", "status": "detected", "detail": r.stdout.strip()[:100]})
    except:
        pass
    return jsonify({"devices": devices})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False, threaded=True)
PYEOF

chmod +x "$INSTALL_DIR/app.py"

# ═══════════════════════════════════════════════════════════════════════════
#  3. TEMPLATE HTML (le dashboard complet)
# ═══════════════════════════════════════════════════════════════════════════

cat > "$INSTALL_DIR/templates/dashboard.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Torre Bert 2.0 — Dashboard</title>
<style>
:root {
  --bg-dark: #0a0e17;
  --bg-panel: #111827;
  --bg-card: #1a2332;
  --border: #1f2937;
  --cyan: #00d4ff;
  --green: #10b981;
  --amber: #f59e0b;
  --red: #ef4444;
  --purple: #a855f7;
  --text: #e5e7eb;
  --text-dim: #6b7280;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg-dark); color: var(--text);
  font-family: 'JetBrains Mono', 'SF Mono', 'Courier New', monospace;
  font-size: 14px;
}
.tb-container { padding: 16px; max-width: 1400px; margin: 0 auto; }
.tb-header {
  display: flex; justify-content: space-between; align-items: center;
  border-bottom: 1px solid var(--border); padding-bottom: 12px; margin-bottom: 16px;
  flex-wrap: wrap; gap: 12px;
}
.tb-title { font-size: 1.4rem; font-weight: 700; color: var(--cyan); letter-spacing: 2px; }
.tb-subtitle { font-size: 0.75rem; color: var(--text-dim); margin-top: 2px; }
.tb-clocks { display: flex; gap: 24px; font-size: 0.85rem; }
.tb-clock { text-align: center; }
.tb-clock-label { font-size: 0.65rem; color: var(--text-dim); text-transform: uppercase; }
.tb-clock-value { font-weight: 700; color: var(--green); font-size: 1.1rem; }

.tb-grid { display: grid; grid-template-columns: 2fr 1fr 1fr; gap: 12px; }
@media (max-width: 1100px) { .tb-grid { grid-template-columns: 1fr 1fr; } }
@media (max-width: 700px) { .tb-grid { grid-template-columns: 1fr; } }

.tb-panel {
  background: var(--bg-panel); border: 1px solid var(--border);
  border-radius: 8px; padding: 14px;
}
.tb-panel-header {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 10px;
}
.tb-panel-title {
  font-size: 0.85rem; font-weight: 700; text-transform: uppercase;
  letter-spacing: 1px; color: var(--cyan);
}
.tb-panel-badge {
  font-size: 0.65rem; padding: 2px 8px; border-radius: 4px;
  background: var(--bg-card); color: var(--text-dim);
}

/* Sky Map */
.sky-map {
  position: relative; height: 320px;
  background: radial-gradient(ellipse at center, #0f172a 0%, #020617 100%);
  border-radius: 6px; overflow: hidden;
}
.sky-horizon {
  position: absolute; bottom: 0; left: 0; right: 0; height: 40%;
  background: linear-gradient(to top, rgba(6,182,212,0.08), transparent);
  border-top: 1px dashed rgba(0,212,255,0.15);
}
.sky-sat {
  position: absolute; width: 10px; height: 10px; border-radius: 50%;
  cursor: pointer; transition: transform 0.2s;
}
.sky-sat:hover { transform: scale(1.5); }
.sky-sat.iss { background: var(--green); box-shadow: 0 0 8px var(--green); }
.sky-sat.noaa { background: var(--cyan); box-shadow: 0 0 6px var(--cyan); }
.sky-sat.meteor { background: var(--amber); box-shadow: 0 0 6px var(--amber); }
.sky-sat.goes { background: var(--purple); box-shadow: 0 0 6px var(--purple); }
.sky-sat.iridium { background: var(--red); box-shadow: 0 0 6px var(--red); }
.sky-label {
  position: absolute; font-size: 0.6rem; color: var(--text-dim);
  white-space: nowrap; pointer-events: none;
}

/* Frequency Table */
.freq-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 6px 8px; border-radius: 4px; margin-bottom: 4px;
  font-size: 0.78rem; cursor: pointer; transition: background 0.15s;
}
.freq-row:hover { background: var(--bg-card); }
.freq-name { font-weight: 600; }
.freq-mhz { font-family: monospace; color: var(--cyan); }
.freq-status {
  font-size: 0.6rem; padding: 1px 6px; border-radius: 3px;
  text-transform: uppercase;
}
.freq-status.active { background: rgba(16,185,129,0.15); color: var(--green); }
.freq-status.upcoming { background: rgba(245,158,11,0.15); color: var(--amber); }
.freq-status.idle { background: rgba(107,114,128,0.15); color: var(--text-dim); }

/* SDR Status */
.sdr-item {
  display: flex; align-items: center; gap: 10px;
  padding: 8px; border-radius: 6px; background: var(--bg-card);
  margin-bottom: 6px;
}
.sdr-icon {
  width: 32px; height: 32px; border-radius: 6px;
  display: flex; align-items: center; justify-content: center;
  font-size: 0.7rem; font-weight: 700;
}
.sdr-icon.online {
  background: rgba(16,185,129,0.15); color: var(--green);
  border: 1px solid rgba(16,185,129,0.3);
}
.sdr-icon.offline {
  background: rgba(239,68,68,0.15); color: var(--red);
  border: 1px solid rgba(239,68,68,0.3);
}
.sdr-info { flex: 1; }
.sdr-name { font-size: 0.8rem; font-weight: 600; }
.sdr-detail { font-size: 0.65rem; color: var(--text-dim); }
.sdr-freq { font-family: monospace; font-size: 0.75rem; color: var(--cyan); }

/* Activity Log */
.log-entry {
  font-size: 0.72rem; padding: 4px 0;
  border-bottom: 1px solid var(--border); display: flex; gap: 8px;
}
.log-time { color: var(--text-dim); font-family: monospace; min-width: 60px; }
.log-msg { color: var(--text); }
.log-msg.highlight { color: var(--green); }
.log-msg.warn { color: var(--amber); }

/* Quick Controls */
.ctrl-btn {
  width: 100%; padding: 10px; margin-bottom: 8px;
  border: 1px solid var(--border); background: var(--bg-card);
  color: var(--text); border-radius: 6px; font-family: inherit;
  font-size: 0.8rem; cursor: pointer; transition: all 0.15s;
  text-align: left; display: flex; align-items: center; gap: 10px;
}
.ctrl-btn:hover { border-color: var(--cyan); background: rgba(0,212,255,0.05); }
.ctrl-btn:active { transform: scale(0.98); }
.ctrl-btn .dot { width: 8px; height: 8px; border-radius: 50%; }
.ctrl-btn .dot.green { background: var(--green); box-shadow: 0 0 6px var(--green); }
.ctrl-btn .dot.amber { background: var(--amber); box-shadow: 0 0 6px var(--amber); }
.ctrl-btn .dot.red { background: var(--red); box-shadow: 0 0 6px var(--red); }

/* Spectrum */
.spectrum {
  height: 60px; background: var(--bg-dark); border-radius: 4px;
  position: relative; overflow: hidden;
}
.spectrum-bars {
  display: flex; align-items: flex-end; height: 100%; gap: 1px; padding: 0 4px;
}
.spec-bar {
  flex: 1;
  background: linear-gradient(to top, var(--green), var(--cyan));
  border-radius: 1px 1px 0 0; opacity: 0.7; transition: height 0.2s;
}

/* Scope */
.scope {
  height: 100px; background: var(--bg-dark); border-radius: 4px;
  position: relative; overflow: hidden;
}
.scope-grid {
  position: absolute; inset: 0;
  background-image:
    linear-gradient(rgba(0,212,255,0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgba(0,212,255,0.05) 1px, transparent 1px);
  background-size: 20px 20px;
}
.scope-line svg { width: 100%; height: 100%; }

/* Connection status */
.conn-status {
  position: fixed; top: 8px; right: 16px;
  font-size: 0.65rem; padding: 3px 10px; border-radius: 12px;
  background: var(--bg-card); border: 1px solid var(--border);
  z-index: 100;
}
.conn-status.connected { color: var(--green); border-color: var(--green); }
.conn-status.disconnected { color: var(--red); border-color: var(--red); }
</style>
</head>
<body>

<div class="conn-status connected" id="conn-status">● Connecté</div>

<div class="tb-container">
  <div class="tb-header">
    <div>
      <div class="tb-title">◈ TORRE BERT 2.0</div>
      <div class="tb-subtitle">Station d'Écoute Spatiale — Frères Judica-Cordiglia · 2026</div>
    </div>
    <div class="tb-clocks">
      <div class="tb-clock">
        <div class="tb-clock-label">UTC</div>
        <div class="tb-clock-value" id="utc-clock">--:--:--</div>
      </div>
      <div class="tb-clock">
        <div class="tb-clock-label">Local</div>
        <div class="tb-clock-value" id="local-clock">--:--:--</div>
      </div>
      <div class="tb-clock">
        <div class="tb-clock-label">LAT / LON</div>
        <div class="tb-clock-value" style="font-size:0.75rem" id="coords">45.07°N / 7.69°E</div>
      </div>
    </div>
  </div>

  <div class="tb-grid">
    <!-- COLONNE 1 : SKY MAP + SPECTRUM -->
    <div>
      <div class="tb-panel">
        <div class="tb-panel-header">
          <span class="tb-panel-title">◉ Carte du Ciel — Satellites Visibles</span>
          <span class="tb-panel-badge" id="sat-count">0 visibles</span>
        </div>
        <div class="sky-map" id="sky-map">
          <div class="sky-horizon"></div>
        </div>
        <div style="margin-top:8px; display:flex; gap:12px; flex-wrap:wrap; font-size:0.65rem;">
          <span><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--green);margin-right:4px;"></span>ISS</span>
          <span><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--cyan);margin-right:4px;"></span>NOAA</span>
          <span><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--amber);margin-right:4px;"></span>Meteor</span>
          <span><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--purple);margin-right:4px;"></span>GOES</span>
          <span><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--red);margin-right:4px;"></span>Iridium</span>
        </div>
      </div>

      <div class="tb-panel" style="margin-top:12px;">
        <div class="tb-panel-header">
          <span class="tb-panel-title">⌇ Spectre RF — 137-1700 MHz</span>
          <span class="tb-panel-badge">Live</span>
        </div>
        <div class="spectrum" id="spectrum">
          <div class="spectrum-bars" id="spec-bars"></div>
        </div>
        <div style="display:flex; justify-content:space-between; margin-top:6px; font-size:0.6rem; color:var(--text-dim);">
          <span>137 MHz</span><span>500 MHz</span><span>1000 MHz</span><span>1626 MHz</span><span>1700 MHz</span>
        </div>
      </div>
    </div>

    <!-- COLONNE 2 : FRÉQUENCES + CONTRÔLES -->
    <div>
      <div class="tb-panel">
        <div class="tb-panel-header">
          <span class="tb-panel-title">◫ Fréquences Actives</span>
          <span class="tb-panel-badge" id="freq-badge">0 actives</span>
        </div>
        <div id="freq-list"></div>
      </div>

      <div class="tb-panel" style="margin-top:12px;">
        <div class="tb-panel-header">
          <span class="tb-panel-title">▶ Contrôles Rapides</span>
        </div>
        <button class="ctrl-btn" onclick="startRx('noaa')">
          <span class="dot green"></span><span>▶ Démarrer réception NOAA</span>
        </button>
        <button class="ctrl-btn" onclick="startRx('meteor')">
          <span class="dot amber"></span><span>▶ Démarrer réception Meteor</span>
        </button>
        <button class="ctrl-btn" onclick="startRx('iss')">
          <span class="dot green"></span><span>▶ Capturer SSTV ISS</span>
        </button>
        <button class="ctrl-btn" onclick="startRx('iridium')">
          <span class="dot red"></span><span>▶ Scanner Iridium</span>
        </button>
        <button class="ctrl-btn" onclick="updateTLE()">
          <span class="dot amber"></span><span>↻ Mettre à jour les TLE</span>
        </button>
        <button class="ctrl-btn" onclick="scanSDR()">
          <span class="dot green"></span><span>⟲ Scanner matériel SDR</span>
        </button>
      </div>
    </div>

    <!-- COLONNE 3 : SDR + LOGS + SCOPE -->
    <div>
      <div class="tb-panel">
        <div class="tb-panel-header">
          <span class="tb-panel-title">◈ Matériel SDR</span>
          <span class="tb-panel-badge" id="sdr-badge">0/0 online</span>
        </div>
        <div id="sdr-list"></div>
      </div>

      <div class="tb-panel" style="margin-top:12px;">
        <div class="tb-panel-header">
          <span class="tb-panel-title">◊ Journal d'Activité</span>
          <span class="tb-panel-badge">Live</span>
        </div>
        <div id="activity-log" style="max-height: 200px; overflow-y: auto;"></div>
      </div>

      <div class="tb-panel" style="margin-top:12px;">
        <div class="tb-panel-header">
          <span class="tb-panel-title">◡ Signal Scope</span>
          <span class="tb-panel-badge" id="scope-freq">137.100 MHz</span>
        </div>
        <div class="scope">
          <div class="scope-grid"></div>
          <div class="scope-line">
            <svg viewBox="0 0 400 100" preserveAspectRatio="none">
              <polyline fill="none" stroke="#00d4ff" stroke-width="1.5" points="" id="scope-poly"/>
            </svg>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
// ─── Horloges ───
function updateClocks() {
  const now = new Date();
  document.getElementById('utc-clock').textContent = now.toISOString().substr(11, 8);
  document.getElementById('local-clock').textContent = now.toLocaleTimeString('fr-FR', {hour12: false});
}
setInterval(updateClocks, 1000);
updateClocks();

// ─── Données globales ───
let stationData = {};
let lastData = null;

// ─── Récupération API ───
async function fetchState() {
  try {
    const res = await fetch('/api/state');
    const data = await res.json();
    stationData = data;
    renderAll();
    document.getElementById('conn-status').textContent = '● Connecté';
    document.getElementById('conn-status').className = 'conn-status connected';
  } catch (e) {
    document.getElementById('conn-status').textContent = '● Déconnecté';
    document.getElementById('conn-status').className = 'conn-status disconnected';
  }
}
setInterval(fetchState, 1500);
fetchState();

// ─── Rendu complet ───
function renderAll() {
  if (!stationData.satellites) return;
  renderSky();
  renderSpectrum();
  renderFrequencies();
  renderSDR();
  renderLogs();
  renderScope();
  document.getElementById('coords').textContent = (stationData.lat||45.07).toFixed(2) + '°N / ' + (stationData.lon||7.69).toFixed(2) + '°E';
}

// ─── Carte du ciel ───
function renderSky() {
  const map = document.getElementById('sky-map');
  map.querySelectorAll('.sky-sat, .sky-label').forEach(el => el.remove());
  let visible = 0;
  stationData.satellites.forEach(sat => {
    // Projection simple : élévation -> Y (haut), azimuth -> X
    const y = Math.max(5, Math.min(85, 85 - (sat.elevation / 90) * 80));
    const x = Math.max(5, Math.min(95, (sat.azimuth / 360) * 90 + 5));
    if (sat.elevation > 0) visible++;

    const el = document.createElement('div');
    el.className = 'sky-sat ' + sat.type;
    el.style.left = x + '%';
    el.style.top = y + '%';
    el.title = sat.name + '\nÉlévation: ' + sat.elevation.toFixed(1) + '°\nAzimut: ' + sat.azimuth.toFixed(1) + '°\nSignal: ' + (sat.signal_db > -900 ? sat.signal_db + ' dB' : 'N/A');
    map.appendChild(el);

    const lbl = document.createElement('div');
    lbl.className = 'sky-label';
    lbl.style.left = (x + 1.5) + '%';
    lbl.style.top = (y - 3) + '%';
    lbl.textContent = sat.name;
    map.appendChild(lbl);
  });
  document.getElementById('sat-count').textContent = visible + ' visibles';
}

// ─── Spectre ───
function renderSpectrum() {
  const container = document.getElementById('spec-bars');
  if (!stationData.spectrum || container.children.length === 0) {
    container.innerHTML = '';
    for (let i = 0; i < 128; i++) {
      const bar = document.createElement('div');
      bar.className = 'spec-bar';
      bar.style.height = '5%';
      container.appendChild(bar);
    }
  }
  const bars = container.querySelectorAll('.spec-bar');
  stationData.spectrum.forEach((val, i) => {
    if (bars[i]) bars[i].style.height = val + '%';
  });
}

// ─── Fréquences ───
function renderFrequencies() {
  const list = document.getElementById('freq-list');
  const freqs = [
    {name: 'ISS Voix/SSTV', freq: 145.800, status: 'En vue', cls: 'active'},
    {name: 'NOAA-19 APT', freq: 137.100, status: 'Décode', cls: 'active'},
    {name: 'Meteor-M2-2', freq: 137.900, status: '+12 min', cls: 'upcoming'},
    {name: 'Iridium', freq: 1626.5625, status: 'Veille', cls: 'idle'},
    {name: 'Inmarsat Aero', freq: 1537.470, status: 'Veille', cls: 'idle'},
    {name: 'ADS-B', freq: 1090.000, status: '24 tr/min', cls: 'active'},
    {name: 'GOES-16 HRIT', freq: 1694.100, status: '+45 min', cls: 'upcoming'},
  ];
  // Mise à jour depuis données serveur si dispo
  if (stationData.satellites) {
    freqs[0].status = stationData.satellites[0].active ? 'En vue · ' + stationData.satellites[0].elevation.toFixed(0) + '°' : 'Hors vue';
    freqs[0].cls = stationData.satellites[0].active ? 'active' : 'idle';
    freqs[1].status = stationData.satellites[1].active ? 'Décode · SNR ' + stationData.satellites[1].signal_db + 'dB' : 'Hors vue';
    freqs[1].cls = stationData.satellites[1].active ? 'active' : 'idle';
  }
  list.innerHTML = freqs.map(f => `
    <div class="freq-row" onclick="tuneTo(${f.freq})">
      <span class="freq-name">${f.name}</span>
      <span class="freq-mhz">${f.freq.toFixed(3)}</span>
      <span class="freq-status ${f.cls}">${f.status}</span>
    </div>
  `).join('');
  const activeCount = freqs.filter(f => f.cls === 'active').length;
  document.getElementById('freq-badge').textContent = activeCount + ' actives';
}

// ─── SDR ───
function renderSDR() {
  const list = document.getElementById('sdr-list');
  if (!stationData.sdr_devices) return;
  let online = 0;
  list.innerHTML = stationData.sdr_devices.map(sdr => {
    if (sdr.status === 'online') online++;
    return `
      <div class="sdr-item">
        <div class="sdr-icon ${sdr.status}">${sdr.name.charAt(0)}</div>
        <div class="sdr-info">
          <div class="sdr-name">${sdr.name}</div>
          <div class="sdr-detail">${sdr.status === 'online' ? 'Gain ' + sdr.gain + ' dB · Temp ' + sdr.temp_c + '°C · ' + (sdr.sample_rate/1e6).toFixed(1) + ' MS/s' : sdr.status}</div>
        </div>
        <div class="sdr-freq">${sdr.freq > 0 ? sdr.freq.toFixed(3) : '--.---'}</div>
      </div>
    `;
  }).join('');
  document.getElementById('sdr-badge').textContent = online + '/' + stationData.sdr_devices.length + ' online';
}

// ─── Logs ───
function renderLogs() {
  const container = document.getElementById('activity-log');
  if (!stationData.logs) return;
  container.innerHTML = stationData.logs.slice().reverse().map(l => `
    <div class="log-entry">
      <span class="log-time">${l.time}</span>
      <span class="log-msg ${l.level}">${l.msg}</span>
    </div>
  `).join('');
}

// ─── Scope ───
function renderScope() {
  const svg = document.getElementById('scope-poly');
  const points = [];
  const t = Date.now() * 0.002;
  for (let i = 0; i <= 400; i += 2) {
    const y = 50 + Math.sin(i * 0.05 + t) * 20 + Math.sin(i * 0.13 + t * 1.3) * 10 + (Math.random() - 0.5) * 8;
    points.push(`${i},${Math.max(5, Math.min(95, y))}`);
  }
  svg.setAttribute('points', points.join(' '));
  requestAnimationFrame(renderScope);
}

// ─── Actions ───
function tuneTo(freq) {
  document.getElementById('scope-freq').textContent = freq.toFixed(3) + ' MHz';
  fetch('/api/tune/rtl0/' + freq).catch(()=>{});
}
function startRx(target) {
  fetch('/api/receive/' + target).catch(()=>{});
}
function updateTLE() {
  fetch('/api/update-tle').catch(()=>{});
}
function scanSDR() {
  fetch('/api/sdr/scan').then(r => r.json()).then(d => {
    console.log('SDR scan:', d);
  }).catch(()=>{});
}
</script>
</body>
</html>
HTMLEOF

# ═══════════════════════════════════════════════════════════════════════════
#  4. SERVICE SYSTEMD
# ═══════════════════════════════════════════════════════════════════════════

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Torre Bert 2.0 — Dashboard SIGINT
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

# ═══════════════════════════════════════════════════════════════════════════
#  5. FINALISATION
# ═══════════════════════════════════════════════════════════════════════════

chown -R "$USER_SDR:$USER_SDR" "$INSTALL_DIR"

systemctl start "$SERVICE_NAME"

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "  ${GREEN}DASHBOARD TORRE BERT 2.0 INSTALLÉ${NC}"
echo ""
echo "  📍 Répertoire     : $INSTALL_DIR"
echo "  🌐 URL Dashboard   : http://$IP:$PORT"
echo "  🌐 Localhost       : http://localhost:$PORT"
echo "  🔧 Service systemd : $SERVICE_NAME"
echo ""
echo "  Commandes utiles :"
echo "    sudo systemctl status $SERVICE_NAME"
echo "    sudo systemctl restart $SERVICE_NAME"
echo "    sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "  Le dashboard est accessible depuis n'importe quel appareil"
echo "  sur le réseau local (tablette, téléphone, autre PC)."
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
