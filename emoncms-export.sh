#!/bin/bash

date=$(date +"%Y-%m-%d")

echo "=== Emoncms export start ==="
date
echo "Backup module version:"
cat /home/pi/backup/backup/module.json | grep version
echo "EUID: $EUID"
echo "Reading /home/pi/backup/config.cfg...."
if [ -f /home/pi/backup/config.cfg ]
then
    source /home/pi/backup/config.cfg
    echo "Location of mysql database: $mysql_path"
    echo "Location of emonhub.conf: $emonhub_config_path"
    echo "Location of Emoncms: $emoncms_location"
    echo "Backup destination: $backup_location"
else
    echo "ERROR: Backup /home/pi/backup/config.cfg file does not exist"
    exit 1
    sudo service feedwriter start > /dev/null
fi

#-----------------------------------------------------------------------------------------------
# Remove Old backup files
#-----------------------------------------------------------------------------------------------
if [ -f $backup_location/emoncms.sql ]
then
    sudo rm $backup_location/emoncms.sql
fi

if [ -f $backup_location/emoncms-backup-$date.tar ]
then
    sudo rm $backup_location/emoncms-backup-$date.tar
fi

#-----------------------------------------------------------------------------------------------
# Check emonPi / emonBase image version
#-----------------------------------------------------------------------------------------------
image_version=$(ls /boot | grep emonSD)
# Check first 16 characters of filename
image_date=${image_version:0:16}

if [[ "${image_version:0:6}" == "emonSD" ]]
then
    echo "Image version: $image_version"
fi

# Very old images (the ones shipped with kickstarter campaign) have "emonpi-28May2015"
if [[ -z $image_version ]] || [[ "$image_date" == "emonSD-17Jun2015" ]]
then
  image="old"
else
  image="new"
fi
#-----------------------------------------------------------------------------------------------

sudo service feedwriter stop

# Get MYSQL authentication details from settings.php
if [ -f /home/pi/backup/get_emoncms_mysql_auth.php ]; then
    auth=$(echo $emoncms_location | php /home/pi/backup/get_emoncms_mysql_auth.php php)
    IFS=":" read server username password <<< "$auth"
else
    echo "Error: cannot read MYSQL authentication details from Emoncms settings.php"
    echo "$PWD"
    sudo service feedwriter start > /dev/null
    exit 1
fi

# MYSQL Dump Emoncms database
if [ -n "$username" ]; then # if username string is not empty
    mysqldump -h$server -u$username -p$password emoncms > $backup_location/emoncms.sql
    if [ $? -ne 0 ]; then
        echo "Error: failed to export mysql data"
        echo "emoncms export failed"
        sudo service feedwriter start > /dev/null
        exit 1
    fi

else
    echo "Error: Cannot read MYSQL authentication details from Emoncms settings.php"
    sudo service feedwriter start > /dev/null
    exit 1
fi

echo "Emoncms MYSQL database dump complete, adding to archive..."

# Create backup archive and add config files stripping out the path
tar -cf $backup_location/emoncms-backup-$date.tar $backup_location/emoncms.sql $emonhub_config_path/emonhub.conf $emoncms_location/settings.php --transform 's?.*/??g' 2>&1
if [ $? -ne 0 ]; then
    echo "Error: failed to tar config data"
    echo "emoncms export failed"
    sudo service feedwriter start > /dev/null
    exit 1
fi

echo "Adding phpfina feed data to archive..."
# Append database folder to the archive with absolute path
tar -vr --file=$backup_location/emoncms-backup-$date.tar -C $mysql_path phpfina
echo "Adding phptimeseries feed data to archive..."
tar -vr --file=$backup_location/emoncms-backup-$date.tar -C $mysql_path phptimeseries

# Compress backup
echo "Compressing archive..."
gzip -fv $backup_location/emoncms-backup-$date.tar 2>&1
if [ $? -ne 0 ]; then
    echo "Error: failed to compress tar file"
    echo "emoncms export failed"
    sudo service feedwriter start > /dev/null
    exit 1
fi

sudo service feedwriter start > /dev/null

echo "Backup saved: $backup_location/emoncms-backup-$date.tar.gz"
date
echo "Export finished...refresh page to view download link"
echo "=== Emoncms export complete! ===" # This string is identified in the interface to stop ongoing AJAX calls, please ammend in interface if changed here
