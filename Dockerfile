# Arbre Analyst V3.1.0 (application Windows 32 bits) exécutée sous Wine dans un conteneur Linux.
# L'interface graphique (Tkinter) est exportée en X11 vers XQuartz sur l'hôte macOS,
# ou capturée en interne via Xvfb pour les tests.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Wine 32 bits nécessite l'architecture i386 (l'exécutable est du PE32 / x86).
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wine wine32 wine64 \
      xvfb x11-utils x11-xserver-utils imagemagick \
      matchbox-window-manager xdotool \
      fonts-liberation2 fonts-dejavu-core fonts-wine fonts-croscore \
      cabextract procps xauth ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Polices : Wine fournit les versions bitmap (.fon) ET TrueType (.ttf) de MS Sans Serif,
# System, Small Fonts... et préfère les bitmap (crénelées) aux tailles natives. On retire
# les .fon d'interface pour forcer le repli sur les TrueType, qui sont anti-aliasées.
RUN rm -f /usr/share/wine/fonts/sserif*.fon \
          /usr/share/wine/fonts/small*.fon \
          /usr/share/wine/fonts/*vgasys*.fon

# Utilisateur non-root : Wine refuse de tourner en root et c'est plus propre.
RUN useradd -m -u 1000 -s /bin/bash wine
USER wine
# Préfixe WoW64 (win64) : exécute la GUI Arbre Analyst (PE32, 32 bits) ET le moteur
# XFTA (xftar.exe, PE32+ 64 bits). Un préfixe win32 refuserait le binaire 64 bits
# ("Bad EXE format"), ce qui casse le menu Calculations.
ENV HOME=/home/wine \
    WINEARCH=win64 \
    WINEPREFIX=/home/wine/.wine \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree=,mshtml="

# Réglage du lissage des polices (anti-aliasing) — sinon texte crénelé.
COPY --chown=wine:wine fonts.reg /home/wine/fonts.reg

# Initialisation du préfixe Wine (WoW64 : 32 + 64 bits) + activation du lissage au build.
RUN set -e ; \
    Xvfb :0 -screen 0 1024x768x24 >/dev/null 2>&1 & XVFB_PID=$! ; \
    export DISPLAY=:0 ; sleep 3 ; \
    wineboot --init 2>&1 | tail -3 ; \
    wineserver -w ; \
    regedit /home/wine/fonts.reg ; \
    wineserver -w ; \
    kill "$XVFB_PID" 2>/dev/null || true

# Application Arbre Analyst (contexte de build : ./app)
COPY --chown=wine:wine app/ /app/

COPY --chown=wine:wine entrypoint.sh /home/wine/entrypoint.sh

WORKDIR /app
ENTRYPOINT ["bash", "/home/wine/entrypoint.sh"]
CMD ["run"]
