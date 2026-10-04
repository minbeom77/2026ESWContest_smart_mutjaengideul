#!/bin/sh
set -eu
# /data units are not visible when systemd first builds the boot transaction.
systemctl daemon-reload
systemctl --no-block start safehub-mqtt.service safehub-csi.service safehub-ui.service
