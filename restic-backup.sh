#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/.env

cd ${SCRIPT_DIR}
git config --global --add safe.directory ${SCRIPT_DIR}
git pull

backupExitCode=0
date="date +%Y-%m-%dT%H:%M:%S%Z"

function unlockRepo () {
  echo "$($date): Unlock job: Begin"
  while [ "" != "$(${RESTIC_ROOT}/restic -q list locks --no-lock --no-cache)" ]; do
    sleep 5
    echo "$($date): Unlock job: Unlocking"
    ${RESTIC_ROOT}/restic -q unlock --cleanup-cache
  done
  echo "$($date): Unlock job: End"
}

function errorCheck () {
  if [ $backupExitCode -eq 1 ]; then
    echo "$($date): Unlock job: Begin. Checking repo."
    ${RESTIC_ROOT}/restic cache --cleanup --max-age 0
    ${RESTIC_ROOT}/restic check --read-data-subset=1%
    checkExitCode=$?
    if [ $checkExitCode -eq 1 ]; then
      echo "$($date): Unlock job: We found some errors. Rebuilding index."
      ${RESTIC_ROOT}/restic rebuild-index
      rebuildExitCode=$?
      if [ $rebuildExitCode -eq 1 ]; then
        echo "$($date): Unlock job: Repo might have fatal errors. Rebuilding index and reading all packs."
        ${RESTIC_ROOT}/restic rebuild-index --read-all-packs
        rebuildAllExitCode=$?
        if [ $rebuildAllExitCode -eq 1 ]; then
          echo "$($date): Unlock job: Fatal. Repo is dead."
          exit 0
        fi
      fi
    fi
  fi
}

function doBackup () {
  echo "$($date): Backup job: Begin"
  ${RESTIC_ROOT}/restic cache --cleanup --max-age 0
  ${RESTIC_ROOT}/restic backup -v --compression max --host=${HOSTNAME} --exclude-file=${RESTIC_EXCLUDE_FILE} --files-from=${RESTIC_INCLUDE_FILE} --cleanup-cache
  backupExitCode=$?
  if [ $backupExitCode -eq 1 ]; then
    errorCheck
  fi
  echo "$($date): Backup job: End"
  echo "$($date): Forget job: Begin"
  ${RESTIC_ROOT}/restic forget -v --compression max --prune -d ${PRUNE_DAYS} -w ${PRUNE_WEEKS} -m ${PRUNE_MONTHS} --host=${HOSTNAME} --group-by host --cleanup-cache
  echo "$($date): Forget job: End"
  return 0
}

dateStart=$(date '+%s')
echo "------------------------"
echo "$($date): Backup started"

unlockRepo
doBackup

echo "$($date): Chown job: Begin"
chown ${USERNAME}:${USERNAME} -R ${RESTIC_CACHE_DIR}
echo "$($date): Chown job: End"

# diff
dateEnd=$(date '+%s')
dateResult=$(date -d@$((dateEnd-dateStart)) -u '+%H:%M:%S')
echo "$($date): Backup ended in $dateResult"
echo "------------------------"
exit $?
