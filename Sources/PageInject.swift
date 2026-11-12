import Foundation

/// 页面注入。对应 Android 侧 web/PageInject.kt。
///
/// 两个职责：
/// 1. polyfill —— `crypto.randomUUID` 在 `http://<IP>`（非安全上下文）里原生为 undefined，
///    而 DSH 连接层拿它生成 RPC id；`AbortSignal.any` 在 iOS 17.4 之前没有。
/// 2. 布局覆盖 —— DSH 在页面启动时用 `matchMedia('(max-width: 1023px)')` 判一次窄/宽屏，
///    判定发生在页面自己的脚本里，所以必须用 WKUserScript 的 .atDocumentStart 抢在前面。
enum PageInject {

    private static let polyfill = #"""
    try{if(self.crypto&&!self.crypto.randomUUID){self.crypto.randomUUID=function(){var b=new Uint8Array(16);self.crypto.getRandomValues(b);b[6]=b[6]&15|64;b[8]=b[8]&63|128;var h='';for(var i=0;i<16;i++){var x=b[i].toString(16);h+=x.length<2?'0'+x:x;if(i===3||i===5||i===7||i===9)h+='-'}return h}}}catch(e){}
    try{if(self.AbortSignal&&!self.AbortSignal.any){self.AbortSignal.any=function(signals){var ctrl=new AbortController(),list=Array.prototype.slice.call(signals||[]),done=false;function stop(s){if(done)return;done=true;try{ctrl.abort(s&&s.reason)}catch(e){ctrl.abort()}}for(var i=0;i<list.length;i++){if(list[i].aborted){stop(list[i]);break}list[i].addEventListener('abort',(function(s){return function(){stop(s)}})(list[i]),{once:true})}return ctrl.signal}}}catch(e){}
    """#

    static func documentStart(layout: String) -> String {
        var forced = "null"
        if layout == ServerStore.layoutDesktop { forced = "false" }
        if layout == ServerStore.layoutMobile { forced = "true" }

        return #"""
        (function(){
        \#(polyfill)
        try{
        var F=\#(forced);
        if(F!==null){
        var orig=window.matchMedia.bind(window);
        var key=function(s){return String(s).replace(/\s+/g,'').toLowerCase()};
        window.matchMedia=function(q){
        var k=key(q),want=null;
        if(k.indexOf('(max-width:1023px)')>=0)want=F;
        else if(k.indexOf('(min-width:1024px)')>=0)want=!F;
        if(want===null||want===undefined)return orig(q);
        var ls=[];
        return{matches:want,media:String(q),onchange:null,
        addEventListener:function(t,f){if(t==='change'&&ls.indexOf(f)<0)ls.push(f)},
        removeEventListener:function(t,f){var i=ls.indexOf(f);if(i>=0)ls.splice(i,1)},
        addListener:function(f){if(ls.indexOf(f)<0)ls.push(f)},
        removeListener:function(f){var i=ls.indexOf(f);if(i>=0)ls.splice(i,1)},
        dispatchEvent:function(){return false}};
        };
        }
        }catch(e){}
        })();
        """#
    }

    /// 整页载入会把 documentElement 的 zoom 冲掉，加载完成后再补一次。
    static func zoom(_ scale: Double) -> String {
        let v = String(format: "%.3f", scale)
        return "(function(){try{document.documentElement.style.zoom='\(v)';}catch(e){}})();"
    }
}
