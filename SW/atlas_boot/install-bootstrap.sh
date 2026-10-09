#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# This bootstrap is for the hub, not the camera board's existing service.
test -f /opt/safehub-system/boot.sh
test -f /opt/safehub-csi/service/bridge.py
test -d /data/share/usr/atlas/apps/com.atlas.app.safehub_app
target=/etc/systemd/system/safehub-bootstrap.service
backup=/opt/safehub-system/backups
mkdir -p "$backup"
if [ -e "$target" ]; then
    cp -p "$target" "$backup/safehub-bootstrap.$(date +%Y%m%d%H%M%S).service"
fi
restore_readonly=0
case "$(awk '$2 == "/" { print $4 }' /proc/mounts)" in
    ro|ro,*) restore_readonly=1 ;;
esac
restore_mount() {
    if [ "$restore_readonly" = 1 ]; then
        sync
        mount -o remount,ro /
    fi
}
trap restore_mount EXIT
if [ "$restore_readonly" = 1 ]; then
    mount -o remount,rw /
fi
cp "$source_dir/safehub-bootstrap.service" "$target"
chmod 0644 "$target"
systemctl enable safehub-bootstrap.service
systemctl daemon-reload
# Do not start until after the root filesystem is read-only again.
