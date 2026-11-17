#!/bin/bash
# 抓真实的公链 / 发射台 / DEX / 品牌图标，打进 App（已有的跳过；失败的运行时再走网络兜底）。8 路并发，结果汇总在末尾。
OUT="ios/App/Logos"
mkdir -p "$OUT"
LOG=$(mktemp -t gmlogo)
DSC="https://dd.dexscreener.com/ds-data/chains"
DSD="https://dd.dexscreener.com/ds-data/dexes"
TW="https://raw.githubusercontent.com/trustwallet/assets/master/blockchains"
gfav() { echo "https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&url=https://$1&size=128"; }
fav() { echo "https://www.google.com/s2/favicons?domain=$1&sz=128"; }
ddg() { echo "https://icons.duckduckgo.com/ip3/$1.ico"; }

# 各来源对不存在的图标会返回占位图：先取占位图算指纹，之后一律丢弃
PHS=()
probe() {
  local t
  t=$(mktemp -t gmph)
  if curl -fsSL --max-time 20 -A "Mozilla/5.0" -o "$t" "$1" 2>/dev/null && [ -s "$t" ]; then
    PHS+=("$(md5 -q "$t")")
  fi
  rm -f "$t"
}
probe "$DSD/zz-not-exist-9.png"
probe "$(gfav zz-not-exist-9.example)"
probe "$(fav zz-not-exist-9.example)"
probe "$(ddg zz-not-exist-9.example)"
echo "PLACEHOLDERS ${#PHS[@]}"

