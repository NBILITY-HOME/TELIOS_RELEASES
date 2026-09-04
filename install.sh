#!/usr/bin/env bash
# =============================================================================
#  Installateur TELIOS — NBILITY
#  Usage : bash install-desktop.sh      (en simple utilisateur, jamais en sudo)
#  Linux Mint 21+ / Ubuntu 22.04+
# =============================================================================
#
# Un seul installateur, deux situations :
#
#   - téléchargé seul, sans le reste du projet : il amorce tout — bilan du
#     système, paquets manquants, clé d'accès au dépôt, clonage — puis se
#     relance depuis le dépôt obtenu ;
#   - lancé depuis un dépôt déjà présent : il installe seulement l'intégration
#     au bureau (lanceur, icônes, entrée de menu).
#
# Ces deux voies ont longtemps été deux fichiers, dont un `install-nbility.sh`
# qui appelait celui-ci. Les réunir évite le seul incident qu'on ne rattrape
# pas au téléphone : un client qui lance l'un en croyant lancer l'autre.
set -euo pipefail

REPO_URL="https://github.com/NBILITY-HOME/TELIOS_MOBILE.git"
DEFAULT_DIR="$HOME/TELIOS"

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$ICI/.." && pwd)"

# Le dépôt est « présent » si les fichiers dont l'installation a besoin sont
# effectivement là. Se contenter du dossier parent ne suffirait pas : un script
# téléchargé dans ~/Téléchargements ferait passer $HOME pour un dépôt, et
# l'installation échouerait plus loin, sur une copie d'icône introuvable.
depot_present() {
  [ -f "$REPO/telios/__init__.py" ] && [ -f "$REPO/packaging/telios.desktop" ]
}

# --- Couleurs ---------------------------------------------------------------
ORANGE='\e[38;2;199;105;47m'
BLEU='\e[38;2;79;140;255m'
VERT='\e[32m'
ROUGE='\e[31m'
JAUNE='\e[33m'
GRIS='\e[90m'
GRAS='\e[1m'
FIN='\e[0m'

# =============================================================================
#  Amorce — uniquement quand le projet n'est pas encore sur le poste
# =============================================================================

PASS=0; FAIL=0; MISSING_PKGS=""; GH_TOKEN=""

ok()   { printf "   ${VERT}✓${FIN} %-38s ${GRIS}%s${FIN}\n" "$1" "${2:-}"; PASS=$((PASS+1)); }
ko()   { printf "   ${ROUGE}✗${FIN} %-38s ${ROUGE}%s${FIN}\n" "$1" "${2:-}"; FAIL=$((FAIL+1)); }
warn() { printf "   ${JAUNE}!${FIN} %-38s ${JAUNE}%s${FIN}\n" "$1" "${2:-}"; }

check_py() {  # check_py "libellé" "code python" "paquet apt si absent"
  if python3 -c "$2" >/dev/null 2>&1; then ok "$1"
  else ko "$1" "absent"; MISSING_PKGS="$MISSING_PKGS $3"; fi
}
check_cmd() { # check_cmd "libellé" commande "paquet apt si absent"
  if command -v "$2" >/dev/null 2>&1; then ok "$1" "$(command -v "$2")"
  else ko "$1" "introuvable"; MISSING_PKGS="$MISSING_PKGS $3"; fi
}

logo() {
  clear 2>/dev/null || true
  printf "${ORANGE}${GRAS}"
  cat <<'LOGO'

   ███╗   ██╗██████╗ ██╗██╗     ██╗████████╗██╗   ██╗
   ████╗  ██║██╔══██╗██║██║     ██║╚══██╔══╝╚██╗ ██╔╝
   ██╔██╗ ██║██████╔╝██║██║     ██║   ██║    ╚████╔╝
   ██║╚██╗██║██╔══██╗██║██║     ██║   ██║     ╚██╔╝
   ██║ ╚████║██████╔╝██║███████╗██║   ██║      ██║
   ╚═╝  ╚═══╝╚═════╝ ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝
LOGO
  printf "${FIN}${BLEU}   TELIOS — assainissement sécurisé de smartphones${FIN}\n"
  printf "${GRIS}   Installateur · NBILITY · contact@nbility.fr${FIN}\n\n"
}

