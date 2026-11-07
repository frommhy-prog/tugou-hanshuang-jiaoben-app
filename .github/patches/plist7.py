# 补丁清单（第七批）：垃圾币符号乱码、数据时间显示日期与失败原因、K 线可读性（叠加线不撑坐标轴、主图成交量、少而宽的蜡烛、标记更少更稀）
def register(rep, cut):
    N = 'ios/App/Narrative.swift'
    rep('nv_spam', N,
        '                if !(n.lowercased().contains(ql) || s.lowercased().contains(ql)) { continue }\n',
        '                if s.count > 14 || n.count > 48 { continue } // 垃圾币：符号或名称塞满一长串其它币的代号\n                if !(n.lowercased().contains(ql) || s.lowercased().contains(ql)) { continue }\n')
    rep('nv_row', N,
        '                    Text(s.sym).font(.subheadline.weight(.semibold))\n                    Pill(text: s.chain, color: Color.blue)\n',
        '                    Text(s.sym).font(.subheadline.weight(.semibold)).lineLimit(1)\n                    Pill(text: s.chain, color: Color.blue)\n')

    E = 'ios/App/NarrativeEngine.swift'
    rep('ne_spam', E,
        '        if a.isEmpty { return nil }\n',
        '        if a.isEmpty { return nil }\n        if (b.symbol ?? "").count > 14 || (b.name ?? "").count > 48 { return nil }\n')
    rep('ne_row', E,
        'Text(s.sym).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)',
        'Text(s.sym).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)')

    R = 'ios/App/ReportCard.swift'
    rep('rc_ts', R,
        '            text = name + " " + d.formatted(date: .omitted, time: .standard) + (stale ? "（旧 " + ago(age) + "）" : "")\n',
        '            let ts: String = age > 43_200 ? d.formatted(date: .abbreviated, time: .shortened) : d.formatted(date: .omitted, time: .standard)\n            text = name + " " + ts + (stale ? "（旧 " + ago(age) + "）" : "")\n')
    rep('rc_hn', R,
        '                if let n = vm.refreshNote { Text(n).font(.caption2).foregroundStyle(Color.orange) }\n',
        '                if let n = vm.refreshNote { Text(n).font(.caption2).foregroundStyle(Color.orange) }\n                if let hn = vm.holderNote, !hn.isEmpty, (vm.stamps.holders.map { Date().timeIntervalSince($0) > 900 } ?? true) { Text(cat("持有人刷新失败：", hn)).font(.caption2).foregroundStyle(Color.orange) }\n')

    P = 'ios/App/ProChart.swift'
    rep('kl_attr', P,
        'Text("来源 GeckoTerminal · 箭头 = 大额买卖，圆点 #n = 第 n 大持有人的成交 · 点 K 线选中，再点取消")',
        'Text("来源 GeckoTerminal · 箭头 = 大额买卖，圆点 #n = 第 n 大持有人的成交 · 点 K 线选中，再点取消 · 图表 TradingView Lightweight Charts™")')

    H = 'ios/App/Web/chart.html'
    rep('ch_logo', H, r'''textColor:'#9ca3af',fontSize:10}''', r'''textColor:'#9ca3af',fontSize:10,attributionLogo:false}''')
    rep('ch_scale', H, r'''  var BK=Object.keys(B),MK=Object.keys(M);
''', r'''  var BK=Object.keys(B),MK=Object.keys(M);
  ['bu','bm','bl','st','sar'].forEach(function(k){M[k].applyOptions({autoscaleInfoProvider:function(){return null;}});});
  var mv=chart.addHistogramSeries({priceScaleId:'mv',priceLineVisible:false,lastValueVisible:false});
  chart.priceScale('mv').applyOptions({scaleMargins:{top:0.86,bottom:0},visible:false});
''')
    rep('ch_st', H, r'''st:L(chart,UP,2)''', r'''st:L(chart,UP,1)''')
    rep('ch_range', H, r'''ts.setVisibleLogicalRange({from:Math.max(-2,n-120),to:n+6})''', r'''ts.setVisibleLogicalRange({from:Math.max(-2,n-80),to:n+6})''')
    rep('ch_vol', H, r'''    compute();markers();
''', r'''    compute();markers();
    mv.setData(S.cfg.sub==='VOL'?[]:S.C.map(function(x){return {time:x.t,value:x.v,color:x.c>=x.o?'rgba(34,197,94,0.35)':'rgba(239,68,68,0.35)'};}));
''')
    rep('ch_lab1', H, r'''var labeled={},picked=[];''', r'''var labeled={},picked=[],allow={};arrows.slice(0,8).forEach(function(m){allow[m[0]+':'+m[1]+':'+m[2]]=1;});''')
    rep('ch_lab2', H, r'''if(picked.length>=3)return;''', r'''if(picked.length>=2)return;''')
    rep('ch_lab3', H, r'''Math.abs(picked[k]-i)<10''', r'''Math.abs(picked[k]-i)<16''')
    rep('ch_lab4', H, r'''      else{var o={time:m[0],position:m[1]>0?''', r'''      else if(allow[m[0]+':'+m[1]+':'+m[2]]){var o={time:m[0],position:m[1]>0?''')
