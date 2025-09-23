#!/data/data/com.termux/files/usr/bin/bash
# IPTV Extractor Script (HTTrack multi-source, Termux-friendly, logging + failure tracking + color summary + new link tracking)

cd "$(dirname "$0")" || exit 1

OUTPUT_FILE="IPTV.m3u"
PREV_FILE="IPTV_prev.m3u"
TMP_DIR="tmp_m3u"
LOG_FILE="extract.log"
FAIL_FILE="failures.txt"
MAX_FAILS=3

# Color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m" # No Color

# Initialize temp folder
mkdir -p "$TMP_DIR"
rm -rf "$TMP_DIR"/*

# Load previous failure counts
declare -A FAILURES
if [ -f "$FAIL_FILE" ]; then
    while IFS="=" read -r src count; do
        FAILURES["$src"]=$count
    done < "$FAIL_FILE"
fi

# Sources to scrape
SOURCES=(
    "http://iboxbd.live/"
    "https://streamtest.in/"
    "https://tonkiang.us/"
    # Add more sources here
)

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
ALL_LINKS="$TMP_DIR/all_m3u8.txt"
> "$ALL_LINKS"

# Initialize counters
TOTAL_SOURCES=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# --- Run header in log ---
{
    echo "========================="
    echo "Run started at $(date)"
    echo "Sources to attempt: ${#SOURCES[@]}"
} >> "$LOG_FILE"

# --- Scraping loop ---
for SITE in "${SOURCES[@]}"; do
    TOTAL_SOURCES=$((TOTAL_SOURCES + 1))

    if [ "${FAILURES[$SITE]:-0}" -ge $MAX_FAILS ]; then
        echo -e "${YELLOW}⚠️ Skipping $SITE (failed ${FAILURES[$SITE]} times)${NC}" | tee -a "$LOG_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo "[*] Scraping $SITE ..." | tee -a "$LOG_FILE"
    SITE_DIR="$TMP_DIR/$(echo $SITE | sed 's#http[s]*://##; s#/$##')"

    httrack "$SITE" -O "$SITE_DIR" -%v --depth=1 --ext-depth=1 --near --sockets=4 --user-agent "$UA" >> "$LOG_FILE" 2>&1

    if [ -d "$SITE_DIR" ]; then
        grep -rho --include="*" 'http[^"]*\.m3u8[^"]*' "$SITE_DIR" >> "$ALL_LINKS"
        echo -e "${GREEN}✅ $SITE mirrored successfully${NC}" | tee -a "$LOG_FILE"
        FAILURES["$SITE"]=0
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}⚠️ Failed to mirror $SITE${NC}" | tee -a "$LOG_FILE"
        FAILURES["$SITE"]=$(( ${FAILURES["$SITE"]:-0} + 1 ))
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# --- Merge all into IPTV.m3u ---
echo "#EXTM3U" > "$OUTPUT_FILE"
sort -u "$ALL_LINKS" >> "$OUTPUT_FILE"
TOTAL_LINKS=$(wc -l < "$OUTPUT_FILE")

# --- Detect new links since last run ---
NEW_LINKS=0
if [ -f "$PREV_FILE" ]; then
    NEW_LINKS=$(comm -13 <(sort "$PREV_FILE") <(sort "$OUTPUT_FILE") | tee -a "$LOG_FILE" | wc -l)
    NEW_LINK_LIST=$(comm -13 <(sort "$PREV_FILE") <(sort "$OUTPUT_FILE"))
else
    NEW_LINKS=$TOTAL_LINKS
    NEW_LINK_LIST=$(cat "$OUTPUT_FILE")
fi

# Save current playlist as previous for next run
cp "$OUTPUT_FILE" "$PREV_FILE"

# Clean temp folder
rm -rf "$TMP_DIR"

# Save updated failure counts
> "$FAIL_FILE"
for key in "${!FAILURES[@]}"; do
    echo "$key=${FAILURES[$key]}" >> "$FAIL_FILE"
done

# Commit & push
git add "$OUTPUT_FILE" "$FAIL_FILE" "$PREV_FILE"
git commit -m "Auto-update IPTV.m3u on $(date)" || echo "No changes to commit" | tee -a "$LOG_FILE"
git push origin master >> "$LOG_FILE" 2>&1
echo -e "${GREEN}✅ Playlist updated and pushed at $(date)${NC}" | tee -a "$LOG_FILE"

# --- Color-coded summary ---
{
    echo "Run summary:"
    echo "Total sources: $TOTAL_SOURCES"
    echo "Succeeded: $SUCCESS_COUNT"
    echo "Failed: $FAILED_COUNT"
    echo "Skipped (max failures reached): $SKIPPED_COUNT"
    echo "Total unique .m3u8 links: $TOTAL_LINKS"
    echo "New links this run: $NEW_LINKS"
    echo "Run finished at $(date)"
    echo "========================="
} | tee -a "$LOG_FILE"

# Summary printed with colors
echo -e "${GREEN}Succeeded: $SUCCESS_COUNT${NC}, ${RED}Failed: $FAILED_COUNT${NC}, ${YELLOW}Skipped: $SKIPPED_COUNT${NC}, Total links: $TOTAL_LINKS, New links: $NEW_LINKS"
if [ "$NEW_LINKS" -gt 0 ]; then
    echo -e "${GREEN}New links added this run:${NC}"
    echo "$NEW_LINK_LIST"
fi
#!
