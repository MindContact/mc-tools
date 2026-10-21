#!/usr/bin/env bash
# Lists and clears developer caches, the Android AVDs and the Claude VM.
#
#   ./clean-caches.sh                 lists every cache with its size, deletes nothing
#   ./clean-caches.sh all             clears everything listed
#   ./clean-caches.sh node pip ...    clears only the ones named
#
# Everything here is re-downloaded or rebuilt on demand; nothing is user data,
# except what was left inside the Claude VM. A target that would break a
# running program skips itself while that program runs.
#
# gradle: ~/.gradle caches, wrapper distributions and daemon logs; the next
#   build re-downloads dependencies and Gradle itself (slow, but safe).
# pacman: every cached package, installed or not (needs sudo).
# avd: every AVD except "lite", the only one kept; "lite" is created if missing.
# claude-vm: the Claude desktop VM (Cowork); the app downloads it again on next
#   use, and whatever was left inside it is lost.
# node: npm, pnpm and yarn caches, node-gyp headers, the TypeScript cache.
# pub: ~/.pub-cache — every Flutter project needs `flutter pub get` afterwards.
# browser / ide: Chrome, Firefox and JetBrains/VS Code caches, not profiles.
# journal: keeps the last two weeks of system logs (needs sudo).
# docker: build cache and dangling images only — never volumes or stopped
#   containers, which hold the local dev databases.
set -euo pipefail
# numfmt reads and writes decimals with the locale separator: docker prints
# "10.44GB", which an Italian locale would read as 1044 GB.
export LC_NUMERIC=C

SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/mnt/Work/lib/dev/android/sdk}}
AVDMANAGER=$SDK/cmdline-tools/latest/bin/avdmanager
LITE_IMAGE="system-images;android-34;google_apis;x86_64"

TARGETS=(gradle yay pacman avd claude-vm node pip dotnet maven pub playwright
         browser ide thumbnails journal docker flatpak)

declare -A DESC=(
  [gradle]="cache, wrapper e daemon di Gradle"
  [yay]="sorgenti e build AUR"
  [pacman]="pacchetti scaricati (sudo)"
  [avd]="AVD Android tranne lite"
  [claude-vm]="VM dell'app desktop Claude (Cowork)"
  [node]="npm, pnpm, yarn, node-gyp, TypeScript"
  [pip]="cache di pip"
  [dotnet]="pacchetti NuGet"
  [maven]="repository Maven locale"
  [pub]="pacchetti Dart/Flutter"
  [playwright]="browser di Playwright"
  [browser]="cache di Chrome e Firefox"
  [ide]="cache di JetBrains, VS Code, Antigravity"
  [thumbnails]="miniature delle immagini"
  [journal]="log di sistema oltre 2 settimane (sudo)"
  [docker]="build cache e immagini senza nome"
  [flatpak]="runtime flatpak inutilizzati"
)

# paths <target>: the directories a target clears, for sizing
paths() {
  case "$1" in
    gradle)     echo ~/.gradle/caches ~/.gradle/wrapper/dists ~/.gradle/daemon ;;
    yay)        echo ~/.cache/yay ;;
    pacman)     echo /var/cache/pacman/pkg ;;
    avd)        find ~/.android/avd -maxdepth 1 -name '*.avd' ! -name lite.avd 2>/dev/null ;;
    claude-vm)  echo ~/.config/Claude/vm_bundles ~/.config/Claude/claude-code-vm ;;
    node)       echo ~/.npm/_cacache ~/.cache/pnpm ~/.cache/yarn ~/.cache/node-gyp ~/.cache/typescript ;;
    pip)        echo ~/.cache/pip ;;
    dotnet)     echo ~/.nuget/packages ;;
    maven)      echo ~/.m2/repository ;;
    pub)        echo ~/.pub-cache ;;
    playwright) echo ~/.cache/ms-playwright ~/.cache/ms-playwright-go ;;
    browser)    echo ~/.cache/google-chrome ~/.cache/google-chrome-headless ~/.cache/mozilla ;;
    ide)        echo ~/.cache/JetBrains ~/.cache/Code ~/.cache/Antigravity* ~/.cache/electron ;;
    thumbnails) echo ~/.cache/thumbnails ;;
  esac
}

has() { command -v "$1" >/dev/null; }

# bytes <target>: what the target would free, in bytes; empty when unknown
bytes() {
  case "$1" in
    journal)
      journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]' | head -1 \
        | numfmt --from=iec 2>/dev/null ;;
    docker)
      has docker || return 0
      docker system df --format '{{.Type}}\t{{.Reclaimable}}' 2>/dev/null \
        | awk -F'\t' '$1=="Build Cache"{split($2,a," "); sub(/B$/,"",a[1]); print a[1]}' \
        | numfmt --from=si 2>/dev/null ;;
    flatpak) ;;
    *)
      local p; p=$(paths "$1")
      [[ -n $p ]] || { echo 0; return; }
      # shellcheck disable=SC2086
      { du -scb $p 2>/dev/null || true; } | tail -1 | cut -f1 ;;
  esac
}

