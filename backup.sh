#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
pwDir=$( cd $(dirname $0) ; pwd -P )
tmpDir=$pwDir/tmp
mkdir -p $tmpDir
if [ ! -f "$1" ]; then
  echo "File $1 doesn't exist"
  echo "Usage: $(basename "$0") <full-path-to-conf-file>"
  exit 1
fi
{
  read
  while IFS=: read -r appName dataDir folderToBackup backupType lvmVG lvmLV; do
    dateTime=$(date +\%Y-\%m-\%d_\%H-\%M)
    archiveName=$HOSTNAME\_$appName\_$dateTime
    archivePath=$tmpDir/$archiveName
    lvmVGPath=/dev/$lvmVG
    lvmLVPath=$lvmVGPath/$lvmLV
    lvmLVSnapName=$lvmLV-snap
    lvmLVSnapPath=$lvmVGPath/$lvmLVSnapName
    lvmMountPath=/mnt/$lvmLV
    checkFolderExist () {
      if [ -n "$dataDir" -a ! -d "$dataDir/$appName" ]; then
        echo "Directory $dataDir/$appName doesn't exist"
        continue
      fi
    }
    createLVMSnap () {
      deleteLVMSnap
      if [ -n "$lvmVG" -a -n "$lvmLV" ]; then
        lvcreate -l 100%ORIGIN -s -n $lvmLVSnapName $lvmLVPath
        mkdir -p $lvmMountPath
        mount -r $lvmLVSnapPath $lvmMountPath
        dataDir=/mnt$dataDir
      fi
    }
    deleteLVMSnap () {
      if [ -n "$lvmVG" -a -n "$lvmLV" ]; then
        umount $lvmMountPath
        lvremove -f $lvmLVSnapPath
        rm -r $lvmMountPath
      fi
    }
    createArchive () {
      deleteArchive
      if [ $appName == mysql ]; then
        mysqldump -u root -h 127.0.0.1  --max_allowed_packet=2G --single-transaction --all-databases | gzip -9 > $archivePath.sql.gz
      fi
      cd $dataDir && tar -czf $archivePath.tar.gz $folderToBackup
      cd $tmpDir
    }
    deleteArchive () {
      rm $tmpDir/*$appName*.gz
    }
    copyToCloud () {
      aws s3 cp $tmpDir s3://$archiveAddress/$appName/ --recursive --exclude "*" --include "*$appName*.gz"
    }
    syncToCloud () {
      aws s3 sync $dataDir/$folderToBackup/ s3://$syncAddress/$folderToBackup/
    }
    checkFolderExist
    createLVMSnap
    if [ $backupType == archive ]; then
      createArchive
      copyToCloud
      deleteArchive
    fi
    if [ $backupType == sync ]; then
      syncToCloud
    fi
    deleteLVMSnap
  done
} < $1
