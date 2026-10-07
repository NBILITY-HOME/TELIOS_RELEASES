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
#     système, paquets manquants, téléchargement de la DERNIÈRE VERSION
#     PUBLIÉE ET SIGNÉE — puis se relance depuis la version obtenue ;
#   - lancé depuis un dépôt déjà présent : il installe seulement l'intégration
#     au bureau (lanceur, icônes, entrée de menu).
#
# Ces deux voies ont longtemps été deux fichiers, dont un `install-nbility.sh`
# qui appelait celui-ci. Les réunir évite le seul incident qu'on ne rattrape
# pas au téléphone : un client qui lance l'un en croyant lancer l'autre.
set -euo pipefail

# La source d'une première installation est celle des mises à jour : le dépôt
# public de distribution, son manifeste signé et ses archives. Ni clé d'accès,
# ni dépôt source privé, ni git : un client n'a rien à saisir, et la première
# version est authentifiée comme toutes les suivantes (ADR 009).
DEPOT_PUBLIC="NBILITY-HOME/TELIOS_RELEASES"
MANIFESTE_API="https://api.github.com/repos/$DEPOT_PUBLIC/contents/latest.json?ref=main"
MANIFESTE_URL="https://raw.githubusercontent.com/$DEPOT_PUBLIC/main/latest.json"
# L'adresse directe, et non « github.com/…/raw/… » : celle-ci n'est qu'une
# redirection, qui a répondu 500 le 07/10/2026 pendant que le fichier, lui,
# restait servi normalement à l'adresse directe.
INSTALLATEUR_URL="https://raw.githubusercontent.com/$DEPOT_PUBLIC/main/install.sh"
# Clé publique de l'éditeur : la même que `telios/maj.py` (un test l'impose).
# Elle voyage avec ce script, servi en HTTPS par GitHub : c'est la racine de
# confiance de la première installation.
CLE_PUBLIQUE="7190fdcf9f863615bce7c2b5844b60e2da4af27b3b51336460f07ca44309742b"
PARTAGE="$HOME/.local/share/telios"

# `pwd -P` : le chemin réel, liens résolus. Lancé à travers le lien
# « courante » (ce que fait l'amorce, ou une personne qui le retrouve là),
# `pwd` seul rendait « …/courante » : l'installateur faisait alors pointer
# « courante » sur lui-même, et la boucle empêchait de poser icônes et menu.
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$ICI/.." && pwd -P)"

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

PASS=0; FAIL=0; MISSING_PKGS=""; A_INSTALLER_DEPUIS_TELIOS=0

