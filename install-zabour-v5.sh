#!/bin/sh
# One-time SSH migration from Zabour V4 to permanent in-app updates.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
[ "$(id -u)" -eq 0 ] && [ -f /etc/openwrt_release ] || { echo 'ERROR: run as root on OpenWrt'; exit 1; }
[ -f /www/zabour/index.html ] && [ -f /www/cgi-bin/zabour-api ] || { echo 'ERROR: Install Zabour first'; exit 1; }
for cmd in wget sha256sum jq mktemp; do command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd"; exit 1; }; done
work=$(mktemp -d /tmp/zabour-bootstrap.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
wget -qO "$work/updater" --timeout=30 https://raw.githubusercontent.com/ammar100050000-netizen/ammar/zabour-router-openwrt-v1/releases/v5.0.0/updater || { echo 'ERROR: Download failed'; exit 1; }
printf '%s  %s\n' '4e28933d770e9fcc1826c99e31534ce57562d4ca8c8001ea239e36aa589b10b3' "$work/updater" | sha256sum -c - || { echo 'ERROR: Installer SHA256 mismatch'; exit 1; }
sh -n "$work/updater" || { echo 'ERROR: Invalid updater'; exit 1; }
mkdir -p /etc/zabour/backups
chmod 700 /etc/zabour /etc/zabour/backups
if [ -f /usr/bin/zabour-update ]; then cp -p /usr/bin/zabour-update /etc/zabour/backups/updater-before-v5; fi
cp "$work/updater" /usr/bin/zabour-update.new
chmod 755 /usr/bin/zabour-update.new
mv -f /usr/bin/zabour-update.new /usr/bin/zabour-update
[ -f /etc/zabour/version ] || printf '%s\n' '4.0.0' > /etc/zabour/version
/usr/bin/zabour-update apply
echo 'ZABOUR V5 INSTALLED; future updates: Services > Zabour > Settings > Update'
echo 'Direct: http://192.168.1.1/zabour/open.html?v=5.0.0'