bilan() {
  printf "${GRAS}── Bilan du système avant installation ──────────────────────────────${FIN}\n\n"

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|linuxmint) ok "Distribution" "${PRETTY_NAME:-$ID}" ;;
      *) warn "Distribution" "${PRETTY_NAME:-inconnue} (non testée, Mint/Ubuntu recommandés)" ;;
    esac
  else
    warn "Distribution" "non identifiée"
  fi

  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    ok "Session graphique" "${XDG_SESSION_TYPE:-détectée}"
  else
    ko "Session graphique" "aucun affichage (requis pour l'application)"
  fi

  local free_mb
  free_mb=$(df -Pm "$HOME" | awk 'NR==2{print $4}')
  if [ "${free_mb:-0}" -ge 200 ]; then ok "Espace disque dans \$HOME" "${free_mb} Mo libres"
  else ko "Espace disque dans \$HOME" "${free_mb:-?} Mo (< 200 Mo)"; fi

  if command -v python3 >/dev/null 2>&1; then
    local pyv; pyv=$(python3 -c 'import sys; print("%d.%d"%sys.version_info[:2])')
    if python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)'; then
      ok "Python 3 (>= 3.8)" "version $pyv"
    else
      ko "Python 3 (>= 3.8)" "version $pyv trop ancienne"
    fi
  else
    ko "Python 3" "introuvable"; MISSING_PKGS="$MISSING_PKGS python3"
  fi
  check_py "PyGObject (python3-gi)" "import gi" "python3-gi"
  check_py "GTK 4" "import gi; gi.require_version('Gtk','4.0')" "gir1.2-gtk-4.0"
  check_py "cairo (rendu PDF)" "import cairo" "python3-gi-cairo"

  check_cmd "git" git git
  check_cmd "ADB (Android Debug Bridge)" adb adb
  check_cmd "pkexec (installation des paquets)" pkexec policykit-1

  # Le dépôt source est privé : en anonyme, l'échec est normal et attendu dès
  # lors qu'une clé a été saisie. Sans clé ni accès anonyme, on avertit plutôt
  # que d'échouer ici — le clonage, lui, tranchera pour de bon.
  if timeout 10 git ls-remote --exit-code "$REPO_URL" HEAD >/dev/null 2>&1 \
     || [ -n "$GH_TOKEN" ]; then
    ok "Accès réseau GitHub"
  else
    warn "Accès réseau GitHub" "dépôt inaccessible sans clé d'accès"
  fi

  printf "\n   ${GRAS}Résultat : ${VERT}%d OK${FIN}${GRAS} / ${ROUGE}%d manquant(s)${FIN}\n\n" "$PASS" "$FAIL"
}

