#!/bin/bash

##################
# I. Global vars #
##################
RED="\e[31m"
GREEN="\e[32m"
NULL="\e[0m"
BACKTITLE="beehive-Installer"

PROGRESSBOXCONF=" --backtitle "$BACKTITLE" --progressbox 24 80"

SITES="https://hub.docker.com https://gitlab.com"

beehiveCOMPOSE="/opt/beehive-ethereumetc/compose/standard.yml"

LSB_STABLE_SUPPORTED="ubuntu"

REMOTESITES="https://hub.docker.com https://gitlab.com"

PREINSTALLPACKAGES="aria2 apache2-utils curl dialog figlet grc libcrack2 libpq-dev lsb-release net-tools software-properties-common toilet"

INSTALLPACKAGES="aria2 apache2-utils apparmor apt-transport-https aufs-tools bash-completion build-essential ca-certificates cgroupfs-mount cockpit cockpit-docker console-setup console-setup-linux curl debconf-utils dialog dnsutils docker.io docker-compose dstat ethtool fail2ban figlet genisoimage git glances grc haveged html2text htop iptables iw jq kbd libcrack2 libltdl7 man mosh multitail net-tools npm ntp openssh-server openssl pass prips software-properties-common syslinux psmisc pv python-pip toilet unattended-upgrades unzip vim wget"


UPDATECHECK="apt-get::Periodic::Update-Package-Lists \"1\";
apt-get::Periodic::Download-Upgradeable-Packages \"0\";
apt-get::Periodic::AutocleanInterval \"7\";
"

SYSCTLCONF="
# Reboot after kernel panic, check via /proc/sys/kernel/panic[_on_oops]
# Set required map count for ELK
kernel.panic = 1
kernel.panic_on_oops = 1
vm.max_map_count = 262144
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
"

FAIL2BANCONF="[DEFAULT]
ignore-ip = 127.0.0.1/8
bantime = 3600
findtime = 600
maxretry = 5

[nginx-http-auth]
enabled  = true
filter   = nginx-http-auth
port     = 64297
logpath  = /data/nginx/log/error.log

[pam-generic]
enabled = true
port    = 64294
filter  = pam-generic
logpath = /var/log/auth.log

[sshd]
enabled = true
port    = 64295
filter  = sshd
logpath = /var/log/auth.log
"
SYSTEMDFIX="[Link]
NamePolicy=kernel database onboard slot path
MACAddressPolicy=none
"
COCKPIT_SOCKET="[Socket]
ListenStream=
ListenStream=64294
"
SSHPORT="
Port 64295
"
CRONJOBS="
# Check if updated images are available and download them
27 1 * * *      root    docker-compose -f /opt/beehive-ethereumetc/beehive.yml pull

# Delete elasticsearch logstash indices older than 90 days
27 4 * * *      root    curator --config /opt/beehive-ethereumetc/curator/curator.yml /opt/beehive-ethereumetc/curator/actions.yml

