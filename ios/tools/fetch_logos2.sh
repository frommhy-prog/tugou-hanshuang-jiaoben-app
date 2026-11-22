#!/bin/bash
# 二轮补抓：第一轮没抓到的图标，换官方推特头像（unavatar）和 DefiLlama 再试。已有的跳过。
OUT="ios/App/Logos"
mkdir -p "$OUT"
TW="https://raw.githubusercontent.com/trustwallet/assets/master/blockchains"
tw() { echo "https://unavatar.io/x/$1?fallback=false"; echo "https://unavatar.io/twitter/$1?fallback=false"; }
llc() { echo "https://icons.llamao.fi/icons/chains/rsz_$1.jpg"; }
llp() { echo "https://icons.llamao.fi/icons/protocols/$1?w=256&h=256"; }

PH=()
probe() {
  local t
  t=$(mktemp -t lg2)
  if curl -fsSL --max-time 20 -A "Mozilla/5.0" -o "$t" "$1" 2>/dev/null && [ -s "$t" ]; then PH+=("$(md5 -q "$t")"); fi
  rm -f "$t"
}
probe "https://icons.llamao.fi/icons/chains/rsz_zz-not-exist-9.jpg"
probe "https://icons.llamao.fi/icons/protocols/zz-not-exist-9"

OKN=0
one() {
  local name="$1"; shift
  if [ -s "$OUT/$name.png" ]; then return 0; fi
  local t u size sum bad ph w
  t=$(mktemp -t lg2)
  for u in "$@"; do
    rm -f "$t"
    curl -fsSL --max-time 25 -A "Mozilla/5.0" -o "$t" "$u" 2>/dev/null || continue
    size=$(stat -f%z "$t" 2>/dev/null || echo 0)
    [ "$size" -gt 300 ] || continue
    sum=$(md5 -q "$t")
    bad=0
    for ph in "${PH[@]}"; do [ "$sum" = "$ph" ] && bad=1; done
    [ "$bad" = "1" ] && continue
    file "$t" | grep -qiE 'image|icon' || continue
    w=$(sips -g pixelWidth "$t" 2>/dev/null | awk '/pixelWidth/{print $2}')
    [ -z "$w" ] && w=0
    [ "$w" -ge 48 ] || continue
    if sips -s format png "$t" --out "$OUT/$name.png" >/dev/null 2>&1; then
      if [ "$w" -gt 256 ]; then sips -Z 256 "$OUT/$name.png" >/dev/null 2>&1; fi
      echo "OK2   $name <- $u"
      OKN=$((OKN + 1))
      rm -f "$t"
      return 0
    fi
  done
  rm -f "$t"
  echo "MISS2 $name"
  return 0
}

one gmc_bob $(tw build_on_bob) $(llc bob)
one gmc_coredao $(tw Coredao_Org) $(llc core)
one gmc_flare $(tw FlareNetworks) $(llc flare)
one gmc_fraxtal $(tw fraxfinance) $(llc fraxtal)
one gmc_lisk $(tw LiskHQ) $(llc lisk)
one gmc_mode $(tw modenetwork) $(llc mode)
one gmc_okc $(tw okx) $(llc okexchain) "$TW/okexchain/info/logo.png"
one gmc_story $(tw StoryProtocol) $(llc story)
one gmc_taiko $(tw taikoxyz) $(llc taiko)
one gmc_xlayer $(tw XLayerOfficial) $(llc xlayer) "https://icons.llamao.fi/icons/chains/rsz_x%20layer.jpg"
one gmc_zora $(tw zora) $(llc zora)
one gmd_lifinity $(tw Lifinity_io) $(llp lifinity-v2) $(llp lifinity)
one gmd_phoenix $(tw PhoenixTrade) $(llp phoenix) $(llp phoenix-v1)
one gml_believe $(tw believeapp)
one gml_boop $(tw boopdotfun) $(tw boop)
one gml_daos $(tw daosdotfun) $(tw daosfun)
one gml_jupstudio $(tw JupiterExchange) $(tw jup_studio)
one gml_zora $(tw zora)
echo "SUMMARY2 ok=$OKN"
exit 0
