#!/bin/zsh
# Live reload: rebuilds, reinstalls and relaunches the app every time a source file changes.
# Leave it running in a terminal while you work; press Ctrl-C to stop.
set -uo pipefail

ROOT="${0:A:h:h}"
STAMP="$ROOT/.build/dev-stamp"
mkdir -p "$ROOT/.build"

reload() {
    touch "$STAMP"
    echo "\n— $(date +%H:%M:%S) rebuilding…"
    "$ROOT/scripts/build-app.sh" --install || echo "Build failed; fix the error and save again."
}

reload
echo "Watching Sources/ and scripts/make-icon.swift for changes…"
while true; do
    sleep 1
    # Anything saved since the last build?
    if [[ -n "$(find "$ROOT/Sources" "$ROOT/scripts/make-icon.swift" -newer "$STAMP" -type f -print -quit)" ]]; then
        sleep 0.3 # let editors finish writing
        reload
    fi
done
