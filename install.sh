#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

[ -f "${SCRIPT_DIR}/.env" ] || exit 1

source ${SCRIPT_DIR}/.env

OS_type="$(uname -m)"
case "$OS_type" in
  x86_64|amd64)
    OS_type='amd64'
    ;;
  aarch64|arm64)
    OS_type='arm64'
    ;;
  arm*)
    OS_type='arm'
    ;;
  *)
    echo 'OS type not supported'
    exit 2
    ;;
esac

rm ${SCRIPT_DIR}/restic
curl -L https://github.com/restic/restic/releases/download/v$VERSION/restic_"$VERSION"_linux_$OS_type.bz2 --output ${SCRIPT_DIR}/restic.bz2
bzip2 -f -d ${SCRIPT_DIR}/restic.bz2

sudo chmod ug+x ${RESTIC_ROOT}/restic
sudo chmod ug+x ${RESTIC_ROOT}/restic-backup.sh

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

sudo systemctl disable --now restic-backup.timer

sudo rm /etc/systemd/system/restic-backup.service
sudo rm /etc/systemd/system/restic-backup.timer

sudo systemctl daemon-reload

sudo ln -s $HOME/.restic/restic-backup.service /etc/systemd/system/restic-backup.service
sudo ln -s $HOME/.restic/restic-backup.timer /etc/systemd/system/restic-backup.timer

sudo chown ${USERNAME}:${USERNAME} -R ${SCRIPT_DIR}

sudo systemctl daemon-reload

sudo systemctl enable --now restic-backup.timer

${RESTIC_ROOT}/restic init --repository-version latest