amorcer() {
  # Un second passage signifierait que le clonage n'a pas produit de dépôt
  # exploitable. Mieux vaut le dire que boucler.
  if [ "${TELIOS_AMORCE:-}" = "1" ]; then
    printf "${ROUGE}Le dépôt cloné est incomplet : installation interrompue.${FIN}\n" >&2
    exit 1
  fi
  export TELIOS_AMORCE=1

  # Les questions posées plus bas exigent un vrai terminal. Dans un tube
  # (« curl … | bash »), la lecture avalerait le script lui-même.
  if [ ! -t 0 ]; then
    printf "${ROUGE}Cet installateur pose des questions : lancez-le depuis un terminal${FIN}\n" >&2
    printf "   wget %s\n" \
           "https://github.com/NBILITY-HOME/TELIOS_RELEASES/raw/main/install.sh" >&2
    printf "   bash install.sh\n" >&2
    exit 1
  fi

  printf '\e[8;55;180t'   # fenêtre assez large pour le bilan
  logo

  printf "${GRAS}── Accès au dépôt TELIOS ────────────────────────────────────────────${FIN}\n\n"
  printf "   Collez la clé d'accès fournie avec votre licence.\n"
  printf "   ${GRIS}Elle ne sera ni affichée, ni enregistrée sur le disque.${FIN}\n\n"
  read -rsp "   Clé d'accès : " GH_TOKEN; printf "\n\n"

  bilan

  MISSING_PKGS=$(echo "$MISSING_PKGS" | xargs -n1 2>/dev/null | sort -u | xargs || true)
  if [ -n "$MISSING_PKGS" ]; then
    printf "${GRAS}── Dépendances manquantes ───────────────────────────────────────────${FIN}\n\n"
    printf "   Paquets à installer : ${JAUNE}%s${FIN}\n\n" "$MISSING_PKGS"
    printf "   Cet installateur tourne sans droits root : l'installation des\n"
    printf "   paquets système demande votre mot de passe, une seule fois.\n\n"
    read -rp "   Lancer « sudo apt install $MISSING_PKGS » maintenant ? [o/N] " REP
    if [[ "${REP,,}" =~ ^(o|oui|y|yes)$ ]]; then
      sudo apt-get update -qq
      sudo apt-get install -y $MISSING_PKGS
      printf "\n   ${VERT}✓${FIN} Dépendances installées.\n\n"
    else
      printf "\n   ${ROUGE}Installation interrompue.${FIN} Installez les paquets puis relancez :\n"
      printf "   sudo apt install %s\n\n" "$MISSING_PKGS"
      exit 1
    fi
  fi

  printf "${GRAS}── Téléchargement de TELIOS ─────────────────────────────────────────${FIN}\n\n"
  read -rp "   Dossier d'installation [${DEFAULT_DIR}] : " INSTALL_DIR
  INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"

  GIT_ENV=()
  ASKPASS_FILE=""
  if [ -n "$GH_TOKEN" ]; then
    # La clé transite par GIT_ASKPASS et rien d'autre : jamais dans l'URL du
    # dépôt distant, donc jamais dans .git/config ni dans l'historique du
    # shell, où elle resterait lisible longtemps après l'installation.
    ASKPASS_FILE=$(mktemp)
    chmod 700 "$ASKPASS_FILE"
    cat > "$ASKPASS_FILE" <<ASKPASS
#!/bin/sh
case "\$1" in
  Username*) echo "x-access-token" ;;
  *)         echo "$GH_TOKEN" ;;
esac
ASKPASS
    GIT_ENV=(env GIT_ASKPASS="$ASKPASS_FILE" GIT_TERMINAL_PROMPT=0)
  fi
  nettoyer() { [ -n "$ASKPASS_FILE" ] && rm -f "$ASKPASS_FILE"; }
  trap nettoyer EXIT

  if [ -d "$INSTALL_DIR/.git" ]; then
    printf "   Dépôt déjà présent : mise à jour…\n"
    "${GIT_ENV[@]}" git -C "$INSTALL_DIR" pull --ff-only
  else
    "${GIT_ENV[@]}" git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  printf "   ${VERT}✓${FIN} Projet dans %s\n\n" "$INSTALL_DIR"

  printf "${GRAS}── Icône et lanceur de menu ─────────────────────────────────────────${FIN}\n\n"
  # On repasse par l'installateur du dépôt obtenu, et non par celui-ci : c'est
  # sa version à lui qui doit poser l'intégration au bureau.
  bash "$INSTALL_DIR/packaging/install-desktop.sh"

  printf "\n${GRAS}── Validation finale ────────────────────────────────────────────────${FIN}\n\n"
  # « -t . » est indispensable : sans lui, six modules de test ne se chargent
  # pas et la suite se termine au vert sans avoir rien vérifié.
  if (cd "$INSTALL_DIR" && python3 -m unittest discover -s tests -t . >/dev/null 2>&1); then
    printf "   ${VERT}✓${FIN} Suite de tests : tous les tests passent.\n"
  else
    printf "   ${JAUNE}!${FIN} Suite de tests : des tests ont échoué.\n"
    printf "     Signalez-le à contact@nbility.fr avant d'établir une attestation.\n"
  fi

  printf "\n${ORANGE}${GRAS}   Installation terminée !${FIN}\n"
  printf "   Cherchez ${GRAS}« TELIOS »${FIN} dans le menu des applications.\n"
  printf "   ${GRIS}Les mises à jour se font ensuite depuis Réglages → Mises à jour,${FIN}\n"
  printf "   ${GRIS}sans clé et sans terminal.${FIN}\n\n"
}