# Uploaded binaries are not supposed to be downloaded
*/1 * * * *     root    mv --backup=numbered /data/dionaea/roots/ftp/* /data/dionaea/binaries/

# Daily reboot
27 3 * * *      root    systemctl stop beehive && docker stop \$(docker ps -aq) || docker rm \$(docker ps -aq) || reboot

# Check for updated packages every sunday, upgrade and reboot
27 16 * * 0     root    apt-get autoclean -y && apt-get autoremove -y && apt-get update -y && apt-get upgrade -y && sleep 10 && reboot
"
ROOTPROMPT='PS1="\[\033[38;5;8m\][\[$(tput sgr0)\]\[\033[38;5;1m\]\u\[$(tput sgr0)\]\[\033[38;5;6m\]@\[$(tput sgr0)\]\[\033[38;5;4m\]\h\[$(tput sgr0)\]\[\033[38;5;6m\]:\[$(tput sgr0)\]\[\033[38;5;5m\]\w\[$(tput sgr0)\]\[\033[38;5;8m\]]\[$(tput sgr0)\]\[\033[38;5;1m\]\\$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"'
USERPROMPT='PS1="\[\033[38;5;8m\][\[$(tput sgr0)\]\[\033[38;5;2m\]\u\[$(tput sgr0)\]\[\033[38;5;6m\]@\[$(tput sgr0)\]\[\033[38;5;4m\]\h\[$(tput sgr0)\]\[\033[38;5;6m\]:\[$(tput sgr0)\]\[\033[38;5;5m\]\w\[$(tput sgr0)\]\[\033[38;5;8m\]]\[$(tput sgr0)\]\[\033[38;5;2m\]\\$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"'
ROOTCOLORS="export LS_OPTIONS='--color=auto'
eval \"\`dircolors\`\"
alias ls='ls \$LS_OPTIONS'
alias ll='ls \$LS_OPTIONS -l'
alias l='ls \$LS_OPTIONS -lA'"


#################
# II. Functions #
#################

# Create funny words for hostnames
function RANDOMWORD {
  local WORDFILE="$1"
  local LINES=$(cat $WORDFILE | wc -l)
  local RANDOM=$((RANDOM % $LINES))
  local NUM=$((RANDOM * RANDOM % $LINES + 1))
  echo -e -n $(sed -n "$NUM p" $WORDFILE | tr -d \' | tr A-Z a-z)
}

# Do we have root?
function GOT_ROOT {
echo -e
echo -e -n "### Checking for root: "
if [ "$(whoami)" != "root" ];
  then
    echo -e "[ NOT OK ]"
    echo -e "### Please run as root."
    echo -e "### Example: sudo $0"
    exit
  else
    echo -e "${GREEN}✓${NULL} [ ${GREEN} OK ${NULL} ]"
fi
}

# Check for pre-installer package requirements.
# If not present install them
function CHECKPACKAGES {
  export DEBIAN_FRONTEND=noninteractive
  # Make sure dependencies for apt-get are installed
  CURL=$(which curl)
  WGET=$(which wget)
  if [ "$CURL" == "" ] || [ "$WGET" == "" ]
    then
      echo -e "${GREEN}✓${NULL} [ ${GREEN} Installing deps for apt-get ${NULL} ]\n"
      apt-get-get -y update
      apt-get-get -y install curl wget
  fi
  echo -e "${GREEN}✓${NULL} [${GREEN} Checking for installer dependencies: ${NULL}]"
  local PACKAGES="$1"
  for DEPS in $PACKAGES;
    do
      OK=$(dpkg -s $DEPS 2>&1 | grep -w ok | awk '{ print $3 }' | head -n 1)
      if [ "$OK" != "ok" ];
        then
          echo -e "${GREEN}✓${NULL} [${GREEN} Now installing... ${NULL}]"
          apt-get update -y
          apt-get install -y $PACKAGES
          break
      fi
  done
  if [ "$OK" = "ok" ];
    then
      echo -e "${GREEN}✓${NULL} [ ${GREEN} OK ${NULL} ]"
  fi
}

# Check if remote sites are available
function CHECKNET {
      local SITES="$1"
      SITESCOUNT=$(echo -e $SITES | wc -w)
      j=0
      for i in $SITES;
        do
          curl --connect-timeout 30 -IsS $i 2>&1>/dev/null
          if [ $? -ne 0 ];then
            exit
          else
              break
          fi
        done
}

# Check for other services
function CHECK_PORTS {
if [ "$beehive_DEPLOYMENT_TYPE" == "user" ];
  then
    echo -e
    echo -e "### Checking for active services."
    echo -e
    grc netstat -tulpen
    echo -e
    echo -e "### Please review your running services."
    echo -e "### We will take care of SSH (22), but other services i.e. FTP (21), TELNET (23), SMTP (25), HTTP (80), HTTPS (443), etc."
    echo -e "### might collide with beehive's honeypots and prevent beehive from starting successfully."
    echo -e
    echo -e "Sleeping 5 second, then carrying on..."
    sleep 5
    echo -e "Ok lets do this!"
fi
}

############################
# III. Pre-Installer phase #
############################
GOT_ROOT
CHECKPACKAGES "$PREINSTALLPACKAGES"



# Prepare running the installer
echo -e "$INFO" | head -n 3
CHECK_PORTS


#######################################
# V. Installer user interaction phase #
#######################################

# Set TERM
export TERM=linux

# Check if remote sites are available
CHECKNET "$REMOTESITES"


dialog --clear

##########################
# VI. Installation phase #
##########################

exec 2> >(tee "/install.err")
exec > >(tee "/install.log")

echo -e "${GREEN}✓${NULL}"  "Installing ..."
export DEBIAN_FRONTEND=noninteractive
echo -e "${GREEN}✓${NULL}"  "[ ${GREEN} Getting update information. ${NULL} ]"
echo -e
apt-get -y update
echo -e
echo -e "${GREEN}✓${NULL}"  "[ ${GREEN} Upgrading packages. ${NULL} ]"
echo -e
# Downlaod and upgrade packages, but silently keep existing configs
echo -e "docker.io docker.io/restart       boolean true" | debconf-set-selections -v
echo -e "debconf debconf/frontend select noninteractive" | debconf-set-selections -v
apt-get -y dist-upgrade -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes
echo -e
echo -e "${GREEN}✓${NULL}"  "[ ${GREEN} Installing dependencies. ${NULL} ]"
echo -e
apt-get -y install $INSTALLPACKAGES

# Remove exim4
apt-get -y purge exim4-base mailutils
apt-get -y autoremove
apt-mark hold exim4-base mailutils

# Lets make sure SSH roaming is turned off (CVE-2016-0777, CVE-2016-0778)
echo -e "${GREEN}✓${NULL}"  "SSH roaming off"
echo -e "UseRoaming no" | tee -a /etc/ssh/ssh_config

# Installing elasticdump, yq
echo -e "${GREEN}✓${NULL}"  "Installing pkgs"
npm install https://github.com/taskrabbit/elasticsearch-dump -g
pip install --upgrade pip
hash -r
pip install elasticsearch-curator yq

echo -e "${GREEN}✓${NULL}"  "Create user"
addgroup --gid 2000 beehive
adduser --system --no-create-home --uid 2000 --disabled-password --disabled-login --gid 2000 beehive

# Lets set the hostname
a=$(RANDOMWORD /opt/beehive-ethereumhost/usr/share/dict/a.txt)
n=$(RANDOMWORD /opt/beehive-ethereumhost/usr/share/dict/n.txt)
HOST=$a$n
echo -e "${GREEN}✓${NULL}"  "Set hostname"
hostnamectl set-hostname $HOST
sed -i 's#127.0.1.1.*#127.0.1.1\t'"$HOST"'#g' /etc/hosts

# Lets patch cockpit.socket, sshd_config
echo -e "${GREEN}✓${NULL}"  "Adjust ports"
mkdir -p /etc/systemd/system/cockpit.socket.d
echo -e "$COCKPIT_SOCKET" | tee /etc/systemd/system/cockpit.socket.d/listen.conf
sed -i '/^port/Id' /etc/ssh/sshd_config
echo -e "$SSHPORT" | tee -a /etc/ssh/sshd_config

# Do not allow root login for cockpit
sed -i '2i\auth requisite pam_succeed_if.so uid >= 1000' /etc/pam.d/cockpit

# Lets make sure only CONF_beehive_FLAVOR images will be downloaded and started
case $CONF_beehive_FLAVOR in
  STANDARD)
    echo -e "${GREEN}✓${NULL}"  "STANDARD"
    ln -s /opt/beehive-ethereumetc/compose/standard.yml $beehiveCOMPOSE
  ;;
esac

# Lets load docker images in parallel
function PULLIMAGES {
for name in $(cat $beehiveCOMPOSE | grep -v '#' | grep image | cut -d'"' -f2 | uniq)
  do
    docker pull $name &
done
}

# Lets add the daily update check with a weekly clean interval
echo -e "${GREEN}✓${NULL}"  "Modify checks"
echo -e "$UPDATECHECK" | tee /etc/apt-get/apt-get.conf.d/10periodic

# Lets make sure to reboot the system after a kernel panic
echo -e "${GREEN}✓${NULL}"  "Tweak sysctl"
echo -e "$SYSCTLCONF" | tee -a /etc/sysctl.conf

# Lets setup fail2ban config
echo -e "${GREEN}✓${NULL}"  "Setup fail2ban"
echo -e "$FAIL2BANCONF" | tee /etc/fail2ban/jail.d/beehive.conf

# Fix systemd error https://github.com/systemd/systemd/issues/3374
echo -e "${GREEN}✓${NULL}"  "Systemd fix"
echo -e "$SYSTEMDFIX" | tee /etc/systemd/network/99-default.link

# Lets add some cronjobs
echo -e "${GREEN}✓${NULL}"  "Add cronjobs"
echo -e "$CRONJOBS" | tee -a /etc/crontab

# Lets create some files and folders
echo -e "${GREEN}✓${NULL}"  "Files & folders"
mkdir -p /data/cowrie/log/tty/ /data/cowrie/downloads/ /data/cowrie/keys/ /data/cowrie/misc/ \
        /data/elk/data /data/elk/log \
        /data/ews/conf \
        /data/suricata/log /root/.ssh/ 
touch /data/spiderfoot/spiderfoot.db
touch /data/nginx/log/error.log

# Lets copy some files
echo -e "${GREEN}✓${NULL}"  "Copy configs"
tar xvfz /opt/beehive-etherum/etc/objects/elkbase.tgz -C /
cp /opt/beehive-ethereumhost/etc/systemd/* /etc/systemd/system/
systemctl enable beehive

# Lets take care of some files and permissions
echo -e "${GREEN}✓${NULL}"  "Permissions"
chmod 760 -R /data
chown beehive:beehive -R /data
chmod 644 -R /data/nginx/conf
chmod 644 -R /data/nginx/cert

# Lets replace "quiet splash" options, set a console font for more screen canvas and update grub
echo -e "${GREEN}✓${NULL}"  "Options"
sed -i 's#GRUB_CMDLINE_LINUX_DEFAULT="quiet"#GRUB_CMDLINE_LINUX_DEFAULT="quiet consoleblank=0"#' /etc/default/grub
sed -i 's#GRUB_CMDLINE_LINUX=""#GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"#' /etc/default/grub
update-grub

# Lets enable a color prompt and add /opt/beehive-ethereumbin to path
echo -e "${GREEN}✓${NULL}"  "Setup prompt"
tee -a /root/.bashrc <<EOF
$ROOTPROMPT
$ROOTCOLORS
PATH="$PATH:/opt/beehive-ethereumbin"
EOF
for i in $(ls -d /home/*/)
  do
