#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source ${SCRIPT_DIR}/.env

cd ${SCRIPT_DIR}
git config --global --add safe.directory ${SCRIPT_DIR}
git pull

chown ${USERNAME}:${USERNAME} -R ${SCRIPT_DIR}

# reduce memory usage
export GOGC=10
export GOMAXPROCS=2

backupExitCode=0
date="date +%Y-%m-%dT%H:%M:%S%Z"

function unlockJob () {
  echo "$($date): Unlock job: Begin"
  while [ "" != "$(${RESTIC_ROOT}/restic -q list locks --no-lock --no-cache)" ]; do
    sleep 5
    echo "$($date): Unlock job: Unlocking"
    ${RESTIC_ROOT}/restic -q unlock
  done
  echo "$($date): Unlock job: End"
}

function checkJob () {
  if [ $backupExitCode -eq 1 ]; then
    echo "$($date): Check job: Begin. Checking repo."
    ${RESTIC_ROOT}/restic cache --cleanup --max-age 0
    ${RESTIC_ROOT}/restic --verbose=${VERBOSE_LEVEL} check --read-data-subset=1%
    checkExitCode=$?
    if [ $checkExitCode -eq 1 ]; then
      echo "$($date): Check job: We found some errors. Rebuilding index."
      ${RESTIC_ROOT}/restic --verbose=${VERBOSE_LEVEL} rebuild-index
      rebuildExitCode=$?
      if [ $rebuildExitCode -eq 1 ]; then
        echo "$($date): Check job: Repo might have fatal errors. Rebuilding index and reading all packs."
        ${RESTIC_ROOT}/restic --verbose=${VERBOSE_LEVEL} rebuild-index --read-all-packs
        rebuildAllExitCode=$?
        if [ $rebuildAllExitCode -eq 1 ]; then
          echo "$($date): Check job: Fatal. Repo is dead."
          exit 0
        fi
      fi
    fi
  fi
}

function backupJob () {
  echo "$($date): Backup job: Begin"
  ${RESTIC_ROOT}/restic backup --verbose=${VERBOSE_LEVEL} --compression ${COMPRESSION_LEVEL} --host=${HOSTNAME} --exclude-file=${RESTIC_EXCLUDE_FILE} --files-from=${RESTIC_INCLUDE_FILE}
  backupExitCode=$?
  if [ $backupExitCode -eq 1 ]; then
    checkJob
  fi
  echo "$($date): Backup job: End"
  return 0
}

function forgetJob () {
  echo "$($date): Forget job: Begin"
  ${RESTIC_ROOT}/restic forget --verbose=${VERBOSE_LEVEL} --compression ${COMPRESSION_LEVEL} -d ${PRUNE_DAYS} -w ${PRUNE_WEEKS} -m ${PRUNE_MONTHS} --host=${HOSTNAME} --group-by host
  echo "$($date): Forget job: End"
  return 0
}

function pruneJob () {
  echo "$($date): Prune job: Begin"
  ${RESTIC_ROOT}/restic prune --verbose=${VERBOSE_LEVEL} --group-by host
  echo "$($date): Prune job: End"
  return 0
}

dateStart=$(date '+%s')
echo "------------------------"
echo "$($date): Backup started"

${RESTIC_ROOT}/restic cache --cleanup

unlockJob
backupJob

unlockJob
forgetJob

if [ "${DO_PRUNE}" -eq 1 ]; then
  unlockJob
  pruneJob
fi

echo "$($date): Chown job: Begin"
chown ${USERNAME}:${USERNAME} -R ${RESTIC_CACHE_DIR}
echo "$($date): Chown job: End"

# diff
dateEnd=$(date '+%s')
dateResult=$(date -d@$((dateEnd-dateStart)) -u '+%H:%M:%S')
echo "$($date): Backup ended in $dateResult"
echo "------------------------"
exit $?