# 清掉之前误存的 Dexscreener 占位图（1688 字节）
for f in "$OUT"/*.png; do
  [ -f "$f" ] || continue
  if [ "$(stat -f%z "$f" 2>/dev/null || echo 0)" = "1688" ]; then rm -f "$f"; echo "DROP placeholder $f"; fi
done

fetch() {
  local name="$1"; shift
  if [ -s "$OUT/$name.png" ]; then echo "HAVE $name" >> "$LOG"; return 0; fi
  local t u size sum bad ph w
  t=$(mktemp -t gmlogo)
  for u in "$@"; do
    rm -f "$t"
    if curl -fsSL --max-time 25 -A "Mozilla/5.0" -o "$t" "$u" 2>/dev/null; then
      size=$(stat -f%z "$t" 2>/dev/null || echo 0)
      sum=$(md5 -q "$t" 2>/dev/null)
      bad=0
      for ph in "${PHS[@]}"; do
        if [ "$sum" = "$ph" ]; then bad=1; fi
      done
      if [ "$bad" = "1" ]; then continue; fi
      if [ "$size" -gt 200 ] && file "$t" | grep -qiE 'image|icon'; then
        w=$(sips -g pixelWidth "$t" 2>/dev/null | awk '/pixelWidth/{print $2}')
        [ -z "$w" ] && w=0
        if [ "$w" -lt 32 ]; then continue; fi
        if sips -s format png "$t" --out "$OUT/$name.png" >/dev/null 2>&1; then
          if [ "$w" -gt 192 ]; then sips -Z 192 "$OUT/$name.png" >/dev/null 2>&1; fi
          echo "OK   $name <- $u" >> "$LOG"
          rm -f "$t"
          return 0
        fi
      fi
    fi
  done
  echo "MISS $name" >> "$LOG"
  rm -f "$t"
  return 0
}

JOBS=0
run() {
  fetch "$@" &
  JOBS=$((JOBS + 1))
  if [ "$JOBS" -ge 8 ]; then wait; JOBS=0; fi
}

# ---- 公链（gmc_<Dexscreener 链 id>）----
run gmc_solana    "$DSC/solana.png"    "$TW/solana/info/logo.png"
run gmc_ethereum  "$DSC/ethereum.png"  "$TW/ethereum/info/logo.png"
run gmc_bsc       "$DSC/bsc.png"       "$TW/smartchain/info/logo.png"
run gmc_base      "$DSC/base.png"      "$TW/base/info/logo.png"
run gmc_polygon   "$DSC/polygon.png"   "$TW/polygon/info/logo.png"
run gmc_arbitrum  "$DSC/arbitrum.png"  "$TW/arbitrum/info/logo.png"
run gmc_optimism  "$DSC/optimism.png"  "$TW/optimism/info/logo.png"
run gmc_robinhood "$DSC/robinhood.png" "$(fav robinhood.com)"
run gmc_okc       "$DSC/okc.png"       "$(gfav okx.com)"
run gmc_xlayer    "$DSC/xlayer.png"    "$(gfav web3.okx.com)"
run gmc_avalanche "$DSC/avalanche.png" "$TW/avalanchec/info/logo.png"
run gmc_linea     "$DSC/linea.png"     "$TW/linea/info/logo.png"
run gmc_scroll    "$DSC/scroll.png"    "$TW/scroll/info/logo.png"
run gmc_blast     "$DSC/blast.png"     "$TW/blast/info/logo.png"
run gmc_zksync    "$DSC/zksync.png"    "$TW/zksync/info/logo.png"
run gmc_mantle    "$DSC/mantle.png"    "$TW/mantle/info/logo.png"
run gmc_cronos    "$DSC/cronos.png"    "$TW/cronos/info/logo.png"
run gmc_fantom    "$DSC/fantom.png"    "$TW/fantom/info/logo.png"
run gmc_sonic     "$DSC/sonic.png"     "$(gfav soniclabs.com)"
run gmc_berachain "$DSC/berachain.png" "$(gfav berachain.com)"
run gmc_tron      "$DSC/tron.png"      "$TW/tron/info/logo.png"
run gmc_ton       "$DSC/ton.png"       "$TW/ton/info/logo.png"
run gmc_sui       "$DSC/sui.png"       "$TW/sui/info/logo.png"
run gmc_aptos     "$DSC/aptos.png"     "$TW/aptos/info/logo.png"
run gmc_near      "$DSC/near.png"      "$TW/near/info/logo.png"
run gmc_unichain  "$DSC/unichain.png"  "$(gfav unichain.org)"
run gmc_abstract  "$DSC/abstract.png"  "$(gfav abs.xyz)"
run gmc_hyperevm  "$DSC/hyperevm.png"  "$(gfav hyperfoundation.org)"
run gmc_sei       "$DSC/sei.png"       "$TW/sei/info/logo.png"
run gmc_ink       "$DSC/ink.png"       "$(gfav inkonchain.com)"
run gmc_monad     "$DSC/monad.png"     "$(gfav monad.xyz)"
run gmc_ronin     "$DSC/ronin.png"     "$TW/ronin/info/logo.png"
run gmc_celo      "$DSC/celo.png"      "$TW/celo/info/logo.png"
run gmc_gnosis    "$DSC/gnosis.png"    "$TW/xdai/info/logo.png"
run gmc_opbnb     "$DSC/opbnb.png"     "$TW/opbnb/info/logo.png"
run gmc_manta     "$DSC/manta.png"     "$TW/manta/info/logo.png"
run gmc_mode      "$DSC/mode.png"      "$(gfav mode.network)"
run gmc_zora      "$DSC/zora.png"      "$(gfav zora.co)"
run gmc_fraxtal   "$DSC/fraxtal.png"   "$(gfav frax.com)"
run gmc_pulsechain "$DSC/pulsechain.png" "$TW/pulsechain/info/logo.png"
run gmc_kava      "$DSC/kava.png"      "$TW/kava/info/logo.png"
run gmc_moonbeam  "$DSC/moonbeam.png"  "$TW/moonbeam/info/logo.png"
run gmc_injective "$DSC/injective.png" "$TW/injective/info/logo.png"
run gmc_osmosis   "$DSC/osmosis.png"   "$TW/osmosis/info/logo.png"
run gmc_cardano   "$DSC/cardano.png"   "$TW/cardano/info/logo.png"
run gmc_harmony   "$DSC/harmony.png"   "$TW/harmony/info/logo.png"
run gmc_metis     "$DSC/metis.png"     "$TW/metis/info/logo.png"
run gmc_taiko     "$DSC/taiko.png"     "$TW/taiko/info/logo.png"
run gmc_story     "$DSC/story.png"     "$(gfav story.foundation)"
run gmc_plasma    "$DSC/plasma.png"    "$(gfav plasma.to)"
run gmc_worldchain "$DSC/worldchain.png" "$(gfav world.org)"
run gmc_lisk      "$DSC/lisk.png"      "$(gfav lisk.com)"
run gmc_bob       "$DSC/bob.png"       "$(gfav gobob.xyz)"
run gmc_coredao   "$DSC/coredao.png"   "$(gfav coredao.org)"
run gmc_flare     "$DSC/flare.png"     "$(gfav flare.network)"
run gmc_hedera    "$DSC/hedera.png"    "$(gfav hedera.com)"
run gmc_stellar   "$DSC/stellar.png"   "$(gfav stellar.org)"
run gmc_bitcoin   "$DSC/bitcoin.png"   "$TW/bitcoin/info/logo.png"

# ---- 发射台（gml_<key>，内盘 / 外盘标识用）----
run gml_pumpfun   "$DSD/pumpfun.png"   "$(gfav pump.fun)"
run gml_pumpswap  "$DSD/pumpswap.png"
run gml_fourmeme  "$DSD/fourmeme.png"  "$(gfav four.meme)"
run gml_letsbonk  "$DSD/letsbonk.png"  "$(gfav bonk.fun)" "$(gfav letsbonk.fun)" "$(gfav bonkcoin.com)"
run gml_flap      "$DSD/flap.png"      "$(gfav flap.sh)"
run gml_moonshot  "$DSD/moonshot.png"  "$(gfav moonshot.com)" "$(gfav moonit.xyz)"
run gml_clanker   "$DSD/clanker.png"   "$(gfav clanker.world)"
run gml_virtuals  "$DSD/virtuals.png"  "$(gfav virtuals.io)"
run gml_bags      "$(gfav bags.fm)"
run gml_believe   "$DSD/believe.png"   "$(gfav believe.app)"
run gml_boop      "$DSD/boop.png"      "$(gfav boop.fun)"
run gml_heaven    "$DSD/heaven.png"    "$(gfav heaven.xyz)"
run gml_launchlab "$DSD/launchlab.png" "$(gfav raydium.io)"
run gml_jupstudio "$(gfav jup.ag)"
run gml_daos      "$DSD/daosfun.png"   "$(gfav daos.fun)"
run gml_zora      "$(gfav zora.co)"

# ---- DEX（gmd_<Dexscreener dex id>）----
run gmd_raydium     "$DSD/raydium.png"     "$(gfav raydium.io)"
run gmd_orca        "$DSD/orca.png"        "$(gfav orca.so)"
run gmd_meteora     "$DSD/meteora.png"     "$(gfav meteora.ag)"
run gmd_pumpswap    "$DSD/pumpswap.png"
run gmd_uniswap     "$DSD/uniswap.png"     "$(gfav uniswap.org)"
run gmd_pancakeswap "$DSD/pancakeswap.png" "$(gfav pancakeswap.finance)"
run gmd_aerodrome   "$DSD/aerodrome.png"   "$(gfav aerodrome.finance)"
run gmd_sushiswap   "$DSD/sushiswap.png"   "$(gfav sushi.com)"
run gmd_camelot     "$DSD/camelot.png"     "$(gfav camelot.exchange)"
run gmd_velodrome   "$DSD/velodrome.png"   "$(gfav velodrome.finance)"
run gmd_lifinity    "$DSD/lifinity.png"    "$(gfav lifinity.io)"
run gmd_phoenix     "$DSD/phoenix.png"     "$(gfav phoenix.trade)"
run gmd_fluxbeam    "$DSD/fluxbeam.png"    "$(gfav fluxbeam.xyz)"
run gmd_thena       "$DSD/thena.png"       "$(gfav thena.fi)"
run gmd_biswap      "$DSD/biswap.png"      "$(gfav biswap.org)"
run gmd_apeswap     "$DSD/apeswap.png"     "$(gfav apeswap.finance)"

# ---- 品牌：社交 / 行情工具 / 钱包 / 交易所 / 交易机器人（gmb_<key>，清单见 ios/tools/brands.txt）----
while read -r key dom; do
  [ -z "$key" ] && continue
  case "$key" in \#*) continue ;; esac
  [ -z "$dom" ] && continue
  run "gmb_$key" "https://$dom/apple-touch-icon.png" "$(gfav $dom)" "$(fav $dom)" "$(ddg $dom)"
done < ios/tools/brands.txt

wait
echo "SUMMARY ok=$(grep -c '^OK' "$LOG") have=$(grep -c '^HAVE' "$LOG") miss=$(grep -c '^MISS' "$LOG") files=$(ls "$OUT" | wc -l | tr -d ' ')"
grep '^OK' "$LOG" | sort
grep '^MISS' "$LOG" | sort
rm -f "$LOG"
exit 0
