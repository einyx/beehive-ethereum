#!/bin/bash

# Some global vars
CONFIGFILE="/opt/beehive/etc/compose/beehive.yml"
COMPOSEPATH="/opt/beehive/etc/compose"
RED="[0;31m"
GREEN="[0;32m"
WHITE="[0;0m"
BLUE="[0;34m"



# Update
function update () {
  echo "### Now checking for newer files in repository ..."
  git fetch --all
  REMOTESTAT=$(git status | grep -c "up-to-date")
  if [ "$REMOTESTAT" != "0" ];
    then
      echo "###### $BLUE""No updates found in repository.""$WHITE"
      return
  fi
  RESULT=$(git diff --name-only origin/master | grep update.sh)
  if [ "$RESULT" == "update.sh" ];
    then
      echo "###### $BLUE""Found newer version, will be pulling updates and restart self.""$WHITE"
      git reset --hard
      git pull --force
      exec "$1" "$2"
      exit 1
    else
      echo "###### $BLUE""Pulling updates from repository.""$WHITE"
      git reset --hard
      git pull --force
  fi
echo
}

# Stop beehive to avoid race conditions with running containers with regard to the current beehive config
function stop_beehive () {
echo "### Need to stop beehive ..."
echo -n "###### $BLUE Now stopping beehive.$WHITE "
systemctl stop beehive
for i in $(docker network ls | awk {'print $1'}); do docker network rm $i;done

# Let's load docker images in parallel
function dockerpull {
local composeFile="/opt/beehive/etc/compose/beehive.yml"
for name in $(cat $composeFile | grep -v '#' | grep image | cut -d'"' -f2 | uniq)
  do
    docker pull $name &
  done
wait
echo
}

function install () {
local PACKAGES="apache2-utils apparmor apt-transport-https aufs-tools bash-completion build-essential ca-certificates cgroupfs-mount cockpit cockpit-docker curl debconf-utils dialog dnsutils docker.io docker-compose dstat ethtool fail2ban genisoimage git glances grc html2text htop iptables iw jq libcrack2 libltdl7 lm-sensors man mosh multitail net-tools npm ntp openssh-server openssl pass prips software-properties-common syslinux psmisc pv python-pip unattended-upgrades unzip vim wireless-tools wpasupplicant"
echo "### Now upgrading packages ..."
dpkg --configure -a
apt-get -y autoclean
apt-get -y autoremove
apt-get update
apt-get -y install $PACKAGES

# Some updates require interactive attention, and the following settings will override that.
echo "docker.io docker.io/restart       boolean true" | debconf-set-selections -v
echo "debconf debconf/frontend select noninteractive" | debconf-set-selections -v
apt-get -y dist-upgrade -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes
dpkg --configure -a
npm install "https://github.com/taskrabbit/elasticsearch-dump" -g
pip install --upgrade pip
hash -r
pip install --upgrade elasticsearch-curator yq
wget https://github.com/bcicen/ctop/releases/download/v0.7.1/ctop-0.7.1-linux-amd64 -O /usr/bin/ctop && chmod +x /usr/bin/ctop
echo

echo "### Now replacing beehive related config files on host"
cp host/etc/systemd/* /etc/systemd/system/
cp host/etc/issue /etc/
systemctl daemon-reload
echo

# Ensure some defaults
echo "### Ensure some beehive defaults with regard to some folders, permissions and configs."
sed -i 's#ListenStream=9090#ListenStream=64294#' /lib/systemd/system/cockpit.socket
sed -i '/^port/Id' /etc/ssh/sshd_config
echo "Port 64295" >> /etc/ssh/sshd_config
echo

### Ensure creation of beehive related folders, just in case
mkdir -p /data/adbhoney/downloads /data/adbhoney/log \
         /data/ciscoasa/log \
         /data/conpot/log \
         /data/cowrie/log/tty/ /data/cowrie/downloads/ /data/cowrie/keys/ /data/cowrie/misc/ \
         /data/dionaea/log /data/dionaea/bistreams /data/dionaea/binaries /data/dionaea/rtp /data/dionaea/roots/ftp /data/dionaea/roots/tftp /data/dionaea/roots/www /data/dionaea/roots/upnp \
         /data/elasticpot/log \
         /data/elk/data /data/elk/log \
         /data/glastopf/log /data/glastopf/db \
         /data/honeytrap/log/ /data/honeytrap/attacks/ /data/honeytrap/downloads/ \
         /data/glutton/log \
         /data/heralding/log \
         /data/mailoney/log \
         /data/medpot/log \
         /data/nginx/log \
         /data/emobility/log \
         /data/ews/conf \
         /data/rdpy/log \
         /data/spiderfoot \
         /data/suricata/log /home/tsec/.ssh/ \
         /data/tanner/log /data/tanner/files \
         /data/p0f/log

### Let's take care of some files and permissions
chmod 760 -R /data
chown beehive:beehive -R /data
chmod 644 -R /data/nginx/conf
chmod 644 -R /data/nginx/cert

echo "### Now pulling latest docker images"
echo "######$BLUE This might take a while, please be patient!$WHITE"
dockerpull 2>&1>/dev/null

fuCHECK_VERSION
fuCONFIGCHECK
stop_beehive
fuBACKUP
update "$0" "$@"
install