human() { [[ -n $1 ]] && numfmt --to=iec --suffix=B "$1" || echo "?"; }

# running <pattern> <target>: true (and says so) while a matching process runs
running() {
  pgrep -f "$1" >/dev/null || return 1
  echo "$2: programma in uso, salto (chiudilo e riprova)" >&2
}

list() {
  local total=0 b rows=()
  for t in "${TARGETS[@]}"; do
    b=$(bytes "$t" || true)
    # unknown sizes (-1) sort last
    rows+=("${b:--1} $t")
    total=$(( total + ${b:-0} ))
  done
  printf '%-11s %8s  %s\n' CACHE SPAZIO COSA
  while read -r b t; do
    [[ $b == -1 ]] && b=""
    printf '%-11s %8s  %s\n' "$t" "$(human "$b")" "${DESC[$t]}"
  done < <(printf '%s\n' "${rows[@]}" | sort -k1,1nr)
  printf '%-11s %8s\n' totale "$(human "$total")"
  echo
  echo "pulisci: $0 all  oppure  $0 <cache> [<cache>...]"
}

clean() {
  local t=$1
  echo "$t: $(human "$(bytes "$t")")"
  case "$t" in
    gradle)
      # A build in progress has a client (wrapper or launcher); daemons alone
      # are idle leftovers of past builds and are stopped, not waited for.
      running 'GradleWrapperMain|gradle-launcher|GradleMain' gradle && return
      pkill -f 'GradleDaemon|KotlinCompileDaemon' || true
      sleep 2
      rm -rf ~/.gradle/caches ~/.gradle/wrapper/dists ~/.gradle/daemon ;;
    yay)
      rm -rf ~/.cache/yay ;;
    pacman)
      sudo paccache -rk0
      sudo paccache -ruk0 ;;
    avd)
      running qemu-system avd && return
      for ini in ~/.android/avd/*.ini; do
        [[ -e $ini ]] || continue
        name=$(basename "$ini" .ini)
        [[ $name == lite ]] && continue
        echo "  elimino $name"
        rm -rf ~/.android/avd/"$name".avd "$ini"
      done
      if [[ ! -e ~/.android/avd/lite.ini ]]; then
        echo "  creo lite ($LITE_IMAGE, pixel_6, 2 GB)"
        echo no | "$AVDMANAGER" create avd -n lite -k "$LITE_IMAGE" -d pixel_6 >/dev/null
        local cfg=~/.android/avd/lite.avd/config.ini
        sed -i 's/^hw.ramSize.*/hw.ramSize = 2048/' "$cfg"
        grep -q '^hw.ramSize' "$cfg" || echo 'hw.ramSize = 2048' >> "$cfg"
      fi ;;
    claude-vm)
      running '[/]Claude/.*electron|[Cc]laude-desktop' claude-vm && return
      rm -rf ~/.config/Claude/vm_bundles ~/.config/Claude/claude-code-vm ;;
    node)
      has npm && npm cache clean --force 2>/dev/null || true
      has pnpm && pnpm store prune >/dev/null 2>&1 || true
      has yarn && yarn cache clean >/dev/null 2>&1 || true
      rm -rf ~/.npm/_cacache ~/.cache/node-gyp ~/.cache/typescript ;;
    pip)
      has pip && pip cache purge >/dev/null 2>&1 || rm -rf ~/.cache/pip ;;
    dotnet)
      running 'dotnet ' dotnet && return
      has dotnet && dotnet nuget locals all --clear >/dev/null || rm -rf ~/.nuget/packages ;;
    maven)
      running 'org.codehaus.plexus.classworlds|mvn ' maven && return
      rm -rf ~/.m2/repository ;;
    pub)
      running 'flutter_tools|dart ' pub && return
      rm -rf ~/.pub-cache ;;
    playwright)
      rm -rf ~/.cache/ms-playwright ~/.cache/ms-playwright-go ;;
    browser)
      running '/opt/google/chrome|firefox' browser && return
      rm -rf ~/.cache/google-chrome ~/.cache/google-chrome-headless ~/.cache/mozilla ;;
    ide)
      running 'jetbrains|/code |/usr/lib/code|antigravity' ide && return
      rm -rf ~/.cache/JetBrains ~/.cache/Code ~/.cache/Antigravity* ~/.cache/electron ;;
    thumbnails)
      rm -rf ~/.cache/thumbnails ;;
    journal)
      sudo journalctl --vacuum-time=2weeks ;;
    docker)
      has docker || return 0
      docker builder prune -af
      docker image prune -f ;;
    flatpak)
      has flatpak || return 0
      flatpak uninstall --unused -y ;;
  esac
}

if [[ $# -eq 0 ]]; then list; exit 0; fi

if [[ $* == all ]]; then
  selected=("${TARGETS[@]}")
else
  selected=("$@")
  for t in "${selected[@]}"; do
    [[ -n ${DESC[$t]:-} ]] || { echo "sconosciuto: $t (lancia senza argomenti per l'elenco)" >&2; exit 1; }
  done
fi

for t in "${selected[@]}"; do clean "$t"; done
echo "fatto"
