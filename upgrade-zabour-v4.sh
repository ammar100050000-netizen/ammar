#!/bin/sh
# Zabour v4 - update UI, CGI, LuCI menu, and online updater.
# No WAN, firewall, mwan3, or Xray routing changes.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] && [ -f /etc/openwrt_release ] || { echo 'ERROR: OpenWrt root required'; exit 1; }
[ -f /www/cgi-bin/zabour-api ] && [ -f /www/zabour/index.html ] || { echo 'ERROR: Zabour v3 required'; exit 1; }
for cmd in wget jq sha256sum uci ifstatus; do command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd"; exit 1; }; done
TMP=$(mktemp -d /tmp/zabour-v4.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BASE=https://raw.githubusercontent.com/ammar100050000-netizen/ammar/zabour-router-openwrt-v1/releases/v4
wget -qO "$TMP/api" "$BASE/zabour-api" || { echo 'ERROR: API download failed'; exit 1; }
wget -qO "$TMP/ui" "$BASE/index.html" || { echo 'ERROR: UI download failed'; exit 1; }
[ "$(wc -c < "$TMP/api")" -gt 7000 ] && [ "$(wc -c < "$TMP/ui")" -gt 25000 ] || { echo 'ERROR: incomplete download'; exit 1; }
sh -n "$TMP/api" || { echo 'ERROR: invalid CGI shell'; exit 1; }
grep -Fq 'update_check)' "$TMP/api" && grep -Fq 'VLESS' "$TMP/ui" && grep -Fq 'checkZabourUpdate' "$TMP/ui" || { echo 'ERROR: wrong release'; exit 1; }
# Test JSON and LAN restriction before replacing current API.
REMOTE_ADDR=192.168.1.2 REQUEST_METHOD=GET QUERY_STRING=status sh "$TMP/api" > "$TMP/status" 2>"$TMP/err" || true
sed -n '/^{/,$p' "$TMP/status" | jq -e '.ok == true and (.lines|length)==2' >/dev/null 2>&1 || { echo 'ERROR: API status test failed'; head -c 400 "$TMP/err"; exit 1; }
REMOTE_ADDR=203.0.113.5 REQUEST_METHOD=GET QUERY_STRING=status sh "$TMP/api" > "$TMP/blocked" 2>/dev/null || true
sed -n '/^{/,$p' "$TMP/blocked" | jq -e '.ok==false' >/dev/null 2>&1 || { echo 'ERROR: LAN access test failed'; exit 1; }
REMOTE_ADDR=192.168.1.2 REQUEST_METHOD=GET QUERY_STRING=version sh "$TMP/api" > "$TMP/version" 2>/dev/null || true
sed -n '/^{/,$p' "$TMP/version" | jq -e '.ok==true and .version=="4.0.0"' >/dev/null 2>&1 || { echo 'ERROR: version test failed'; exit 1; }
mkdir -p /etc/zabour/backups /usr/share/luci/menu.d /www/luci-static/resources/view/zabour
chmod 700 /etc/zabour/backups
cp -p /www/cgi-bin/zabour-api /etc/zabour/backups/api-before-v4
cp -p /www/zabour/index.html /etc/zabour/backups/ui-before-v4
# LuCI menu entry, using the native JS view mechanism of OpenWrt 24.10.
cat > "$TMP/menu.json" <<'EOF'
{
  "admin/services/zabour": {
    "title": "Zabour",
    "order": 70,
    "action": {"type": "view", "path": "zabour/index"}
  }
}
EOF
jq -e '."admin/services/zabour".action.type=="view"' "$TMP/menu.json" >/dev/null
cat > "$TMP/luci.js" <<'EOF'
'use strict';
'require view';
return view.extend({
  render: function () {
    return E('iframe', {
      src: '/zabour/open.html?v=4',
      style: 'width:100%;height:85vh;min-height:650px;border:0;background:#090e1b'
    });
  }
});
EOF
cat > "$TMP/updater" <<'EOF'
#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || exit 1
latest=$(wget -qO - --timeout=10 https://raw.githubusercontent.com/ammar100050000-netizen/ammar/zabour-router-openwrt-v1/releases/latest-version.txt | tr -d '\r\n')
case "$latest" in ''|*[!0-9.]*) echo 'ERROR: invalid update version'; exit 1;; esac
[ "$latest" != 4.0.0 ] || { echo 'Zabour 4.0.0 is already up to date'; exit 0; }
work=$(mktemp -d /tmp/zabour-updater.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
url="https://raw.githubusercontent.com/ammar100050000-netizen/ammar/zabour-router-openwrt-v1/releases/v$latest/upgrade.sh"
wget -qO "$work/upgrade.sh" --timeout=15 "$url" || { echo 'ERROR: update package not published'; exit 1; }
[ "$(wc -c < "$work/upgrade.sh")" -gt 100 ] || { echo 'ERROR: empty update'; exit 1; }
sh -n "$work/upgrade.sh" || { echo 'ERROR: invalid update script'; exit 1; }
sh "$work/upgrade.sh"
EOF
sh -n "$TMP/updater" || { echo 'ERROR: updater syntax'; exit 1; }
cp "$TMP/api" /www/cgi-bin/zabour-api
chmod 755 /www/cgi-bin/zabour-api
cp "$TMP/ui" /www/zabour/index.html
cp "$TMP/ui" /www/zabour/open.html
chmod 644 /www/zabour/index.html /www/zabour/open.html
cp "$TMP/menu.json" /usr/share/luci/menu.d/luci-app-zabour.json
cp "$TMP/luci.js" /www/luci-static/resources/view/zabour/index.js
cp "$TMP/updater" /usr/bin/zabour-update
chmod 755 /usr/bin/zabour-update
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/uhttpd restart
echo 'ZABOUR V4 READY'
echo 'LuCI: Services > Zabour'
echo 'Direct: http://192.168.1.1/zabour/open.html?v=4'
echo 'LAN-only guest access remains enabled: restore authentication before exposing other devices.'
