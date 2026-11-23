#!/bin/sh
# Zabour v3 repair: CGI JSON, missing WAN interfaces, login overlay.
# No changes to network interfaces, firewall, mwan3 rules, or Xray.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo 'ERROR: run as root on OpenWrt'; exit 1; }
[ -f /etc/openwrt_release ] || { echo 'ERROR: OpenWrt required'; exit 1; }
[ -f /www/cgi-bin/zabour-api ] && [ -f /www/zabour/index.html ] || {
  echo 'ERROR: Zabour base package is not installed'; exit 1;
}
[ "$(uci -q get network.lan.ipaddr 2>/dev/null || true)" = 192.168.1.1 ] || {
  echo 'ERROR: LAN address differs from 192.168.1.1, refusing guest mode'; exit 1;
}
[ "$(uci -q get network.lan.netmask 2>/dev/null || true)" = 255.255.255.0 ] || {
  echo 'ERROR: LAN mask differs from /24, refusing guest mode'; exit 1;
}
for cmd in wget sha256sum jq ifstatus sh; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd"; exit 1; }
done
TMP=$(mktemp -d /tmp/zabour-v3.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BASE='https://raw.githubusercontent.com/ammar100050000-netizen/ammar/zabour-router-openwrt-v1/releases/v3'
wget -qO "$TMP/api" "$BASE/zabour-api" || { echo 'ERROR: API download failed'; exit 1; }
wget -qO "$TMP/ui" "$BASE/index.html" || { echo 'ERROR: UI download failed'; exit 1; }
(
  cd "$TMP"
  printf '%s  %s\n' '712811a5e73c5700935b9bf4320ab417ad9187c1f32050138464bfba782ebfc6' api | sha256sum -c -
  printf '%s  %s\n' '21fd0c99f6d132715d4a708874e582a7667c99da9867c459078820e28b91854b' ui | sha256sum -c -
) || { echo 'ERROR: downloaded files failed integrity check'; exit 1; }
sh -n "$TMP/api" || { echo 'ERROR: CGI syntax invalid'; exit 1; }
grep -Fq "let token='LAN-GUEST'" "$TMP/ui" || { echo 'ERROR: guest UI mismatch'; exit 1; }
grep -Fq '#login{display:none!important}' "$TMP/ui" || { echo 'ERROR: guest UI overlay still enabled'; exit 1; }
grep -Fq 'json_status()' "$TMP/api" || { echo 'ERROR: missing API status fix'; exit 1; }
# Self-test (no WAN2 required): each CGI response must be a JSON object.
REMOTE_ADDR=192.168.1.2 REQUEST_METHOD=GET QUERY_STRING=status sh "$TMP/api" > "$TMP/status" 2> "$TMP/stderr" || true
sed -n '/^{/,$p' "$TMP/status" | jq -e '.ok == true and (.lines|type == "array") and (.lines|length==2)' >/dev/null 2>&1 || {
  echo 'ERROR: local API self-test failed; no files installed'
  head -c 360 "$TMP/stderr"; echo
  head -c 360 "$TMP/status"; echo
  exit 1
}
REMOTE_ADDR=203.0.113.42 REQUEST_METHOD=GET QUERY_STRING=status sh "$TMP/api" > "$TMP/blocked" 2>/dev/null || true
sed -n '/^{/,$p' "$TMP/blocked" | jq -e '.ok == false and (.error | startswith("Forbidden"))' >/dev/null 2>&1 || {
  echo 'ERROR: API LAN restriction self-test failed; no files installed'; exit 1;
}
# Preserve exact deployed files for manual rollback.
mkdir -p /etc/zabour/backups
chmod 700 /etc/zabour/backups
cp -p /www/cgi-bin/zabour-api /etc/zabour/backups/zabour-api.pre-v3
cp -p /www/zabour/index.html /etc/zabour/backups/zabour-index.pre-v3
cp "$TMP/api" /www/cgi-bin/zabour-api
chmod 755 /www/cgi-bin/zabour-api
cp "$TMP/ui" /www/zabour/index.html
cp "$TMP/ui" /www/zabour/open.html
chmod 644 /www/zabour/index.html /www/zabour/open.html
# NoobWRT defaults to wwan0; an old placeholder 'wan' doesn't exist on this router.
if [ "$(uci -q get zabour.global.wan1 2>/dev/null || true)" = wan ] && \
   ! uci -q get network.wan >/dev/null 2>&1 && \
   uci -q get network.wwan0 >/dev/null 2>&1; then
  uci set zabour.global.wan1=wwan0
  uci commit zabour
fi
/etc/init.d/uhttpd restart
printf '%s\n' 'ZABOUR V3 READY' 'Open: http://192.168.1.1/zabour/open.html?v=3' 'Temporary guest access allowed on 192.168.1.0/24 only.'
