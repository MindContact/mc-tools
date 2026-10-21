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
# avd: every AVD except $KEEP_AVD (default "lite"), which is created if missing.
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

# Machine-specific settings live in .env next to the script (see .env.example).
ENV_FILE="$(dirname "$(readlink -f "$0")")/.env"
# shellcheck disable=SC1090
[[ -f $ENV_FILE ]] && { set -a; source "$ENV_FILE"; set +a; }

SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}
AVDMANAGER=$SDK/cmdline-tools/latest/bin/avdmanager
KEEP_AVD=${KEEP_AVD:-lite}
KEEP_AVD_IMAGE=${KEEP_AVD_IMAGE:-"system-images;android-34;google_apis;x86_64"}

TARGETS=(gradle yay pacman avd claude-vm node pip dotnet maven pub playwright
         browser ide thumbnails journal docker flatpak)

declare -A DESC=(
  [gradle]="Gradle caches, wrapper and daemons"
  [yay]="AUR sources and builds"
  [pacman]="downloaded packages (sudo)"
  [avd]="Android AVDs except $KEEP_AVD"
  [claude-vm]="Claude desktop app VM (Cowork)"
  [node]="npm, pnpm, yarn, node-gyp, TypeScript"
  [pip]="pip cache"
  [dotnet]="NuGet packages"
  [maven]="local Maven repository"
  [pub]="Dart/Flutter packages"
  [playwright]="Playwright browsers"
  [browser]="Chrome and Firefox caches"
  [ide]="JetBrains, VS Code, Antigravity caches"
  [thumbnails]="image thumbnails"
  [journal]="system logs older than 2 weeks (sudo)"
  [docker]="build cache and dangling images"
  [flatpak]="unused flatpak runtimes"
)

# paths <target>: the directories a target clears, for sizing
paths() {
  case "$1" in
    gradle)     echo ~/.gradle/caches ~/.gradle/wrapper/dists ~/.gradle/daemon ;;
    yay)        echo ~/.cache/yay ;;
    pacman)     echo /var/cache/pacman/pkg ;;
    avd)        find ~/.android/avd -maxdepth 1 -name '*.avd' ! -name "$KEEP_AVD.avd" 2>/dev/null ;;
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
  echo "$2: in use, skipped (close it and retry)" >&2
}

list() {
  local total=0 b rows=()
  for t in "${TARGETS[@]}"; do
    b=$(bytes "$t" || true)
    # unknown sizes (-1) sort last
    rows+=("${b:--1} $t")
    total=$(( total + ${b:-0} ))
  done
  printf '%-11s %8s  %s\n' CACHE SIZE WHAT
  while read -r b t; do
    [[ $b == -1 ]] && b=""
    printf '%-11s %8s  %s\n' "$t" "$(human "$b")" "${DESC[$t]}"
  done < <(printf '%s\n' "${rows[@]}" | sort -k1,1nr)
  printf '%-11s %8s\n' total "$(human "$total")"
  echo
  echo "clean: $0 all  or  $0 <cache> [<cache>...]"
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
        [[ $name == "$KEEP_AVD" ]] && continue
        echo "  deleting $name"
        rm -rf ~/.android/avd/"$name".avd "$ini"
      done
      if [[ ! -e ~/.android/avd/$KEEP_AVD.ini ]]; then
        echo "  creating $KEEP_AVD ($KEEP_AVD_IMAGE, pixel_6, 2 GB)"
        echo no | "$AVDMANAGER" create avd -n "$KEEP_AVD" -k "$KEEP_AVD_IMAGE" -d pixel_6 >/dev/null
        local cfg=~/.android/avd/$KEEP_AVD.avd/config.ini
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
    [[ -n ${DESC[$t]:-} ]] || { echo "unknown: $t (run without arguments for the list)" >&2; exit 1; }
  done
fi

for t in "${selected[@]}"; do clean "$t"; done
echo "done"
