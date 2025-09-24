#!/data/data/com.termux/files/usr/bin/bash
# Auto M3U8 extractor & updater (mixed-mode, per-source summary, new-links tracking)

set -e

REPO_DIR="$HOME/M3u8-URL-Extractor-from-Live-Server"
MIRROR_DIR="$REPO_DIR/tmp_m3u"
ALL_LINKS="$REPO_DIR/IPTV.m3u"
LOG_FILE="$REPO_DIR/extract.log"
PREV_LINKS="$REPO_DIR/IPTV_prev.m3u"

RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
NC="\033[0m"

SOURCES=(
  "https://tvembed.net/"
  "https://oklivetv.com/"
  "https://iptvcat.com/"
  "https://wwitv.com/"
  "https://tvbox.ag/iptv/"
  "https://www.iptvsource.net/"
  "https://www.tvboxnow.com/iptv/"
  "https://freetviptv.net/streams/"
  "https://www.streamlive.to/"
  "http://51.15.2.221:8080/"
  "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/us_news.m3u"
  "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/gb_news.m3u"
)

mkdir -p "$MIRROR_DIR"
> "$ALL_LINKS"
> "$LOG_FILE"
declare -A SOURCE_COUNTS

# Backup previous playlist
if [ -f "$ALL_LINKS" ]; then
    cp "$ALL_LINKS" "$PREV_LINKS"
else
    > "$PREV_LINKS"
fi

echo "===================================" | tee -a "$LOG_FILE"
echo "Run started at $(date)" | tee -a "$LOG_FILE"
echo "===================================" | tee -a "$LOG_FILE"

for SITE in "${SOURCES[@]}"; do
    echo "[*] Processing $SITE ..." | tee -a "$LOG_FILE"
    TMP_FILE="$MIRROR_DIR/tmp_links.txt"
    > "$TMP_FILE"

    if [[ "$SITE" == *.m3u ]] || [[ "$SITE" == *.m3u8 ]]; then
        echo "  ↳ Direct playlist detected, fetching..." | tee -a "$LOG_FILE"
        curl -sL "$SITE" >> "$TMP_FILE"
        echo "✅ Direct playlist fetched" | tee -a "$LOG_FILE"
    else
        SITE_NAME=$(echo "$SITE" | sed 's~http[s]*://~~; s~/.*~~')
        SITE_DIR="$MIRROR_DIR/$SITE_NAME"

        httrack "$SITE" -O "$SITE_DIR" -q -%v0 -N0 -s0 -c1 -I0
        if [ $? -eq 0 ]; then
            grep -rho --include="*" 'http[^"]*\.m3u8[^"]*' "$SITE_DIR" >> "$TMP_FILE" || true
            echo "✅ Site mirrored successfully" | tee -a "$LOG_FILE"
        else
            echo "❌ Failed to mirror $SITE" | tee -a "$LOG_FILE"
        fi
    fi

    sort -u "$TMP_FILE" >> "$ALL_LINKS"
    COUNT=$(wc -l < "$TMP_FILE")
    SOURCE_COUNTS["$SITE"]=$COUNT
done

# Deduplicate overall playlist
sort -u "$ALL_LINKS" -o "$ALL_LINKS"

# New links tracking
NEW_COUNT=$(comm -23 <(sort "$ALL_LINKS") <(sort "$PREV_LINKS") | wc -l)
echo -e "\n✨ New links this run: $NEW_COUNT" | tee -a "$LOG_FILE"

# Per-source summary
echo -e "\n📊 Links contributed per source:" | tee -a "$LOG_FILE"
for SITE in "${!SOURCE_COUNTS[@]}"; do
    COUNT=${SOURCE_COUNTS[$SITE]}
    if [ "$COUNT" -eq 0 ]; then COLOR="$RED"
    elif [ "$COUNT" -lt 5 ]; then COLOR="$YELLOW"
    else COLOR="$GREEN"; fi
    echo -e "${COLOR}$SITE -> $COUNT links${NC}" | tee -a "$LOG_FILE"
done

# Git push
cd "$REPO_DIR"
git add IPTV.m3u || true

if git diff --cached --quiet; then
    echo -e "\nℹ️ No playlist changes to commit."
else
    git commit -m "Auto-update IPTV.m3u on $(date)"
    git push origin master || true
    echo -e "\n✅ Playlist updated and pushed at $(date)"
fi

