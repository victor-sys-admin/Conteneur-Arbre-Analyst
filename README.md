# Arbre Analyst 3.1.0 — exécution en conteneur (macOS)

[Arbre Analyst](https://www.arbre-analyst.com/) est un logiciel **Windows 32 bits**
(Python 3.8 + Tkinter gelé, moteur **XFTA** pour l'analyse d'arbres de défaillance).
Ce dépôt l'empaquette dans un conteneur Linux : l'application est exécutée sous **Wine**,
et son interface graphique est affichée sur macOS via **XQuartz**.

> **⚠️ Setup conçu et testé pour macOS uniquement**
>
> Toute la couche **affichage + orchestration** est spécifique à macOS : XQuartz (serveur X
> de l'hôte), la machine podman (VM Linux), la passerelle `host.docker.internal` et le
> script `run.sh` (préférences XQuartz, `xhost`, `open -a XQuartz`, mapping des UID de
> volume). Seule l'**image** (le `Dockerfile`) est portable ; un usage sous Linux ou Windows
> imposerait de réécrire le branchement de l'affichage (X11 natif, VcXsrv…) et le montage
> des volumes.

## Sommaire

- [Environnement testé](#environnement-testé)
- [Arborescence du dépôt](#arborescence-du-dépôt)
- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Commandes (`run.sh`)](#commandes-runsh)
- [Persistance des analyses](#persistance-des-analyses)
- [Raccourcis clavier / souris](#raccourcis-clavier--souris)
- [Architecture](#architecture)
- [Dépannage](#dépannage)
- [Décisions techniques & problèmes résolus](#décisions-techniques--problèmes-résolus)
- [Licences](#licences)

## Environnement testé

Validé de bout en bout (build, GUI, calcul XFTA, clic droit, persistance, polices, arrêt
propre) sur la configuration suivante :

| Composant             | Version testée                                             |
| --------------------- | ---------------------------------------------------------- |
| macOS                 | **15.7.7** (Sequoia, build 24G720)                         |
| CPU / architecture    | **Intel Core i7-8850H — x86_64**                           |
| podman                | **5.8.3** (machine `applehv`, 6 CPU, 11 Gio RAM, 60 Gio)   |
| compose *(optionnel)* | docker-compose **5.3.0** (fournisseur de `podman compose`) |
| XQuartz               | **2.8.5**                                                  |
| Wine *(dans l'image)* | **8.0** (Debian bookworm)                                  |

> **Apple Silicon (M1/M2/M3…) : non testé.** L'exécutable et Wine sont en **x86**. Sur un
> Mac ARM, le conteneur `amd64` et Wine `i386` s'exécuteraient sous émulation (lent, voire
> instable). Ce setup vise un **Mac Intel**.

## Arborescence du dépôt

```
abre-analyst/
├── app/                Application Arbre Analyst V3.1.0 (.exe, moteur XFTA, convert.exe, libs)
├── Dockerfile          Image Debian + Wine WoW64 (32+64 bits) + préfixe Wine préinitialisé
├── entrypoint.sh       Point d'entrée du conteneur : modes run / test / shell
├── fonts.reg           Réglages de police Wine (lissage + redirection vers polices lissées)
├── run.sh              Script d'orchestration (build / test / xquartz / up / shell / down)
├── docker-compose.yml  Service équivalent pour `podman compose up`
├── analyses/           Analyses sauvegardées — partagé avec « Mes documents » de l'appli
├── out/                Captures d'écran produites par `./run.sh test`
└── README.md
```

## Prérequis

1. **Mac Intel (x86_64)** sous macOS récent (testé sur 15.7).
2. **podman** avec une machine démarrée :
   ```bash
   brew install podman
   podman machine init      # première fois : crée la VM Linux (~60 Gio)
   podman machine start
   ```
3. **XQuartz** (serveur X pour l'affichage de la fenêtre) :
   ```bash
   brew install --cask xquartz
   ```
   Après une **première installation** de XQuartz, fermer puis rouvrir la session macOS
   (ou redémarrer) afin qu'il s'enregistre. `run.sh` active ensuite automatiquement
   l'écoute réseau et `xhost`.

> Aucune autre installation n'est nécessaire (Wine, Python, XFTA… sont **dans l'image**).

## Démarrage rapide

```bash
./run.sh build      # 1. Construire l'image (première fois, quelques minutes)
./run.sh test       # 2. (Optionnel) Vérifier sans écran → capture dans out/
./run.sh up         # 3. Lancer l'application (la fenêtre s'ouvre via XQuartz)
```

`./run.sh up` configure XQuartz automatiquement (écoute TCP + `xhost +` le temps de la
session), monte le dossier des analyses, puis démarre le conteneur avec
`DISPLAY=host.docker.internal:0`. **Ctrl-C** dans ce terminal — ou la fermeture de la
fenêtre de l'application — arrête et supprime le conteneur.

## Commandes (`run.sh`)

| Commande           | Effet                                                                        |
| ------------------ | ---------------------------------------------------------------------------- |
| `./run.sh build`   | Construit l'image `localhost/arbre-analyst:3.1.0`.                           |
| `./run.sh up`      | Configure XQuartz puis lance la GUI. Ctrl-C arrête proprement le conteneur.  |
| `./run.sh test`    | Lance l'app en headless (Xvfb) et exporte une capture dans `out/`.           |
| `./run.sh xquartz` | (Re)configure XQuartz seul (écoute réseau + `xhost`).                        |
| `./run.sh shell`   | Ouvre un shell dans le conteneur (débogage).                                 |
| `./run.sh down`    | Arrête et supprime les conteneurs.                                           |

### Alternative : `podman compose`

Une fois XQuartz configuré (`./run.sh xquartz`) :

```bash
podman compose up          # ou : DISPLAY_TARGET=host.docker.internal:0 podman compose up
```

Le fichier `docker-compose.yml` monte lui aussi `./analyses`. `run.sh up` reste toutefois
recommandé : il gère la configuration de XQuartz et l'arrêt propre au Ctrl-C.

## Persistance des analyses

Le conteneur est **éphémère** (`--rm`) : tout ce qui est écrit *dans* le conteneur est perdu
à l'arrêt. Pour conserver les fichiers, le dossier **`analyses/`** du dépôt est monté dans
le conteneur et relié à « **Mes documents** » de Wine.

- Dans Arbre Analyst : **Fichier → Enregistrer** dans *Mes documents* (dossier par défaut).
- Le fichier `.opsa` apparaît aussitôt côté Mac dans **`abre-analyst/analyses/`**.
- Pour rouvrir : **Fichier → Ouvrir → Mes documents**.

> Chaîne du montage : `./analyses` (Mac) ↔ `/data` (conteneur) ↔ *Mes documents* de Wine.
> Le dossier reste aussi accessible via le lecteur **`Z:\data`** dans les boîtes de dialogue.

## Raccourcis clavier / souris

Arbre Analyst est une application **Windows** : elle utilise les raccourcis Windows, et
XQuartz **ne traduit pas** les raccourcis macOS (⌘). Correspondances sur un Mac portable :

| Action                          | Sur Mac (trackpad + clavier)                     |
| ------------------------------- | ------------------------------------------------ |
| Clic droit / menu contextuel    | **Clic à deux doigts** (émis comme bouton 3)     |
| Copier / Couper / Coller        | **Ctrl + C / Ctrl + X / Ctrl + V** (*pas* ⌘)     |
| Annuler / Rétablir              | **Ctrl + Z / Ctrl + Y**                          |
| Supprimer un élément            | **Fn + ⌫** (équivaut à la touche `Delete`)       |
| Retour arrière (édition texte)  | **⌫** seule                                      |

Vérifié avec `xev` : le clic à deux doigts arrive bien en `button 3` ; `⌫` seule produit
`BackSpace`, `⌘+⌫` produit `Meta+BackSpace` (ignoré par l'appli), et **`Fn+⌫` produit
`Delete`** — le raccourci attendu.

> **Option — faire agir ⌘ comme Ctrl** (pour retrouver ⌘C/⌘X/⌘V) : possible via un remap
> `xmodmap` (Command → Control). Délicat cependant, car XQuartz capture lui-même ⌘C/⌘X/⌘V
> pour son propre presse-papier ; il faut donc aussi désactiver ces équivalents-clavier de
> XQuartz. Non activé par défaut.

## Architecture

- **Wine WoW64 (win64).** La GUI `Arbre Analyst.exe` est un exécutable PE32 (32 bits), mais
  le moteur de calcul **XFTA** (`app/externe/win32/xfta/xftar.exe`) est un PE32+ **64 bits**.
  Le préfixe Wine est donc en `win64` (comme un Windows 64 bits) afin d'exécuter les deux ;
  le Dockerfile active l'architecture `i386` et installe `wine32` **et** `wine64`.
- **Affichage.** Le conteneur ne rend aucun écran : il envoie le protocole X11 au serveur X
  de l'hôte. `host.docker.internal` (→ `192.168.127.254`) est la passerelle podman vers le
  Mac, où XQuartz écoute sur le port TCP 6000 (`DISPLAY :0`).
- **stdio.** Le Python gelé exige des handles standard *valides* : sa sortie n'est jamais
  redirigée vers un fichier ou `/dev/null` (sinon `WinError 6`). En mode `test`, le journal
  est capturé via un `tee` (pipe).
- **Arrêt propre.** L'application GUI ignore SIGINT/SIGTERM. `run.sh up` la lance en détaché,
  l'attend via un `wait` bash interruptible, et la supprime avec `podman rm -f -t 0`
  (SIGKILL immédiat) sur Ctrl-C ou fermeture de la fenêtre.

## Dépannage

| Symptôme                          | Cause / solution                                                                                                              |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Rien ne s'affiche à l'`up`        | XQuartz pas prêt : relancer `./run.sh xquartz`, ou activer XQuartz → Préférences → Sécurité → « Autoriser les connexions des clients réseau ». |
| `cannot open display`             | `xhost +` non appliqué, ou XQuartz pas relancé après un changement de préférence.                                             |
| Fenêtre partielle en `test`       | Normal en headless (capture prise pendant le rendu). Sous XQuartz la fenêtre est complète (quartz-wm gère l'affichage).       |
| `no space left on device` au build | La VM podman est pleine (chaque image ≈ 3 Go). Libérer avec `podman image prune -f`.                                         |

## Décisions techniques & problèmes résolus

Les points suivants ont été rencontrés puis corrigés lors de la containerisation. Ils sont
documentés pour expliquer les choix d'implémentation et éviter toute régression lors d'une
modification du `Dockerfile`, de `entrypoint.sh` ou de `run.sh`.

### 1. Build interrompu — `exit status 143` à l'init du préfixe Wine

**Symptôme.** L'étape `RUN` d'initialisation du préfixe Wine (Xvfb + `wineboot`) échouait
avec `Terminated` puis `exit status 143` (SIGTERM), alors que Wine venait d'afficher
`configuration has been updated`.

**Cause.** Le script arrêtait le Xvfb temporaire avec `pkill -f 'Xvfb :0'`. L'option `-f`
compare la **ligne de commande entière** : le shell exécutant le `RUN` contenait lui-même
la chaîne « Xvfb :0 », si bien que `pkill` se terminait lui-même.

**Solution.** Arrêter Xvfb par son **PID** plutôt que par motif :

```sh
Xvfb :0 ... & XVFB_PID=$!
...
kill "$XVFB_PID" 2>/dev/null || true
```

### 2. Application qui ne démarre pas — `WinError 6 Invalid handle`

**Symptôme.**

```
Fatal Python error: init_sys_streams: can't initialize sys standard streams
OSError: [WinError 6] Invalid handle
```

L'application ne démarrait pas lorsque sa sortie était redirigée vers un fichier ou
`/dev/null`.

**Cause.** Arbre Analyst est un **Python 3.8 gelé, sous-système Windows GUI (sans console)**.
À l'initialisation, l'interpréteur crée `sys.stdout`/`stderr` à partir des handles standard.
Sous Wine, une redirection vers un fichier ou `/dev/null` fournit un handle jugé invalide.

| stdio du process              | Résultat        |
| ----------------------------- | --------------- |
| hérité (pipe / tty)           | démarre ✅       |
| `> fichier.log` ou `/dev/null`| `WinError 6` ❌ |

**Solution.** Ne jamais rediriger la sortie de l'application vers un fichier ou `/dev/null`.
Mode `run` : `exec wine "$APP"` (sortie héritée du conteneur). Mode `test` : capture du
journal via un pipe (`wine "$APP" 2>&1 | tee log`).

### 3. Fenêtre à moitié rendue dans la capture headless

**Symptôme.** La première capture de `./run.sh test` ne montrait que le coin supérieur
gauche de la fenêtre, bien que `xwininfo` annonçât une fenêtre complète.

**Cause.** Le Xvfb de test n'avait **aucun gestionnaire de fenêtres** : la fenêtre Tk
n'était ni mappée ni redimensionnée à sa taille finale, et la capture partait trop tôt.

**Solution.** Ajout de `matchbox-window-manager` (léger) démarré avant l'application, plus
un délai de stabilisation avant la capture. En usage réel via XQuartz, `quartz-wm` joue ce
rôle et le problème n'existe pas.

### 4. Menu *Calculations* en échec — `Bad EXE format` (moteur XFTA 64 bits)

**Symptôme.** Au lancement d'un calcul :

```
Can't recognize 'Z:\app\externe\win32\xfta\xftar.exe C:\users\wine\Temp\...\xfta.txt'
as an internal or external command, or batch script
```

**Cause.** L'application invoque le moteur **XFTA** (`xftar.exe`) en commande externe. Or ce
binaire est un PE32+ **64 bits**, tandis que le préfixe Wine était initialement en **win32**,
qui refuse les exécutables 64 bits :

```
$ wine xftar.exe
ShellExecuteEx failed: Bad EXE format for Z:\app\externe\win32\xfta\xftar.exe.
```

Le `cmd` de Wine, incapable de lancer le binaire, renvoie alors « can't recognize … as a
command ». (La GUI, elle, est en 32 bits : la distribution mélange 32 et 64 bits, ce qui
fonctionne sur un Windows 64 bits réel.)

**Solution.** Basculer le préfixe Wine en **`WINEARCH=win64`** (WoW64), qui exécute à la fois
la GUI 32 bits et le moteur XFTA 64 bits.

### 5. Police crénelée — bitmaps embarqués

**Symptôme.** Tout le texte (menus et diagrammes) s'affichait crénelé, non anti-aliasé.

**Cause.** L'application Tk demande **Tahoma 8** (interface) et **Arial** (canevas). Ces
polices Windows embarquent des **bitmaps** aux petites tailles ; Wine affiche alors ces
bitmaps, que `FontSmoothing` ne peut pas lisser.

**Solution** (`fonts.reg` + Dockerfile) :

1. Activer le lissage : `HKCU\Control Panel\Desktop\FontSmoothing = 2`.
2. Retirer les polices bitmap `.fon` d'interface fournies par Wine (sserif / system / small).
3. Rediriger les familles vers les polices **croscore** (sans bitmaps embarqués, compatibles
   métriquement avec Windows, donc layout préservé) via
   `HKCU\Software\Wine\Fonts\Replacements` : `Tahoma` / `MS Sans Serif` / `Arial` → **Arimo**,
   `Times New Roman` → **Tinos**, `Courier New` → **Cousine**.

   *Tk convertit lui-même `Helvetica` → `Arial` et `Courier` → `Courier New` avant d'atteindre
   Wine : il faut donc rediriger les noms Windows, pas les alias Tk.*

Résultat : menus **et** texte des diagrammes entièrement anti-aliasés.

### 6. `Ctrl-C` ne stoppait pas le conteneur

**Symptôme.** Après `./run.sh up`, `Ctrl-C` ne tuait pas le conteneur ; l'application
continuait de tourner.

**Cause.** Deux facteurs :

1. `podman run` **attaché** transmettait SIGINT à la GUI Wine, qui l'ignore (application
   Windows sans gestion des signaux Unix) ; le conteneur survivait.
2. `podman rm -f` patientait **10 s** (grâce SIGTERM, ignorée par Wine) avant le SIGKILL.

**Solution** (`run.sh`, fonction `up`) : lancer le conteneur en **détaché**, l'attendre via
un `wait` bash **interruptible**, avec un `trap` qui exécute `podman rm -f -t 0` (SIGKILL
immédiat) sur Ctrl-C ou fermeture de la fenêtre. Arrêt désormais en moins d'une seconde.

## Licences

Arbre Analyst et XFTA sont des logiciels tiers ; voir `Arbre-Analyst - Licence.pdf` et
`XFTA-License.pdf`. Ce dépôt se limite à les empaqueter pour un usage local.
