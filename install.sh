#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/.env

sudo chmod +x ${RESTIC_ROOT}/restic
sudo chmod +x ${RESTIC_ROOT}/restic-backup.sh

cat <<EOF > ${RESTIC_ROOT}/restic-backup.service
[Unit]
Description=Restic backup

[Service]
Type=simple
ExecStart=${RESTIC_ROOT}/restic-backup.sh

Nice=19
IOSchedulingClass=2
IOSchedulingPriority=7
EOF

sudo systemctl disable --now restic-backup*

sudo rm /etc/systemd/system/restic-backup*

sudo ln -s $HOME/.restic/restic-backup.service /etc/systemd/system/restic-backup.service
sudo ln -s $HOME/.restic/restic-backup.timer /etc/systemd/system/restic-backup.timer

sudo systemctl daemon-reload

sudo systemctl enable --now restic-backup.timer

${RESTIC_ROOT}/restic init --repository-version latest