tee -a $i.bashrc <<EOF
$USERPROMPT
PATH="$PATH:/opt/beehive-ethereumbin"
EOF
done

# Lets create ews.ip before reboot and prevent race condition for first start
echo -e "${GREEN}✓${NULL}"  "Update IP"
/opt/beehive-ethereumbin/updateip.sh

# Lets clean up apt-get
echo -e "${GREEN}✓${NULL}"  "Clean up"
apt-get autoclean -y
apt-get autoremove -y

# Final steps
cp /opt/beehive-ethereumhost/etc/rc.local /etc/rc.local && \
rm -rf /root/installer && \
rm -rf /etc/issue.d/cockpit.issue && \
rm -rf /etc/motd.d/cockpit && \
rm -rf /etc/issue.net && \
rm -rf /etc/motd && \
systemctl restart console-setup.service


# Lets generate a SSL self-signed certificate without interaction (browsers will see it invalid anyway)

echo -e "${GREEN}✓${NULL}"  "NGINX Certificate"
mkdir -p /data/nginx/cert
openssl req \
        -nodes \
        -x509 \
        -sha512 \
        -newkey rsa:8192 \
        -keyout "/data/nginx/cert/nginx.key" \
        -out "/data/nginx/cert/nginx.crt" \
        -days 3650 \
        -subj '/C=AU/ST=Some-State/O=Internet Widgits Pty Ltd'

echo -e "${GREEN}✓${NULL}"  "Pull images"
PULLIMAGES


echo -e "${GREEN}✓${NULL}"  "Rebooting ..."
sleep 2