# Colonne alignée en caractères, pas en octets : `printf %-38s` compte les
# octets, et chaque lettre accentuée (è, ô, é) en vaut deux en UTF-8 — la
# valeur de « Accès au dépôt de distribution » partait de travers.
colonne() { local pad=$((38 - ${#1})); [ "$pad" -lt 1 ] && pad=1; printf "%s%*s" "$1" "$pad" ""; }
ok()   { printf "   ${VERT}✓${FIN} %s${GRIS}%s${FIN}\n" "$(colonne "$1")" "${2:-}"; PASS=$((PASS+1)); }
ko()   { printf "   ${ROUGE}✗${FIN} %s${ROUGE}%s${FIN}\n" "$(colonne "$1")" "${2:-}"; FAIL=$((FAIL+1)); }
warn() { printf "   ${JAUNE}!${FIN} %s${JAUNE}%s${FIN}\n" "$(colonne "$1")" "${2:-}"; }

# Un chemin du dossier personnel s'écrit « ~/… » : sinon la ligne déborde la
# fenêtre et se coupe au milieu du nom.
court() { printf "%s" "${1/#$HOME/\~}"; }

# Vrai quand l'intégration au bureau est appelée par l'amorce : elle parle
# alors dans le style du rapport d'installation, et laisse la conclusion à
# l'amorce, qui ne vient qu'après la validation finale.
par_amorce() { [ "${TELIOS_AMORCE:-}" = "1" ]; }

check_py() {  # check_py "libellé" "code python" "paquet apt si absent"
  if python3 -c "$2" >/dev/null 2>&1; then ok "$1"
  else ko "$1" "absent"; MISSING_PKGS="$MISSING_PKGS $3"; fi
}
# Un outil que TELIOS installe lui-même, page « Dépendances » : signalé, jamais
# exigé ici. Seul le socle qui fait démarrer l'application est requis par
# l'installateur (décision du 6 octobre 2026) ; le reste se coche dans
# l'application, sans terminal.
facultatif() { # facultatif "libellé" présent(0/1)
  if [ "$2" = "1" ]; then
    printf "   ${VERT}✓${FIN} %s${GRIS}%s${FIN}\n" "$(colonne "$1")" "présent"
  else
    printf "   ${GRIS}·${FIN} %s${JAUNE}%s${FIN}\n" "$(colonne "$1")" "à installer depuis TELIOS"
    A_INSTALLER_DEPUIS_TELIOS=$((A_INSTALLER_DEPUIS_TELIOS + 1))
  fi
}
present_py()  { python3 -c "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
present_cmd() { command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

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

  if python3 -c "import urllib.request as u; u.urlopen('$MANIFESTE_URL', timeout=10)" >/dev/null 2>&1; then
    ok "Accès au dépôt de distribution" "github.com"
  else
    ko "Accès au dépôt de distribution" "injoignable (réseau, proxy ?)"
  fi

  printf "\n   ${GRAS}Résultat : ${VERT}%d OK${FIN}${GRAS} / ${ROUGE}%d manquant(s)${FIN}\n\n" "$PASS" "$FAIL"

  # La liste suit `telios/deps.py` (un test l'impose) : ce que la page
  # « Dépendances » de TELIOS propose, pré-coché quand il manque.
  printf "   ${GRAS}Outils installés ensuite depuis TELIOS${FIN} ${GRIS}(Réglages → Dépendances)${FIN}\n\n"
  facultatif "cairo (rapports PDF)" "$(present_py 'import cairo')"
  facultatif "ADB (Android Debug Bridge)" "$(present_cmd adb)"
  facultatif "pkexec (fenêtre d'autorisation)" "$(present_cmd pkexec)"
  facultatif "OpenSSL (certificat d'un APK)" "$(present_cmd openssl)"
  facultatif "zbar-tools (QR code de licence)" "$(present_cmd zbarimg)"
  facultatif "scrcpy (écran du téléphone)" "$(present_cmd scrcpy)"
  # Sans pkexec, la page « Dépendances » ne peut rien installer : on le dit,
  # avec la commande, plutôt que de laisser découvrir un bouton sans effet.
  if [ "$(present_cmd pkexec)" = "0" ]; then
    printf "\n   ${JAUNE}!${FIN} Sans pkexec, TELIOS ne pourra pas installer ces outils lui-même :\n"
    printf "     sudo apt install policykit-1\n"
  fi
  printf "\n"
}

# La suite de tests de la version posée, jouée sur ce poste. Une trentaine de
# secondes sans rien à l'écran faisait croire l'installation bloquée (vu le
# 6 octobre 2026) : on dit ce qui se passe, et une roue tourne avec le nombre
# de contrôles faits et le temps écoulé. Le verdict, lui, ne vient que du
# code de retour de la suite — jamais du compteur, qui n'est qu'un repère.
valider_installation() {
  local dossier="$1" journal pid debut faits total roue code i=0
  journal=$(mktemp)
  printf "   Vérification de TELIOS sur ce poste : près de 1 500 contrôles automatiques,\n"
  printf "   environ 30 secondes. ${GRIS}Rien n'est envoyé, rien n'est modifié.${FIN}\n\n"
  # « -t . » est indispensable : sans lui, six modules de test ne se chargent
  # pas et la suite se termine au vert sans avoir rien vérifié.
  (cd "$dossier" && exec python3 -m unittest discover -s tests -t . -v) >/dev/null 2>"$journal" &
  pid=$!
  debut=$SECONDS
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*|*UTF8*) roue="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏" ;;
    *) roue='|/-\' ;;
  esac
  if [ -t 1 ]; then
    tput civis 2>/dev/null || true
    trap 'tput cnorm 2>/dev/null || true' EXIT
    while kill -0 "$pid" 2>/dev/null; do
      # En mode détaillé, chaque test finit par « ... ok », « ... skipped… »,
      # « ... FAIL » ou « ... ERROR ». Les points de progression du mode
      # court, eux, s'interrompaient au premier message écrit par un test.
      faits=$(grep -cE '\.\.\. (ok|skipped|FAIL|ERROR|expected failure|unexpected success)' "$journal" 2>/dev/null || true)
      printf "\r   ${ORANGE}%s${FIN} %d contrôle(s) effectué(s) · %d s " \
        "${roue:$((i % ${#roue})):1}" "$faits" "$((SECONDS - debut))"
      i=$((i + 1))
      sleep 0.15
    done
    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
  fi
  if wait "$pid"; then code=0; else code=$?; fi
  total=$(grep -o '^Ran [0-9]*' "$journal" | grep -o '[0-9]*' || true)
  rm -f "$journal"
  if [ "$code" -eq 0 ]; then
    printf "   ${VERT}✓${FIN} Suite de tests : %s contrôles réussis en %d s.\n" "${total:-tous les}" "$((SECONDS - debut))"
  else
    printf "   ${JAUNE}!${FIN} Suite de tests : des contrôles ont échoué.\n"
    printf "     Signalez-le à contact@nbility.fr avant d'établir une attestation.\n"
  fi
}

amorcer() {
  # Un second passage signifierait que la version téléchargée n'est pas
  # exploitable. Mieux vaut le dire que boucler.
  if [ "${TELIOS_AMORCE:-}" = "1" ]; then
    printf "${ROUGE}La version téléchargée est incomplète : installation interrompue.${FIN}\n" >&2
    exit 1
  fi
  export TELIOS_AMORCE=1

  # La question posée plus bas exige un vrai terminal. Dans un tube
  # (« curl … | bash »), la lecture avalerait le script lui-même.
  if [ ! -t 0 ]; then
    printf "${ROUGE}Cet installateur pose des questions : lancez-le depuis un terminal${FIN}\n" >&2
    printf "   wget -O install.sh %s && bash install.sh\n" "$INSTALLATEUR_URL" >&2
    exit 1
  fi

  printf '\e[8;55;180t'   # fenêtre assez large pour le bilan
  logo

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
      # shellcheck disable=SC2086
      sudo apt-get install -y $MISSING_PKGS
      printf "\n   ${VERT}✓${FIN} Dépendances installées.\n\n"
    else
      printf "\n   ${ROUGE}Installation interrompue.${FIN} Installez les paquets puis relancez :\n"
      printf "   sudo apt install %s\n\n" "$MISSING_PKGS"
      exit 1
    fi
  fi

  printf "${GRAS}── Téléchargement de la dernière version publiée ────────────────────${FIN}\n\n"
  # Même chaîne que la mise à jour depuis l'application (telios/maj.py) :
  # manifeste signé par l'éditeur, archive vérifiée par son empreinte, chemins
  # confinés à l'extraction, une version par dossier et le lien « courante ».
  # Un seul écart, et rien n'est installé.
  local VERSION
  if ! VERSION=$(python3 - "$MANIFESTE_API $MANIFESTE_URL" "$CLE_PUBLIQUE" "$PARTAGE" <<'AMORCE'
"""Amorce de TELIOS : télécharge, authentifie et pose la dernière version.

Autonome — le projet n'est pas encore là — et limité à la bibliothèque
standard (ADR 005). La vérification Ed25519 suit la RFC 8032 ; un test
l'éprouve contre `telios/ed25519.py`, et la chaîne entière contre une
publication signée d'une clé d'essai. Écrit en Python 3.8 au plus.

    python3 - "<sources du manifeste>" <clé publique hex> <racine>

Imprime la version installée sur la sortie standard ; tout refus part sur
la sortie d'erreur avec un code non nul.
"""
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

TAILLE_MAX = 200 * 1024 * 1024
DELAI = 30

# ── Ed25519, vérification seule (RFC 8032, § 5.1.7)
_P = 2 ** 255 - 19
_Q = 2 ** 252 + 27742317777372353535851937790883648493


def _inv(x):
    return pow(x, _P - 2, _P)


_D = -121665 * _inv(121666) % _P
_I = pow(2, (_P - 1) // 4, _P)


def _add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % _P
    b = (p[1] + p[0]) * (q[1] + q[0]) % _P
    c = 2 * p[3] * q[3] * _D % _P
    d = 2 * p[2] * q[2] % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _mul(s, p):
    r = (0, 1, 1, 0)
    while s:
        if s & 1:
            r = _add(r, p)
        p = _add(p, p)
        s >>= 1
    return r


def _egaux(p, q):
    return (p[0] * q[2] - q[0] * p[2]) % _P == 0 and (p[1] * q[2] - q[1] * p[2]) % _P == 0


def _x(y, signe):
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inv(_D * y * y + 1) % _P
    if x2 == 0:
        return None if signe else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P:
        x = x * _I % _P
    if (x * x - x2) % _P:
        return None
    if x & 1 != signe:
        x = _P - x
    return x


_GY = 4 * _inv(5) % _P
_GX = _x(_GY, 0)
_G = (_GX, _GY, 1, _GX * _GY % _P)


def _point(octets):
    if len(octets) != 32:
        return None
    y = int.from_bytes(octets, "little")
    signe = y >> 255
    y &= (1 << 255) - 1
    x = _x(y, signe)
    return None if x is None else (x, y, 1, x * y % _P)


def verifier(cle, message, signature):
    if len(cle) != 32 or len(signature) != 64:
        return False
    a = _point(cle)
    r = _point(signature[:32])
    if a is None or r is None:
        return False
    s = int.from_bytes(signature[32:], "little")
    if s >= _Q:
        return False
    h = int.from_bytes(hashlib.sha512(signature[:32] + cle + message).digest(), "little") % _Q
    return _egaux(_mul(s, _G), _add(r, _mul(h, a)))


# ── chaîne d'installation

class Refus(Exception):
    pass


def lire(url, limite=TAILLE_MAX):
    requete = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github.raw+json", "User-Agent": "TELIOS-installateur"})
    with urllib.request.urlopen(requete, timeout=DELAI) as flux:
        donnees = flux.read(limite + 1)
    if len(donnees) > limite:
        raise Refus("réponse anormalement volumineuse : refusée")
    return donnees


def manifeste(sources, cle):
    echecs = []
    for url in sources:
        try:
            brut = lire(url, 1024 * 1024)
            break
        except Refus:
            raise
        except Exception as exc:  # réseau : on essaie la source suivante
            echecs.append("{0} : {1}".format(url, exc))
    else:
        raise Refus("dépôt de distribution injoignable\n  " + "\n  ".join(echecs))
    try:
        donnees = json.loads(brut.decode("utf-8"))
    except ValueError:
        raise Refus("le manifeste publié n'est pas un JSON valide")
    if not isinstance(donnees, dict):
        raise Refus("le manifeste publié n'a pas la forme attendue")
    manquants = [c for c in ("version", "archive", "sha256", "signature") if not donnees.get(c)]
    if manquants:
        raise Refus("manifeste incomplet, champs manquants : " + ", ".join(manquants))
    corps = {k: v for k, v in donnees.items() if k != "signature"}
    charge = json.dumps(corps, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    try:
        signature = bytes.fromhex(str(donnees["signature"]))
    except ValueError:
        signature = b""
    if not verifier(cle, charge, signature):
        raise Refus("la signature du manifeste est invalide : il ne vient pas de l'éditeur")
    version = str(donnees["version"]).strip().lstrip("v")
    # Le numéro devient un nom de dossier : rien d'autre que des chiffres.
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){1,3}", version):
        raise Refus("numéro de version inattendu : " + version)
    return version, str(donnees["archive"]), str(donnees["sha256"]).strip().lower()


def sur(membre, racine):
    if membre.islnk() or membre.issym() or membre.isdev():
        return False
    destination = (racine / membre.name).resolve()
    try:
        destination.relative_to(racine.resolve())
    except ValueError:
        return False
    return True


def installer(version, url, empreinte, racine):
    versions = racine / "versions"
    versions.mkdir(parents=True, exist_ok=True)
    provisoire = Path(tempfile.mkdtemp(prefix="telios-amorce-", dir=str(racine)))
    try:
        archive = provisoire / "telios.tar.gz"
        donnees = lire(url)
        obtenue = hashlib.sha256(donnees).hexdigest()
        if obtenue != empreinte:
            raise Refus("empreinte SHA-256 incorrecte : l'archive ne correspond pas à celle "
                        "publiée\n  attendue : {0}\n  obtenue  : {1}".format(empreinte, obtenue))
        archive.write_bytes(donnees)
        extrait = provisoire / "extrait"
        extrait.mkdir()
        with tarfile.open(str(archive), "r:gz") as tar:
            membres = tar.getmembers()
            if not all(sur(m, extrait) for m in membres):
                raise Refus("l'archive contient des chemins hors du dossier d'installation : refusée")
            try:
                tar.extractall(str(extrait), members=membres, filter="data")
            except TypeError:  # Python < 3.12 : notre contrôle seul protège
                tar.extractall(str(extrait), members=membres)
        contenu = list(extrait.iterdir())
        source = contenu[0] if len(contenu) == 1 and contenu[0].is_dir() else extrait
        if not (source / "telios" / "__init__.py").is_file():
            raise Refus("l'archive ne contient pas TELIOS")
        cible = versions / version
        if cible.exists():
            shutil.rmtree(str(cible))
        shutil.move(str(source), str(cible))
        lien = racine / "courante"
        transit = racine / (".courante-" + version)
        if transit.is_symlink() or transit.exists():
            transit.unlink()
        transit.symlink_to(cible, target_is_directory=True)
        os.replace(str(transit), str(lien))  # atomique : « courante » ne manque jamais
    finally:
        shutil.rmtree(str(provisoire), ignore_errors=True)


def principal(argv):
    sources, cle, racine = argv[1].split(), bytes.fromhex(argv[2]), Path(argv[3])
    try:
        version, url, empreinte = manifeste(sources, cle)
        installer(version, url, empreinte, racine)
    except Refus as exc:
        sys.stderr.write("Installation refusée : {0}\n".format(exc))
        return 1
    except Exception as exc:
        sys.stderr.write("Installation impossible : {0}\n".format(exc))
        return 1
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(principal(sys.argv))
AMORCE
  ); then
    printf "\n   ${ROUGE}✗ Rien n'a été installé.${FIN} Vérifiez la connexion, puis relancez.\n" >&2
    printf "     Si le refus persiste, écrivez à contact@nbility.fr.\n\n" >&2
    exit 1
  fi
  printf "   ${VERT}✓${FIN} TELIOS %s, signature de l'éditeur et empreinte vérifiées\n\n" "$VERSION"

  printf "${GRAS}── Icône et lanceur de menu ─────────────────────────────────────────${FIN}\n\n"
  # On repasse par l'installateur de la version obtenue, et non par celui-ci :
  # c'est le sien qui doit poser l'intégration au bureau. Par son vrai dossier,
  # jamais par le lien « courante » qu'il va lui-même réécrire.
  bash "$PARTAGE/versions/$VERSION/packaging/install-desktop.sh"

  printf "\n${GRAS}── Validation finale ────────────────────────────────────────────────${FIN}\n\n"
  valider_installation "$PARTAGE/courante"

  printf "\n${ORANGE}${GRAS}   Installation terminée !${FIN}\n"
  printf "   Cherchez ${GRAS}« TELIOS »${FIN} dans le menu des applications (Accessoires),\n"
  printf "   puis saisissez la clé de licence de votre entreprise dans Réglages → Licence.\n"
  # Un outil manque : l'installation n'en est pas moins faite, mais la
  # personne doit savoir où le compléter — sinon elle découvre l'absence au
  # premier rapport PDF ou au premier téléphone branché.
  if [ "$A_INSTALLER_DEPUIS_TELIOS" -gt 0 ]; then
    printf "\n   ${JAUNE}${GRAS}%d outil(s) à installer depuis TELIOS${FIN}\n" "$A_INSTALLER_DEPUIS_TELIOS"
    printf "   1. Lancez TELIOS : une fenêtre signale ce qui manque ;\n"
    printf "   2. ouvrez Réglages → Dépendances (le bouton de la fenêtre y mène) ;\n"
    printf "   3. les outils manquants y sont pré-cochés : cliquez « Installer la sélection »,\n"
    printf "      puis saisissez votre mot de passe.\n"
  fi
  printf "   ${GRIS}Les mises à jour se font ensuite depuis Réglages → Mises à jour.${FIN}\n\n"
}

# =============================================================================
#  Intégration au bureau — le dépôt est là, on installe
# =============================================================================

# Le menu de Cinnamon (Linux Mint) garde en mémoire l'état qu'il a lu : une
# entrée supprimée puis reposée — désinstallation suivie d'une réinstallation
# — n'y reparaissait pas avant une reconnexion. Vu le 6 octobre 2026. On lui
# demande de se recharger, lui seul : ni redémarrage de Cinnamon, ni fenêtre
# fermée. Sans Cinnamon (GNOME, autre bureau), rien à faire : le menu suit
# les fichiers de lui-même. Un échec ici n'en est pas un pour l'installation.
recharger_menu() {
  command -v gdbus >/dev/null || return 0
  gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon \
    --method org.Cinnamon.ReloadXlet 'menu@cinnamon.org' 'APPLET' >/dev/null 2>&1 || true
}

installer_bureau() {
  local BIN_DIR="$HOME/.local/bin"
  local APP_DIR="$HOME/.local/share/applications"
  local ICON_ROOT="$HOME/.local/share/icons/hicolor"
  local LAUNCHER="$BIN_DIR/telios-gui"
  local DESKTOP="$APP_DIR/telios.desktop"

  par_amorce || echo "==> Dépôt        : $REPO"
  command -v python3 >/dev/null || { echo "python3 introuvable." >&2; exit 1; }
  if ! python3 -c "import gi; gi.require_version('Gtk','4.0')" 2>/dev/null; then
    echo "!! Socle manquant pour lancer TELIOS. Installez-le :" >&2
    echo "   sudo apt install python3-gi gir1.2-gtk-4.0" >&2
    echo "   (les autres outils s'installent ensuite depuis TELIOS, Réglages → Dépendances)" >&2
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
    if ! par_amorce; then
      echo "==> Version active : $REPO"
      echo "    (remplace $ANCIENNE — relancer cet installateur impose ce dépôt)"
    fi
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
  if par_amorce; then ok "Lanceur" "$(court "$LAUNCHER")"
  else echo "==> Lanceur      : $LAUNCHER -> $COURANTE"; fi

  # 2) Icônes (thème hicolor + fallback scalable SVG).
  local size dest
  for size in 16 24 32 48 64 128 256 512; do
    dest="$ICON_ROOT/${size}x${size}/apps"
    mkdir -p "$dest"
    cp "$REPO/packaging/icons/telios-${size}.png" "$dest/telios.png"
  done
  mkdir -p "$ICON_ROOT/scalable/apps"
  cp "$REPO/telios/gui/assets/telios.svg" "$ICON_ROOT/scalable/apps/telios.svg"
  if par_amorce; then ok "Icônes" "$(court "$ICON_ROOT")"
  else echo "==> Icônes       : $ICON_ROOT"; fi

  # 3) Fichier .desktop avec Exec pointant sur le lanceur absolu.
  sed "s|__EXEC__|$LAUNCHER|" "$REPO/packaging/telios.desktop" > "$DESKTOP"
  chmod +x "$DESKTOP"
  if par_amorce; then ok "Entrée de menu" "Accessoires → TELIOS"
  else echo "==> Lanceur menu : $DESKTOP"; fi

  command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" 2>/dev/null || true
  command -v gtk-update-icon-cache   >/dev/null && gtk-update-icon-cache -f -t "$ICON_ROOT" 2>/dev/null || true
  recharger_menu

  # Appelée par l'amorce, la conclusion vient après la validation finale :
  # l'écrire ici la faisait apparaître au milieu du rapport, en double.
  par_amorce && return 0
  echo
  echo "✓ Installé. Cherchez « TELIOS » dans le menu des applications (rubrique Accessoires)."
}

# =============================================================================
if depot_present; then
  installer_bureau
else
  amorcer
fi
