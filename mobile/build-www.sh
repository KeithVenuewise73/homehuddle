#!/usr/bin/env bash
# ============================================================================
# HomeHuddle mobile web assembler
# ----------------------------------------------------------------------------
# ASSEMBLE, DON'T REBUILD. This copies the EXISTING HomeHuddle web app into
# mobile/www (Capacitor's webDir) so the iOS binary ships the real UI verbatim.
# It forks nothing: /homehuddle, /shared, icons, and the service worker are
# copied as-is, then absolute https://venuewise.net/ links are rewritten to
# in-bundle relative paths so navigation stays inside the app (and off the
# live-web Stripe checkout path).
#
# Run from mobile/:  npm run build:web
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WWW="$HERE/www"

echo "→ Cleaning $WWW"
rm -rf "$WWW"
mkdir -p "$WWW"

echo "→ Copying HomeHuddle app (/homehuddle)"
cp -R "$REPO/homehuddle/." "$WWW/homehuddle/"

echo "→ Copying shared modules (/shared) + native bridge"
mkdir -p "$WWW/shared"
cp -R "$REPO/shared/." "$WWW/shared/"

echo "→ Copying root icons used by the app"
for f in icon-192.png icon-512.png; do
  [ -f "$REPO/$f" ] && cp "$REPO/$f" "$WWW/$f" || true
done
# NOTE: sw.js is intentionally NOT bundled. The web service worker is skipped in
# the native shell (WKWebView web-push doesn't work and a SW can serve stale app
# code across native updates). Native push uses APNs via VW.native.initPush().

echo "→ Copying legal pages so in-bundle Privacy/Terms links resolve"
for f in privacy.html terms.html homehuddle-privacy.html homehuddle-terms.html support.html; do
  [ -f "$REPO/$f" ] && cp "$REPO/$f" "$WWW/$f" || true
done

echo "→ Rewriting absolute venuewise.net links to in-bundle relative paths"
# Only touch bundled HTML. This keeps navigation inside the packaged app instead
# of bouncing to the live website (which would expose the web Stripe flow on iOS).
# Supabase endpoints (*.supabase.co) and mailto: links are untouched. Legal pages
# are bundled above, so their relative links resolve inside the app.
find "$WWW" -name '*.html' -print0 | xargs -0 sed -i \
  -e 's#https://venuewise\.net/#/#g'

echo "→ Wiring RevenueCat native config into the bundle"
# native.js reads window.VW_NATIVE_CONFIG, which lives in shared/native-config.js.
# That file is .gitignored (holds the publishable RevenueCat SDK key) and is
# created at build time. The SOURCE web HTML deliberately does NOT reference it
# (so venuewise.net never 404s on it); we inject the include ONLY into the
# bundled native HTML below.
if [ -f "$REPO/shared/native-config.js" ]; then
  echo "  ✓ using shared/native-config.js (real config present)"
else
  echo "  ⚠️  shared/native-config.js NOT found — using the PLACEHOLDER example."
  echo "  ⚠️  Set shared/native-config.js with the real RevenueCat public 'appl_' key"
  echo "  ⚠️  BEFORE a real build, or in-app purchases will not initialize."
  cp "$REPO/shared/native-config.example.js" "$WWW/shared/native-config.js"
fi

echo "→ Injecting native-config + app version before native.js (bundled HTML only)"
# Load order in the bundle becomes: native-config.js (sets VW_NATIVE_CONFIG) →
# native.js (reads it). VW_APP_VERSION labels client_errors.app_version.
find "$WWW" -name '*.html' -print0 | xargs -0 sed -i \
  -e "s#<script src=\"/shared/native\.js\"></script>#<script>window.VW_APP_VERSION='1.0.0';</script>\n  <script src=\"/shared/native-config.js\"></script>\n  <script src=\"/shared/native.js\"></script>#g"

echo "→ Writing native entry redirect (start at the calendar app)"
cat > "$WWW/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=/homehuddle/calendar.html">
<title>HomeHuddle</title></head>
<body><script>location.replace('/homehuddle/calendar.html');</script></body></html>
HTML

echo "✓ www assembled at $WWW"
echo "  Next (on macOS):  npx cap add ios  &&  npx cap sync ios  &&  npx cap open ios"
