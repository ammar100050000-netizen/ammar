#!/bin/sh
# Zabour Router: repair login modal and LAN-only guest API, without changing any WAN settings.
set -eu
[ "$(id -u)" = 0 ] || { echo 'ERROR: SSH root needed'; exit 1; }
api=/www/cgi-bin/zabour-api
ui=/www/zabour/index.html
[ -f "$api" ] && [ -f "$ui" ] || { echo 'ERROR: Install Zabour first'; exit 1; }
[ "$(uci -q get network.lan.ipaddr || true)" = 192.168.1.1 ] || { echo 'ERROR: unexpected LAN IP, stopping'; exit 1; }
[ "$(uci -q get network.lan.netmask || true)" = 255.255.255.0 ] || { echo 'ERROR: unexpected LAN mask, stopping'; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'ERROR: jq missing'; exit 1; }
mkdir -p /etc/zabour/backups
chmod 700 /etc/zabour/backups
# Only repair from a known authenticated API; previous patch saved the original here.
if [ -f /etc/zabour/backups/zabour-api.with-login ]; then
  src=/etc/zabour/backups/zabour-api.with-login
else
  src="$api"
fi
grep -q 'HTTP_X_ZABOUR_TOKEN' "$src" || { echo 'ERROR: original API not found; no changes made'; exit 1; }
[ -f /etc/zabour/backups/zabour-api.with-login ] || cp -p "$src" /etc/zabour/backups/zabour-api.with-login
# Persistent backup of the currently deployed files, for an easy rollback.
cp -p "$api" /etc/zabour/backups/zabour-api.pre-repair
cp -p "$ui" /etc/zabour/backups/zabour-index.pre-repair
TMP=$(mktemp -d /tmp/zabour-fix.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
awk '
  /^\[ -s \/etc\/zabour\/token \] \|\| error / {next}
  /^read -r secret < \/etc\/zabour\/token$/ {next}
  index($0,"HTTP_X_ZABOUR_TOKEN") {
    print "# Accessible only from existing management LAN, do NOT expose WAN"
    print "case \"${REMOTE_ADDR:-}\" in"
    print "  127.0.0.1|::1|192.168.1.*) : ;;"
    print "  *) error '\''Forbidden: local LAN only'\'' ;;"
    print "esac"
    found=1
    next
  }
  {print}
  END {if(!found)exit 3}
' "$src" > "$TMP/api" || { echo 'ERROR: API modification failed'; exit 1; }
sh -n "$TMP/api" || { echo 'ERROR: API syntax invalid'; exit 1; }
cp "$ui" "$TMP/index.html"
sed -i "s@let token=localStorage.getItem('zabour_token')||''@let token='LAN-ONLY'@;s@let token='local-bypass'@let token='LAN-ONLY'@" "$TMP/index.html"
sed -i 's@</style></head>@</style><style>#login{display:none!important}</style></head>@' "$TMP/index.html"
sed -i 's@const j=await r.json();if(!j.ok)@const raw=await r.text();let j;try{j=JSON.parse(raw)}catch(e){throw Error("Zabour API HTTP "+r.status+": invalid JSON")}if(!j.ok)@' "$TMP/index.html"
grep -Fq "let token='LAN-ONLY'" "$TMP/index.html" || { echo 'ERROR: UI patch failed'; exit 1; }
grep -Fq '#login{display:none!important}' "$TMP/index.html" || { echo 'ERROR: UI hide failed'; exit 1; }
# Test CGI response as if invoked from management LAN; do not rely on network links yet.
REMOTE_ADDR=192.168.1.2 REQUEST_METHOD=GET QUERY_STRING=status sh "$TMP/api" > "$TMP/status.out" 2>"$TMP/status.err" || true
sed -n '/^{/,$p' "$TMP/status.out" | jq -e '.ok == true and (.lines | type == "array")' >/dev/null 2>&1 || {
  echo 'ERROR: Backend diagnostic failed; current files unchanged'
  head -c 400 "$TMP/status.err"; echo
  head -c 400 "$TMP/status.out"; echo
  exit 1
}
# Install after validation. No interface, firewall, xray, or mwan3 config is changed.
cp "$TMP/api" "$api"
cp "$TMP/index.html" "$ui"
cp "$TMP/index.html" /www/zabour/open.html
chmod 755 "$api"
/etc/init.d/uhttpd restart
printf '%s\n' 'ZABOUR REPAIRED: http://192.168.1.1/zabour/open.html?v=2' 'LAN-ONLY temporary access enabled; please restore password protection later.'
