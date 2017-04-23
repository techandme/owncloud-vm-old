#!/bin/bash
#
## Tech and Me ## - ©2017, https://www.techandme.se/
#
# Tested on Ubuntu Server 14.04 & 16.04.
#

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

# Put your theme name here:
THEME_NAME=""

# Static values
STATIC="https://raw.githubusercontent.com/techandme/owncloud-vm/master/static"
DOWNLOADREPO="https://download.owncloud.org/community/testing"
SCRIPTS=/var/scripts
OCPATH=/var/www/owncloud
BACKUP=/var/OCBACKUP
HTML=/var/www
SECURE="$SCRIPTS/setup_secure_permissions_owncloud.sh"

# Must be root
[[ `id -u` -eq 0 ]] || { echo "Must be root to run script, in Ubuntu type: sudo -i"; exit 1; }

# Check if aptitude is installed
if [ $(dpkg-query -W -f='${Status}' aptitude 2>/dev/null | grep -c "ok installed") -eq 1 ]
then
    echo "Aptitude installed"
else
    apt install aptitude -y
fi

# System Upgrade
sudo apt update -q2
sudo aptitude full-upgrade -y
echo
echo "System is now upgraded, now the script will upgrade ownCloud."
echo "Which version do you want to upgrade to? Type it like this: '9.1.2RC1'"
read OCVERSION
curl -s $DOWNLOADREPO/owncloud-$OCVERSION.tar.bz2
if [ $? -eq 0 ]; then
    echo -e "\e[32m$OCVERSION exists!\e[0m"
    else
    echo
    echo "$OCVERSION doesn't exist. Please check available versions here:"
    echo "$DOWNLOADREPO"
    echo
    exit 1
fi
echo "Upgrading to $OCVERSION in 15 seconds... Press CTRL+C to abort."
echo "Disclamer: Tech and Me or ownCloud are not responsible for any dataloss."
echo "Config files are backed up to $BACKUP and $OCDATA aren't removed, but things could go wrong."
echo
sleep 15

# Backup data
echo "Backing up data..."
DATE=`date +%Y-%m-%d-%H%M%S`
if [ -d $BACKUP ]
then
    mkdir -p $BACKUP_OLD/$DATE
    mv $BACKUP/* $BACKUP_OLD/$DATE
    rm -R $BACKUP
    mkdir -p $BACKUP
fi
rsync -Aax $OCPATH/config $BACKUP
rsync -Aax $OCPATH/themes $BACKUP
rsync -Aax $OCPATH/apps $BACKUP
if [[ $? > 0 ]]
then
    echo "Backup was not OK. Please check $BACKUP and see if the folders are backed up properly"
    exit 1
else
    echo -e "\e[32m"
    echo "Backup OK!"
    echo -e "\e[0m"
fi
wget https://download.owncloud.org/community/testing/owncloud-$OCVERSION.tar.bz2 -P $HTML

if [ -f $HTML/owncloud-$OCVERSION.tar.bz2 ]
then
    echo "$HTML/owncloud-$OCVERSION.tar.bz2 exists"
else
    echo "Aborting,something went wrong with the download"
    exit 1
fi

if [ -d $BACKUP/config/ ]
then
    echo "$BACKUP/config/ exists"
else
    echo "Something went wrong with backing up your old ownCloud instance, please check in $BACKUP if config/ folder exist."
    exit 1
fi

if [ -d $BACKUP/themes/ ]
then
    echo "$BACKUP/themes/ exists"
else
    echo "Something went wrong with backing up your old ownCloud instance, please check in $BACKUP if themes/ folder exist."
    exit 1
fi

# Let the magic begin...
if [ -d $BACKUP/apps/ ]
then
    echo "$BACKUP/apps/ exists, removing old ownCloud instance in 5 seconds..." && sleep 5
    rm -rf $OCPATH
    tar -xjf $HTML/owncloud-$OCVERSION.tar.bz2 -C $HTML
    rm $HTML/owncloud-$OCVERSION.tar.bz2
    cp -R $BACKUP/themes $OCPATH/
    cp -R $BACKUP/config $OCPATH/
    cp -R $BACKUP/apps $OCPATH/
    bash $SECURE
    sudo -u www-data php $OCPATH/occ maintenance:mode --off
    sudo -u www-data php $OCPATH/occ upgrade
else
    echo "Something went wrong with backing up your old ownCloud instance, please check in $BACKUP if apps/ folders exist."
    exit 1
fi

# Change owner of $BACKUP folder to root
chown -R root:root $BACKUP

# Enable Apps
sudo -u www-data php $OCPATH/occ app:enable calendar
sudo -u www-data php $OCPATH/occ app:enable contacts
sudo -u www-data php $OCPATH/occ app:enable documents

# Increase max filesize (expects that changes are made in /etc/php5/apache2/php.ini)
# Here is a guide: https://www.techandme.se/increase-max-file-size/
VALUE="# php_value upload_max_filesize 513M"
if grep -Fxq "$VALUE" $OCPATH/.htaccess
then
    echo "Value correct"
else
    sed -i 's/  php_value upload_max_filesize 513M/# php_value upload_max_filesize 513M/g' $OCPATH/.htaccess
    sed -i 's/  php_value post_max_size 513M/# php_value post_max_size 513M/g' $OCPATH/.htaccess
    sed -i 's/  php_value memory_limit 512M/# php_value memory_limit 512M/g' $OCPATH/.htaccess
fi

# Set $THEME_NAME
VALUE2="$THEME_NAME"
if grep -Fxq "$VALUE2" "$OCPATH/config/config.php"
then
    echo "Theme correct"
else
    sed -i "s|'theme' => '',|'theme' => '$THEME_NAME',|g" $OCPATH/config/config.php
    echo "Theme set"
fi

# Set secure permissions
FILE="$SCRIPTS/setup_secure_permissions_owncloud.sh"
if [ -f $FILE ]
then
    echo "Script exists"
else
    mkdir -p $SCRIPTS
    wget -q $STATIC/setup_secure_permissions_owncloud.sh -P $SCRIPTS
    chmod +x $SCRIPTS/setup_secure_permissions_owncloud.sh
fi
sudo bash $SCRIPTS/setup_secure_permissions_owncloud.sh

# Repair
sudo -u www-data php $OCPATH/occ maintenance:repair

# Cleanup un-used packages
sudo apt autoremove -y
sudo apt autoclean

# Update GRUB, just in case
sudo update-grub

# Write to log
touch /var/log/cronjobs_success.log
echo "OW
LOUD UPDATE success-`date +"%Y%m%d"`" >> /var/log/cronjobs_success.log
echo
echo ownCloud version:
sudo -u www-data php $OCPATH/occ status
echo
echo

# Disable maintenance mode again just to be sure
sudo -u www-data php $OCPATH/occ maintenance:mode --off

## Un-hash this if you want the system to reboot
# sudo reboot

exit 0
