#!/bin/sh
# Zabour Router LAN-only login bypass; reversible, does not change WAN or mwan3.
set -eu

[ "$(id -u)" -eq 0 ] || { echo 'ERROR: SSH root required'; exit 1; }
api=/www/cgi-bin/zabour-api
ui=/www/zabour/index.html
[ -f "$api" ] && [ -f "$ui" ] || { echo 'ERROR: Zabour is not installed'; exit 1; }
lan_ip=$(uci -q get network.lan.ipaddr || true)
lan_mask=$(uci -q get network.lan.netmask || true)
[ "$lan_ip" = 192.168.1.1 ] && [ "$lan_mask" = 255.255.255.0 ] || {
  echo 'ERROR: Expected LAN 192.168.1.1/24; refusing to open access on an unknown subnet'; exit 1;
}
mkdir -p /etc/zabour/backups
chmod 700 /etc/zabour /etc/zabour/backups

if grep -q 'HTTP_X_ZABOUR_TOKEN' "$api"; then
  [ -f /etc/zabour/backups/zabour-api.with-login ] || cp -p "$api" /etc/zabour/backups/zabour-api.with-login
  [ -f /etc/zabour/backups/zabour-index.with-login ] || cp -p "$ui" /etc/zabour/backups/zabour-index.with-login
  tmp=$(mktemp /tmp/zabour-api.XXXXXX)
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  awk '
    index($0,"HTTP_X_ZABOUR_TOKEN") {
      print "# LAN-only access while login is temporarily disabled"
      print "case \"\u0024{REMOTE_ADDR:-}\" in"
      print "  127.0.0.1|::1|192.168.1.*) : ;;"
      print "  *) error '\''Zabour is accessible only from the local LAN'\'' ;;"
      print "esac"
      found=1
      next
    }
    {print}
    END {if (!found) exit 3}
  ' "$api" > "$tmp"
  chmod 755 "$tmp"
  cp "$tmp" "$api"
fi

if grep -Fq "let token=localStorage.getItem('zabour_token')||''" "$ui"; then
  sed -i "s@let token=localStorage.getItem('zabour_token')||''@let token='local-bypass'@" "$ui"
fi
if grep -Fq '<button class="btn danger" id="logout"' "$ui"; then
  sed -i 's@<button class="btn danger" id="logout"@<button style="display:none" class="btn danger" id="logout"@' "$ui"
fi

if grep -q 'HTTP_X_ZABOUR_TOKEN' "$api" || ! grep -Fq "let token='local-bypass'" "$ui"; then
  echo 'ERROR: patch not fully applied; restore backup manually'; exit 1
fi
/etc/init.d/uhttpd restart
printf '%s\n' 'ZABOUR LOGIN DISABLED (LAN 192.168.1.0/24 ONLY)' 'Open http://192.168.1.1/zabour/ and refresh the page.' 'Restore backups to require login again.'
