#!/bin/sh
set -eu
# /data units are not visible when systemd first builds the boot transaction.
systemctl daemon-reload
systemctl --no-block start safehub-mqtt.service safehub-csi.service safehub-ui.service
# Optional local captions use /data units too; explicitly start them after reload.
# Hosts that use an external STT server need no local unit.
if [ -f /data/share/usr/lib/systemd/system/safehub-stt.service ]; then
    systemctl --no-block start safehub-stt.service
fi
