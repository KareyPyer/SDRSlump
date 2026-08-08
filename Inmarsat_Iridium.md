## Inmarsat (L-band, satellites géostationnaires ~1525-1559 MHz)

Deux flux distincts, deux logiciels historiques (utilisables avec `gqrx` ou `SDR#`/`SDRUno` de ta liste, en sortie audio USB) :

- **AERO / ACARS satellite** (1545,0-1545,2 MHz) → **JAERO** : démodule le MSK/OQPSK, décode les messages ACARS envoyés aux avions (position, météo, clairances). Fonctionne même avec un RTL-SDR, à condition que le tuner R820T/2 ne chauffe pas trop en L-band (un petit dissipateur aide).
- **STD-C / EGC** (1537-1542 MHz, maritime : SafetyNET, NAVAREA, météo) → **Scytale-C** (ou l'ancien Tekmanoid).
- Alternative moderne : **inmarsat-sniffer** (alphafox02), un binaire C autonome qui décode STD-C **et** AERO simultanément depuis une seule capture SDR (HackRF, Airspy, RTL-SDR, SDRplay...), sans GNU Radio.

Ces satellites sont géostationnaires : l'antenne se pointe une fois et reste fixe.

## Iridium (LEO, ~1616-1626,5 MHz)

Constellation en orbite basse (66 satellites) → signal intermittent, passages rapides, nécessite une couverture de ciel large plutôt qu'un pointage fixe.

- **gr-iridium** (module GNU Radio, binaire `iridium-extractor`) capture et démodule les bursts bruts.
- **iridium-toolkit** (Chaos Computer Club Munich, `iridium-parser.py`) parse ensuite ces trames (Ring Alert, position/heure, pagers, ACARS via Iridium, parfois voix avec AMBE/osmo-ir77).
- Alternative légère : **iridium-sniffer** (DragonOS), en C pur, plus adapté aux systèmes embarqués type Raspberry Pi.

Point important : la bande Iridium utile fait **~8,5 MHz**. Un RTL-SDR (bande passante ~2-3 MHz) ne capture qu'une tranche — il faut choisir entre bande simplex (alertes/pager) et bande duplex (voix/data, ACARS). Un **HackRF** (jusqu'à 20 MHz) ou un **Airspy R2/Mini** capte quasiment toute la bande en une seule passe, donc bien plus de bursts décodés.

## Hardware additionnel nécessaire

**Downconverter : généralement inutile ici.** Contrairement au HF (où un upconverter est nécessaire pour les SDR RTL/HackRF), le L-band (~1,5-1,6 GHz) est directement dans la plage native de la plupart des SDR (RTL-SDR jusqu'à 1,7 GHz, HackRF/Airspy/SDRplay bien au-delà). Un downconverter/LNB ne devient pertinent que si tu captes depuis une parabole en bande Ku (télédiffusion satellite), pas pour ces signaux de terminaux mobiles.

**Antenne**
- Inmarsat (géostationnaire, fixe) : antenne patch RHCP, souvent une antenne GPS active modifiée (le filtre GPS L1 d'origine est trop étroit et doit être retiré/remplacé).
- Iridium (LEO, passages au zénith) : antenne à couverture large, polarisation RHCP également — hélice (quadrifilaire, QFH), ou même patch large-bande. Certains fabricants (Taoglas) vendent des antennes dédiées Iridium.

**LNA (amplificateur faible bruit)** — quasi indispensable vu la faiblesse du signal satellite reçu au sol :
- Modules dédiés et filtrés existent spécifiquement pour cet usage : par ex. les **Nooelec SAWbird+ (GOES/Inmarsat)** et **SAWbird+ IRI (Iridium)**, ou un LNA générique type **LNA4ALL** placé au plus près de l'antenne.

**Filtre passe-bande**
- Indispensable pour rejeter le bruit hors-bande (GPS L1 à 1575 MHz, GSM, DME) qui sature facilement le préamplificateur en large bande.
- Idéalement intégré au LNA (les SAWbird ci-dessus embarquent déjà un filtre SAW calé sur la bonne bande).

**Bias-tee**
- Pour alimenter l'antenne active/LNA à distance via le même câble coax. Beaucoup de SDR (Airspy, RTL-SDR Blog V3, certains HackRF modifiés) en ont un intégré et activable en logiciel ; sinon un bias-tee externe fait l'affaire.

**Résumé chaîne matérielle typique**
```
Antenne (patch/hélice RHCP)
   → LNA filtré (SAWbird ou équivalent), alimenté par bias-tee
   → câble coax court (pertes faibles en L-band)
   → SDR (HackRF/Airspy conseillé pour Iridium, RTL-SDR suffisant pour Inmarsat)
   → gqrx/SDR#/SDRUno (audio USB) ou GNU Radio/iridium-extractor (IQ)
   → JAERO / Scytale-C / inmarsat-sniffer / iridium-toolkit
```
