#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/.env

backupExitCode=0
date="date +%Y-%m-%dT%H:%M:%S%Z"

function unlockRepo () {
  echo "$($date): Unlock job: Begin"
  echo "------------------------"
  while [ "" != "$(${RESTIC_ROOT}/restic -q list locks --no-lock --no-cache)" ]; do
    echo "$($date): Unlock job: Unlocking"
    echo "------------------------"
    ${RESTIC_ROOT}/restic -q unlock --cleanup-cache
    sleep 5
  done
  echo "$($date): Unlock job: End"
  echo "------------------------"
}

function errorCheck () {
  if [ $backupExitCode -eq 1 ]; then
    echo "$($date): Unlock job: Begin. Checking repo."
    echo "------------------------"
    ${RESTIC_ROOT}/restic cache --cleanup --max-age 0
    ${RESTIC_ROOT}/restic check --read-data-subset=1%
    checkExitCode=$?
    if [ $checkExitCode -eq 1 ]; then
      echo "$($date): Unlock job: We found some errors. Rebuilding index."
      echo "------------------------"
      ${RESTIC_ROOT}/restic rebuild-index
      rebuildExitCode=$?
      if [ $rebuildExitCode -eq 1 ]; then
        echo "$($date): Unlock job: Repo might have fatal errors. Rebuilding index and reading all packs."
        echo "------------------------"
        ${RESTIC_ROOT}/restic rebuild-index --read-all-packs
        rebuildAllExitCode=$?
        if [ $rebuildAllExitCode -eq 1 ]; then
          echo "$($date): Unlock job: Fatal. Repo is dead."
          echo "------------------------"
          exit 0
        fi
      fi
    fi
  fi
}

function doBackup () {
  echo "$($date): Backup job: Begin"
  echo "------------------------"
  ${RESTIC_ROOT}/restic cache --cleanup --max-age 0
  ${RESTIC_ROOT}/restic backup -v --compression max --host=${HOSTNAME} --exclude-file=${RESTIC_EXCLUDE_FILE} --files-from=${RESTIC_INCLUDE_FILE} --cleanup-cache
  backupExitCode=$?
  if [ ! $backupExitCode -eq 0 ]; then
    errorCheck
  fi
  echo "$($date): Backup job: End"
  echo "------------------------"
  echo "$($date): Forget job: Begin"
  echo "------------------------"
  ${RESTIC_ROOT}/restic forget -v --compression max --prune -d ${PRUNE_DAYS} -w ${PRUNE_WEEKS} -m ${PRUNE_MONTHS} --host=${HOSTNAME} --group-by host --cleanup-cache
  echo "$($date): Forget job: End"
  echo "------------------------"
  return 0
}

dateStart=$(date '+%s')
echo "------------------------"
echo "------------------------"
echo "------------------------"
echo "$($date): Backup started"
echo "------------------------"

unlockRepo
doBackup

echo "$($date): Chown job: Begin"
echo "------------------------"
chown ${USERNAME}:${USERNAME} -R ${RESTIC_CACHE_DIR}
echo "$($date): Chown job: End"
echo "------------------------"

# diff
dateEnd=$(date '+%s')
dateResult=$(date -d@$((dateEnd-dateStart)) -u '+%H:%M:%S')
echo "$($date): Backup ended in $dateResult"
echo "------------------------"
echo "------------------------"
echo "------------------------"
exit $?
