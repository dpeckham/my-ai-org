#!/usr/bin/env bash
# Create the company's GitHub App bot (once), install it, and give its
# credentials to Paperclip. Idempotent: install.sh runs it every time, and it
# only does what is missing.
#
#   scripts/github-apps.sh [--name NAME] [--org ORG] [--no-install]
#
# One App acts for every reviewing role (Product Manager, Lead Engineer, UI
# Designer, QA Lead, Security, CTO); the Coder acts as the operator's own
# account. That split is what makes reviews meaningful: GitHub never lets a
# PR's author approve it.
#
# GitHub allows no unattended App creation, so this takes two clicks:
#   1. "Create GitHub App" -- uses the App manifest flow: a local page posts the
#      App's definition to GitHub, you confirm, GitHub redirects back here with
#      a one-time code, and the code is exchanged for the App's private key.
#      Nothing to copy or paste.
#   2. "Install" -- choose "All repositories" so future project repos are
#      covered without coming back here. Repos in an org need a separate
#      install there, by an owner of that org.
#
# The key is stored in ~/.config/my-ai-org/github-app/ (mode 600, outside the
# repo), so a rebuild reuses it, and as Paperclip secrets bound to the
# reviewing agents by paperclip-org.sh and newproject.sh.

set -euo pipefail
shopt -s inherit_errexit

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HOME/.config/my-ai-org/github-app"
NAME=""; ORG=""; INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:?}"; shift 2 ;;
    --org) ORG="${2:?}"; shift 2 ;;
    --no-install) INSTALL=0; shift ;;
    *) echo "Usage: $0 [--name NAME] [--org ORG] [--no-install]"; exit 1 ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }
. "$HERE/lib/paperclip.sh"

