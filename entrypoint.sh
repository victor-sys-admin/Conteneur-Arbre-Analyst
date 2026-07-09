#!/usr/bin/env bash
# Point d'entrée du conteneur Arbre Analyst.
#   run    : lance l'application, GUI exportée vers $DISPLAY (XQuartz sur macOS)
#   test   : lance l'app sous un Xvfb interne et capture un screenshot (/tmp/out)
#   shell  : shell interactif pour le débogage
set -euo pipefail

APP="/app/Arbre Analyst.exe"
MODE="${1:-run}"

start_xvfb() {
  local disp="$1"
  Xvfb "$disp" -screen 0 "${XVFB_RES:-1280x900x24}" >/tmp/xvfb.log 2>&1 &
  export DISPLAY="$disp"
  # Attendre que le serveur X réponde
  for _ in $(seq 1 20); do
    if xdpyinfo -display "$disp" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  echo "!! Xvfb n'a pas démarré" >&2; cat /tmp/xvfb.log >&2; return 1
}

case "$MODE" in
  run)
    if [ -z "${DISPLAY:-}" ]; then
      echo "!! DISPLAY non défini. Sur macOS : DISPLAY=host.docker.internal:0 (XQuartz)." >&2
      exit 1
    fi
    # Persistance : si un dossier /data est monté (depuis le Mac), on y fait pointer
    # « Mes documents » de Wine -> les sauvegardes atterrissent directement sur le Mac.
    if [ -d /data ]; then
      DOCS="$WINEPREFIX/drive_c/users/$(whoami)/Documents"
      rm -rf "$DOCS" 2>/dev/null || true
      ln -sfn /data "$DOCS"
      echo ">> Persistance : sauvegardes -> /data (dossier 'analyses' sur le Mac)"
    fi
    echo ">> Lancement d'Arbre Analyst — DISPLAY=$DISPLAY"
    exec wine "$APP"
    ;;

  test)
    OUT="${OUT_DIR:-/tmp/out}"
    mkdir -p "$OUT"
    start_xvfb ":99"
    # Gestionnaire de fenêtres léger : mappe/redimensionne la fenêtre comme le fera
    # quartz-wm sous XQuartz -> capture d'écran représentative.
    matchbox-window-manager -use_titlebar no >/dev/null 2>&1 &
    sleep 1
    echo ">> [test] Démarrage d'Arbre Analyst sous Xvfb..."
    # NE PAS rediriger vers un fichier/dev-null : le Python gelé exige des handles
    # standard valides (un pipe convient, pas un fichier). On passe donc par 'tee'.
    wine "$APP" 2>&1 | tee /tmp/wine.log &
    # Laisser le temps à Python/Tk de créer la fenêtre
    for i in $(seq 1 30); do
      sleep 2
      # Y a-t-il une fenêtre applicative (au-delà de la racine) ?
      if xwininfo -root -children -display :99 2>/dev/null | grep -qiE 'Arbre|Analyst|python|tk'; then
        echo ">> [test] Fenêtre détectée après ${i}x2s"
        break
      fi
    done
    sleep 6
    echo ">> [test] État des fenêtres X :"
    xwininfo -root -children -display :99 2>/dev/null | sed -n '1,40p' || true
    echo ">> [test] Capture d'écran -> $OUT/arbre-analyst.png"
    import -display :99 -window root "$OUT/arbre-analyst.png" 2>/tmp/import.log \
      || { echo "!! capture échouée"; cat /tmp/import.log >&2; }
    echo "===== wine.log (30 dernières lignes) ====="
    tail -30 /tmp/wine.log 2>/dev/null || true
    # Garder le conteneur vivant un court instant pour permettre podman cp
    sleep 2
    ;;

  shell)
    exec /bin/bash
    ;;

  *)
    echo ">> Lancement direct : wine $*"
    exec wine "$@"
    ;;
esac
