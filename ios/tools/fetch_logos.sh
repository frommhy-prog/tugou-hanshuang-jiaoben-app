#!/bin/bash
# 抓真实的公链 / 发射台 / DEX 官方图标，打进 App（已有的跳过，失败的运行时再走网络兜底）
OUT="ios/App/Logos"
TMP="/tmp/gm_logo.tmp"
mkdir -p "$OUT"
DSC="https://dd.dexscreener.com/ds-data/chains"
DSD="https://dd.dexscreener.com/ds-data/dexes"
TW="https://raw.githubusercontent.com/trustwallet/assets/master/blockchains"
fav() { echo "https://www.google.com/s2/favicons?domain=$1&sz=128"; }

# Dexscreener 对不存在的图标也返回 200 的占位图：先取一张占位图算指纹，之后一律丢弃；并清掉之前误存的占位图
curl -fsSL --max-time 20 -o "$TMP" "$DSD/zz-not-exist-9.png" 2>/dev/null
PH=""
[ -s "$TMP" ] && PH=$(md5 -q "$TMP" 2>/dev/null)
echo "PLACEHOLDER md5=$PH"
for f in "$OUT"/*.png; do
  [ -f "$f" ] || continue
  if [ "$(stat -f%z "$f" 2>/dev/null || echo 0)" = "1688" ]; then rm -f "$f"; echo "DROP placeholder $f"; fi
done

fetch() {
  local name="$1"; shift
  if [ -s "$OUT/$name.png" ]; then echo "HAVE $name"; return 0; fi
  for u in "$@"; do
    rm -f "$TMP"
    if curl -fsSL --max-time 25 -A "Mozilla/5.0" -o "$TMP" "$u" 2>/dev/null; then
      size=$(stat -f%z "$TMP" 2>/dev/null || echo 0)
      sum=$(md5 -q "$TMP" 2>/dev/null)
      if [ -n "$PH" ] && [ "$sum" = "$PH" ]; then continue; fi
      if [ "$size" -gt 200 ] && file "$TMP" | grep -qiE 'image'; then
        if sips -s format png "$TMP" --out "$OUT/$name.png" >/dev/null 2>&1; then
          echo "OK   $name <- $u"; return 0
        fi
      fi
    fi
  done
  echo "MISS $name"
  return 0
}

fetch gmc_solana    "$DSC/solana.png"    "$TW/solana/info/logo.png"
fetch gmc_ethereum  "$DSC/ethereum.png"  "$TW/ethereum/info/logo.png"
fetch gmc_bsc       "$DSC/bsc.png"       "$TW/smartchain/info/logo.png"
fetch gmc_base      "$DSC/base.png"      "$TW/base/info/logo.png"
fetch gmc_polygon   "$DSC/polygon.png"   "$TW/polygon/info/logo.png"
fetch gmc_arbitrum  "$DSC/arbitrum.png"  "$TW/arbitrum/info/logo.png"
fetch gmc_optimism  "$DSC/optimism.png"  "$TW/optimism/info/logo.png"
fetch gmc_robinhood "$DSC/robinhood.png" "$(fav robinhood.com)"

fetch gml_pumpfun   "$DSD/pumpfun.png"   "$(fav pump.fun)"
fetch gml_fourmeme  "$DSD/fourmeme.png"  "$(fav four.meme)"
fetch gml_letsbonk  "$DSD/letsbonk.png"  "$(fav bonk.fun)" "$(fav letsbonk.fun)" "$(fav bonkcoin.com)"
fetch gml_flap      "$DSD/flap.png"      "$(fav flap.sh)"
fetch gml_moonshot  "$DSD/moonshot.png"  "$(fav moonshot.com)" "$(fav dexscreener.com)"
fetch gml_clanker   "$DSD/clanker.png"   "$(fav clanker.world)"
fetch gml_virtuals  "$DSD/virtuals.png"  "$(fav virtuals.io)"
fetch gml_bags      "$(fav bags.fm)"
ls -la "$OUT" 2>/dev/null | head -40
exit 0