for c in gh python3 openssl curl jq; do command -v "$c" >/dev/null || die "$c is required"; done
gh auth status >/dev/null 2>&1 || die "gh is not signed in (gh auth login)"
LOGIN=$(gh api user -q .login)
NAME="${NAME:-$LOGIN-bot}"
(( ${#NAME} <= 34 )) || die "App names are limited to 34 characters: $NAME"
open_url() { (xdg-open "$1" || open "$1") >/dev/null 2>&1 || true; echo "    $1"; }

# ------------------------------------------------------------------ create
step "GitHub App"
install -d -m 700 "$STATE"
if [[ -s "$STATE/app.json" && -s "$STATE/private-key.pem" ]]; then
  info "exists: $(jq -r '.slug' "$STATE/app.json") (app id $(jq -r '.id' "$STATE/app.json"))"
else
  [[ -t 0 ]] || die "creating the App needs a browser click; run this in an interactive terminal"
  info "Creating '$NAME'. A browser tab opens; click \"Create GitHub App\" there."
  # Permissions: contents:write is not for pushing code. GitHub leaves an
  # App's review out of the PR's review decision without it, so approvals
  # would post but never count. checks/actions/statuses are all needed to read
  # CI state; security_events and vulnerability_alerts are for Security and
  # the CTO.
  python3 - "$NAME" "$ORG" "$STATE" "https://github.com/$LOGIN" <<'PY'
import html, json, os, secrets, sys, threading, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

name, org, state_dir, home_url = sys.argv[1:5]
state = secrets.token_urlsafe(24)
result = {}
perms = {"contents": "write", "pull_requests": "write", "issues": "write",
         "checks": "read", "actions": "read", "statuses": "read", "metadata": "read",
         "security_events": "read", "vulnerability_alerts": "read"}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def page(self, code, body):
        self.send_response(code); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers(); self.wfile.write(body.encode())
    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == "/":
            manifest = {"name": name, "url": home_url, "public": False,
                        "redirect_url": f"http://127.0.0.1:{port}/callback",
                        "default_events": [], "default_permissions": perms}
            target = (f"https://github.com/organizations/{org}/settings/apps/new" if org
                      else "https://github.com/settings/apps/new") + f"?state={state}"
            self.page(200, f"""<!doctype html><title>Create {html.escape(name)}</title>
<form id=f method=post action="{html.escape(target, quote=True)}">
<input type=hidden name=manifest value="{html.escape(json.dumps(manifest), quote=True)}">
<p>Sending the App definition to GitHub... <button>Continue</button></p></form>
<script>document.getElementById('f').submit()</script>""")
        elif u.path == "/callback":
            if q.get("state", [""])[0] != state or "code" not in q:
                self.page(400, "<p>Unexpected callback (state mismatch). Close this tab and re-run.</p>"); return
            req = urllib.request.Request(
                f"https://api.github.com/app-manifests/{q['code'][0]}/conversions", method="POST", data=b"",
                headers={"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28",
                         "User-Agent": "my-ai-org-github-apps"})
            try:
                with urllib.request.urlopen(req, timeout=30) as r: app = json.loads(r.read())
            except Exception as e:
                result["error"] = str(e); self.page(500, f"<p>Conversion failed: {html.escape(str(e))}</p>")
            else:
                os.umask(0o077)
                with open(os.path.join(state_dir, "private-key.pem"), "w") as f: f.write(app["pem"])
                keep = {k: app.get(k) for k in ("id", "slug", "client_id", "html_url", "name")}
                keep["owner"] = (app.get("owner") or {}).get("login")
                with open(os.path.join(state_dir, "app.json"), "w") as f: json.dump(keep, f, indent=2)
                result["app"] = keep
                self.page(200, f"<p>Created <b>{html.escape(app['slug'])}</b>. You can close this tab and return to the terminal.</p>")
            threading.Thread(target=srv.shutdown).start()
        else:
            self.page(404, "")

srv = HTTPServer(("127.0.0.1", 0), H); port = srv.server_address[1]
url = f"http://127.0.0.1:{port}/"
print(f"    If no tab opens, visit {url}", flush=True)
webbrowser.open(url)
# Daemon, or Python waits out the full 10 minutes at exit even after success.
timer = threading.Timer(600, srv.shutdown); timer.daemon = True; timer.start()
srv.serve_forever()
timer.cancel()
if "app" not in result:
    sys.exit("    !! no App was created (" + result.get("error", "timed out after 10 minutes") + ")")
print(f"    created {result['app']['slug']} (app id {result['app']['id']})")
PY
fi
APP_ID=$(jq -r .id "$STATE/app.json"); SLUG=$(jq -r .slug "$STATE/app.json")

# ------------------------------------------------------------------ install
# Read installations with an App JWT (same signing as gh-bot).
app_jwt() {
  local now h p s
  now=$(date +%s)
  h=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  p=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$APP_ID" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  s=$(printf '%s.%s' "$h" "$p" | openssl dgst -sha256 -binary -sign "$STATE/private-key.pem" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  printf '%s.%s.%s' "$h" "$p" "$s"
}
installations() {
  curl -fsS -H "Authorization: Bearer $(app_jwt)" -H "Accept: application/vnd.github+json" \
    https://api.github.com/app/installations | jq -r '.[] | "\(.account.login) (\(.repository_selection))"'
}
step "Installations"
inst=$(installations)
if [[ -n "$inst" ]]; then
  printf '%s\n' "$inst" | sed 's/^/    installed on /'
elif [[ $INSTALL -eq 1 && -t 0 ]]; then
  info "Not installed anywhere yet. Choose \"All repositories\" on the page that opens, then Install."
  open_url "https://github.com/apps/$SLUG/installations/new"
  read -r -p "    Press Enter once you've installed it... " _
  inst=$(installations)
  [[ -n "$inst" ]] && printf '%s\n' "$inst" | sed 's/^/    installed on /' || info "still no installation; re-run this script after installing"
else
  info "not installed anywhere; install it at https://github.com/apps/$SLUG/installations/new"
fi
info "repos in an org you don't own need that org's owner to install: https://github.com/apps/$SLUG/installations/new"

# ------------------------------------------------------- Paperclip secrets
step "Paperclip secrets"
if ! curl -fsS -o /dev/null "$PAPERCLIP/api/health" 2>/dev/null; then
  info "Paperclip not reachable; skipped (install.sh runs this again after Paperclip is up)"
  exit 0
fi
companies=$(api GET /companies)
[[ "$(jq length <<<"$companies")" -eq 1 ]] || { info "no single company yet; skipped (paperclip-org.sh creates it)"; exit 0; }
CID=$(jq -r '.[0].id' <<<"$companies")
put_secret() {  # put_secret NAME VALUE DESCRIPTION
  local id; id=$(secret_id "$CID" "$1")
  if [[ -n "$id" ]]; then
    local cur_ok=0
    # Rotate only when the value changed, so re-runs don't pile up versions.
    [[ "$(cat "$STATE/.$1.sha" 2>/dev/null)" == "$(sha "$2")" ]] && cur_ok=1
    if [[ $cur_ok -eq 0 ]]; then
      api POST "/secrets/$id/rotate" "$(jq -n --arg v "$2" '{value: $v}')" >/dev/null
      info "$1: rotated"
    else
      info "$1: current"
    fi
  else
    api POST "/companies/$CID/secrets" "$(jq -n --arg n "$1" --arg v "$2" --arg d "$3" \
      '{name: $n, value: $v, description: $d}')" >/dev/null
    info "$1: created"
  fi
  ( umask 077; sha "$2" > "$STATE/.$1.sha" )
}
put_secret github-bot-app-id "$APP_ID" "GitHub App id of the company bot ($SLUG). Set by github-apps.sh."
put_secret github-bot-private-key "$(cat "$STATE/private-key.pem")" "Private key of the company bot ($SLUG). Set by github-apps.sh."
info "bound on the reviewing agents by paperclip-org.sh and newproject.sh"
