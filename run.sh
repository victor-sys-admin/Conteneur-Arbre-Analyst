#!/usr/bin/env bash
# Helper pour construire, tester et lancer Arbre Analyst en conteneur (podman) sur macOS.
#
#   ./run.sh build      Construit l'image
#   ./run.sh test       Lance l'app en headless (Xvfb) et récupère une capture d'écran
#   ./run.sh xquartz     (Re)configure XQuartz pour l'affichage réseau
#   ./run.sh up         Configure XQuartz puis lance la GUI (affichage sur le Mac)
#   ./run.sh shell      Ouvre un shell dans le conteneur (débogage)
#   ./run.sh down       Arrête/supprime le conteneur
set -euo pipefail

cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"
export PATH="$PATH:/opt/podman/bin"

IMAGE="localhost/arbre-analyst:3.1.0"
NAME="arbre-analyst"
GATEWAY="host.docker.internal:0"   # passerelle podman -> XQuartz de l'hôte

log() { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }

build() {
  log "Construction de l'image $IMAGE ..."
  podman build -t "$IMAGE" .
}

ensure_image() { podman image exists "$IMAGE" || build; }

# Configure XQuartz : écoute TCP + autorise les clients réseau du conteneur.
setup_xquartz() {
  if ! command -v xhost >/dev/null 2>&1; then
    export PATH="$PATH:/opt/X11/bin"
  fi
  log "Activation de l'écoute TCP de XQuartz (nolisten_tcp = false)"
  defaults write org.xquartz.X11 nolisten_tcp -bool false
  defaults write org.xquartz.X11 no_auth      -bool false

  # (Re)démarrer XQuartz pour appliquer la préférence si nécessaire.
  if ! pgrep -x Xquartz >/dev/null 2>&1; then
    log "Démarrage de XQuartz ..."
    open -a XQuartz
    sleep 4
  fi
  export DISPLAY="${DISPLAY:-:0}"
  # Autoriser les connexions (session courante). Le conteneur arrive via la passerelle podman.
  log "Autorisation des clients X (xhost +) pour la session"
  /opt/X11/bin/xhost + >/dev/null 2>&1 || xhost + >/dev/null 2>&1 || true
  log "XQuartz prêt."
}

# Test headless : rend la fenêtre sous Xvfb dans le conteneur et exporte le screenshot.
test_headless() {
  ensure_image
  mkdir -p out
  podman rm -f "${NAME}-test" >/dev/null 2>&1 || true
  log "Lancement du conteneur en mode test (Xvfb interne) ..."
  podman run --name "${NAME}-test" "$IMAGE" test
  log "Récupération de la capture d'écran ..."
  podman cp "${NAME}-test:/tmp/out/arbre-analyst.png" out/arbre-analyst.png \
    && log "Capture -> $(pwd)/out/arbre-analyst.png" \
    || err "Impossible de récupérer la capture."
  podman rm -f "${NAME}-test" >/dev/null 2>&1 || true
}

up() {
  ensure_image
  setup_xquartz
  mkdir -p "$SCRIPT_DIR/analyses"
  podman rm -f -t 0 "$NAME" >/dev/null 2>&1 || true

  # Arrêt propre : Ctrl-C (ou fermeture de la fenêtre) doit tuer le conteneur.
  # On lance en DÉTACHÉ puis on attend : sinon, en mode attaché, le Ctrl-C est
  # transmis à l'appli Wine (une GUI Windows) qui l'ignore -> le conteneur survit.
  # -t 0 : SIGKILL immédiat. Sans ça, podman envoie SIGTERM (que la GUI Wine ignore)
  # puis attend 10 s avant de tuer -> l'arrêt paraîtrait "bloqué".
  stop_app() {
    echo
    log "Arrêt d'Arbre Analyst ..."
    podman rm -f -t 0 "$NAME" >/dev/null 2>&1 || true
    exit 0
  }
  trap stop_app INT TERM

  log "Lancement d'Arbre Analyst (GUI -> XQuartz, DISPLAY=$GATEWAY)"
  log "Sauvegardes persistées dans : $SCRIPT_DIR/analyses"
  log "La fenêtre s'ouvre à l'écran. Ctrl-C ici (ou fermer la fenêtre) pour quitter."

  podman run -d --rm --name "$NAME" \
    -e DISPLAY="$GATEWAY" \
    -v "$SCRIPT_DIR/analyses":/data \
    "$IMAGE" run >/dev/null

  # Attend l'arrêt du conteneur (fermeture de la fenêtre) en arrière-plan, puis un
  # 'wait' builtin : contrairement à une commande externe au premier plan, il est
  # interrompu IMMÉDIATEMENT par Ctrl-C, ce qui déclenche le trap tout de suite.
  podman wait "$NAME" >/dev/null 2>&1 &
  wait $! || true
  podman rm -f -t 0 "$NAME" >/dev/null 2>&1 || true
  log "Arbre Analyst est fermé."
}

shell() {
  ensure_image
  podman run --rm -it --entrypoint bash "$IMAGE"
}

down() {
  podman rm -f -t 0 "$NAME" "${NAME}-test" >/dev/null 2>&1 || true
  log "Conteneurs arrêtés."
}

case "${1:-up}" in
  build)   build ;;
  test)    test_headless ;;
  xquartz) setup_xquartz ;;
  up|run)  up ;;
  shell)   shell ;;
  down)    down ;;
  *) echo "Usage: $0 {build|test|xquartz|up|shell|down}"; exit 1 ;;
esac
