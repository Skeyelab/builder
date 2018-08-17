#!/bin/sh

exec 2> /var/log/rc.local.log # send stderr from rc.local to a log file
exec 1>&2

set -x
set -e

DATA_DIR=/opt/data

# Delete "pi" user and create another one
useradd -m %PI_USERNAME% -G sudo || true
echo "%PI_USERNAME%:%PI_PASSWORD%" | chpasswd
install -d -m 700 /home/%PI_USERNAME%/.ssh
mv /id_rsa.pub /home/%PI_USERNAME%/.ssh/authorized_keys
chown %PI_USERNAME%:%PI_USERNAME% -Rf /home/%PI_USERNAME%/.ssh/

echo "%PI_USERNAME% ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_%PI_USERNAME%-nopasswd

rm /etc/sudoers.d/010_pi-nopasswd
deluser -remove-home pi

# Change user and group ID
usermod -u 1000 %PI_USERNAME%
groupmod -g 1000 %PI_USERNAME%

# Configure hostname
randomWord1=$(shuf ${DATA_DIR}/words.txt -n 1 | sed -e "s/\s/-/g")
randomWord2=$(shuf ${DATA_DIR}/words.txt -n 1 | sed -e "s/\s/-/g")
PI_CONFIG_HOSTNAME="%PI_HOSTNAME%-${randomWord1}-${randomWord2}"

echo "${PI_CONFIG_HOSTNAME}" > "/etc/hostname"
OLD_HOST="raspberrypi"
sed -i "s/$OLD_HOST/$PI_CONFIG_HOSTNAME/g" "/etc/hosts"
/etc/init.d/hostname.sh

# Configure the memory split
if test "%PI_GPU_MEMORY%" = "16" || test "%PI_GPU_MEMORY%" = "32" || test "%PI_GPU_MEMORY%" = "64" || test "%PI_GPU_MEMORY%" = "128" || test "%PI_GPU_MEMORY%" = "256"; then
  echo "gpu_mem=%PI_GPU_MEMORY%" >> /boot/config.txt
fi

# Configure static IP address
apt-get -qq update
apt-get install -y python-dev python-pip
pip install netifaces

export TARGET_IP="target_ip"
export NETWORK_CONFIG="/etc/network/interfaces"
export PI_IP_ADDRESS_RANGE_START="%PI_IP_ADDRESS_RANGE_START%"
export PI_IP_ADDRESS_RANGE_END="%PI_IP_ADDRESS_RANGE_END%"
export PI_DNS_ADDRESS="%PI_DNS_ADDRESS%"
python /interfaces.py

cat /etc/network/interfaces
rm /interfaces.py
pip uninstall -y netifaces
apt-get remove -y python-dev python-pip

PI_IP_ADDRESS=$(cat ./target_ip)
rm ./target_ip

# Remove DHCPCD5 - https://www.raspberrypi.org/forums/viewtopic.php?t=111709
apt-get remove -y dhcpcd5

# Install Docker
if "%PI_INSTALL_DOCKER%" -eq "true"; then
  curl -sSL https://get.docker.com | CHANNEL=stable sh
  usermod -aG docker %PI_USERNAME%
fi

# Send email telling about this server
if test "%PI_MAILGUN_API_KEY%" && test "%PI_MAILGUN_DOMAIN%" && test "%PI_EMAIL_ADDRESS%"; then
  curl -s --user "api:%PI_MAILGUN_API_KEY%" \
    https://api.mailgun.net/v3/%PI_MAILGUN_DOMAIN%/messages \
    -F from="%PI_USERNAME%@%PI_MAILGUN_DOMAIN%" \
    -F to=%PI_EMAIL_ADDRESS% \
    -F subject="New Raspberry Pi (${PI_CONFIG_HOSTNAME}) set up" \
    -F text="New %PI_USERNAME%@${PI_CONFIG_HOSTNAME} setup on: ${PI_IP_ADDRESS}"
fi

apt-get install -y mlocate supervisor transmission-daemon
updatedb
systemctl stop transmission-daemon

echo '{
    "alt-speed-down": 50,
    "alt-speed-enabled": false,
    "alt-speed-time-begin": 540,
    "alt-speed-time-day": 127,
    "alt-speed-time-enabled": false,
    "alt-speed-time-end": 1020,
    "alt-speed-up": 50,
    "bind-address-ipv4": "0.0.0.0",
    "bind-address-ipv6": "::",
    "blocklist-enabled": true,
    "blocklist-url": "http://john.bitsurge.net/public/biglist.p2p.gz",
    "cache-size-mb": 4,
    "dht-enabled": true,
    "download-dir": "/var/lib/transmission-daemon/downloads",
    "download-limit": 100,
    "download-limit-enabled": 0,
    "download-queue-enabled": true,
    "download-queue-size": 2,
    "encryption": 2,
    "idle-seeding-limit": 30,
    "idle-seeding-limit-enabled": false,
    "incomplete-dir": "/var/lib/transmission-daemon/downloads",
    "incomplete-dir-enabled": false,
    "lpd-enabled": true,
    "max-peers-global": 200,
    "message-level": 1,
    "peer-congestion-algorithm": "",
    "peer-id-ttl-hours": 6,
    "peer-limit-global": 200,
    "peer-limit-per-torrent": 50,
    "peer-port": 51413,
    "peer-port-random-high": 65535,
    "peer-port-random-low": 49152,
    "peer-port-random-on-start": true,
    "peer-socket-tos": "default",
    "pex-enabled": true,
    "port-forwarding-enabled": true,
    "preallocation": 1,
    "prefetch-enabled": true,
    "queue-stalled-enabled": true,
    "queue-stalled-minutes": 30,
    "ratio-limit": 2,
    "ratio-limit-enabled": false,
    "rename-partial-files": true,
    "rpc-authentication-required": true,
    "rpc-bind-address": "0.0.0.0",
    "rpc-enabled": true,
    "rpc-host-whitelist": "",
    "rpc-host-whitelist-enabled": true,
    "rpc-password": "transmission",
    "rpc-port": 9091,
    "rpc-url": "/transmission/",
    "rpc-username": "transmission",
    "rpc-whitelist": "*.*.*.*",
    "rpc-whitelist-enabled": false,
    "scrape-paused-torrents-enabled": true,
    "script-torrent-done-enabled": false,
    "script-torrent-done-filename": "",
    "seed-queue-enabled": false,
    "seed-queue-size": 10,
    "speed-limit-down": 100,
    "speed-limit-down-enabled": false,
    "speed-limit-up": 100,
    "speed-limit-up-enabled": false,
    "start-added-torrents": true,
    "trash-original-torrent-files": false,
    "umask": 18,
    "upload-limit": 100,
    "upload-limit-enabled": 0,
    "upload-slots-per-torrent": 14,
    "utp-enabled": true
}' > /etc/transmission-daemon/settings.json

systemctl start transmission-daemon

rm -Rf ${DATA_DIR}

rm -- "$0"

echo "Deleted current script"