# =============================================================================
#  Intégration au bureau — le dépôt est là, on installe
# =============================================================================

installer_bureau() {
  local BIN_DIR="$HOME/.local/bin"
  local APP_DIR="$HOME/.local/share/applications"
  local ICON_ROOT="$HOME/.local/share/icons/hicolor"
  local LAUNCHER="$BIN_DIR/telios-gui"
  local DESKTOP="$APP_DIR/telios.desktop"

  echo "==> Dépôt        : $REPO"
  command -v python3 >/dev/null || { echo "python3 introuvable." >&2; exit 1; }
  if ! python3 -c "import gi; gi.require_version('Gtk','4.0')" 2>/dev/null; then
    echo "!! Dépendances manquantes. Installez-les :" >&2
    echo "   sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-4.0 adb policykit-1" >&2
    exit 1
  fi

  mkdir -p "$BIN_DIR" "$APP_DIR"

  # 1) Lanceur : il suit le lien « courante », jamais un chemin figé.
  #
  #    Sans cette indirection, une mise à jour posée par « Réglages → Mises à
  #    jour » s'installerait sans jamais s'exécuter : le lanceur continuerait de
  #    démarrer le dépôt cloné. « courante » est donc la seule autorité — cet
  #    installateur la fait pointer sur ce dépôt, la mise à jour la fait pointer
  #    sur la version qu'elle vient d'installer.
  local PARTAGE="$HOME/.local/share/telios"
  local COURANTE="$PARTAGE/courante"
  mkdir -p "$PARTAGE"

  local ANCIENNE=""
  [ -L "$COURANTE" ] && ANCIENNE="$(readlink "$COURANTE")"
  ln -sfn "$REPO" "$COURANTE"
  if [ -n "$ANCIENNE" ] && [ "$ANCIENNE" != "$REPO" ]; then
    echo "==> Version active : $REPO"
    echo "    (remplace $ANCIENNE — relancer cet installateur impose ce dépôt)"
  fi

  cat > "$LAUNCHER" <<'LAUNCH'
#!/usr/bin/env bash
# « courante » désigne la version à exécuter : ce dépôt après installation,
# ou la dernière version posée par la mise à jour. Le repli couvre le cas où
# le lien aurait disparu.
COURANTE="$HOME/.local/share/telios/courante"
if [ -d "$COURANTE" ]; then
  cd "$COURANTE"
else
  cd "__REPO__"
fi
exec python3 -m telios.gui "$@"
LAUNCH
  sed -i "s|__REPO__|$REPO|" "$LAUNCHER"
  chmod +x "$LAUNCHER"
  echo "==> Lanceur      : $LAUNCHER -> $COURANTE"

  # 2) Icônes (thème hicolor + fallback scalable SVG).
  local size dest
  for size in 16 24 32 48 64 128 256 512; do
    dest="$ICON_ROOT/${size}x${size}/apps"
    mkdir -p "$dest"
    cp "$REPO/packaging/icons/telios-${size}.png" "$dest/telios.png"
  done
  mkdir -p "$ICON_ROOT/scalable/apps"
  cp "$REPO/telios/gui/assets/telios.svg" "$ICON_ROOT/scalable/apps/telios.svg"
  echo "==> Icônes       : $ICON_ROOT"

  # 3) Fichier .desktop avec Exec pointant sur le lanceur absolu.
  sed "s|__EXEC__|$LAUNCHER|" "$REPO/packaging/telios.desktop" > "$DESKTOP"
  chmod +x "$DESKTOP"
  echo "==> Lanceur menu : $DESKTOP"

  command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache   >/dev/null && gtk-update-icon-cache -f -t "$ICON_ROOT" 2>/dev/null || true

  echo
  echo "✓ Installé. Cherchez « telios » dans le menu des applications."
  echo "  (déconnectez/reconnectez la session si l'icône n'apparaît pas tout de suite)"
}

# =============================================================================
if depot_present; then
  installer_bureau
else
  amorcer
fi
