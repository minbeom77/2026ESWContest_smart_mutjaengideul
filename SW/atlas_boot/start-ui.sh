#!/bin/sh
set -eu

app_id=com.atlas.app.safehub_app
app_status() {
    busctl --system --timeout=10 call com.atlas.AppManager1 \
        /com/atlas/AppManager1 com.atlas.AppManager1 GetStatus s "$1"
}
is_running() {
    app_status "$1" 2>/dev/null | grep -q '"state" s "Running"'
}

# Let the platform finish opening its home screen before bringing SafeHub up.
attempt=0
while [ "$attempt" -lt 60 ]; do
    if is_running com.atlas.app.home; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
sleep 3
busctl --system --timeout=15 call com.atlas.AppManager1 \
    /com/atlas/AppManager1 com.atlas.AppManager1 Start s "$app_id"

# Recover a stopped/crashed app, without stealing focus from a running app.
while sleep 15; do
    if ! is_running "$app_id"; then
        busctl --system --timeout=15 call com.atlas.AppManager1 \
            /com/atlas/AppManager1 com.atlas.AppManager1 Start s "$app_id"
    fi
done
