dump('entering util/clipboard.js\n');

if (typeof util == 'undefined') var util = {};
util.clipboard = {};

util.clipboard.EXPORT_OK    = [ 
    'cut', 'copy', 'paste'
];
util.clipboard.EXPORT_TAGS    = { ':all' : util.clipboard.EXPORT_OK };

util.clipboard.cut = function() {
    try {
        var n = document.popupNode;
        if (n.getAttribute('readonly')=='true') return;
        var v = n.value;
        var start = n.selectionStart;
        var end = n.selectionEnd;
        var clip = v.substring( start, end );
        n.value = v.substring(0, start) + v.substring(end, v.length);
        const gClipboardHelper = Components.classes["@mozilla.org/widget/clipboardhelper;1"]
            .getService(Components.interfaces.nsIClipboardHelper);
        gClipboardHelper.copyString(clip);
        n.setSelectionRange(start,start);
        dump('Copied ' + clip + '\n');
    } catch(E) {
        alert(E);
    }
}

util.clipboard.copy = function() {
    try {
        var n = document.popupNode;
        var v = n.value;
        var start = n.selectionStart;
        var end = n.selectionEnd;
        var clip = v.substring( start, end );
        const gClipboardHelper = Components.classes["@mozilla.org/widget/clipboardhelper;1"]
            .getService(Components.interfaces.nsIClipboardHelper);
        gClipboardHelper.copyString(clip);
        dump('Copied ' + clip + '\n');
    } catch(E) {
        alert(E);
    }
}

util.clipboard.paste = function() {
    try {
        var n = document.popupNode;
        if (n.getAttribute('readonly')=='true') return;
        var v = n.value;
        var start = n.selectionStart;
        var end = n.selectionEnd;
        var cb = Components.classes["@mozilla.org/widget/clipboard;1"].getService(Components.interfaces.nsIClipboard); 
        if (!cb) return false; 
        var trans = Components.classes["@mozilla.org/widget/transferable;1"].createInstance(Components.interfaces.nsITransferable); 
        if (!trans) return false; 
        trans.addDataFlavor("text/unicode"); 
        cb.getData(trans, cb.kGlobalClipboard);
        var str = {}; var strLength = {};
        trans.getTransferData("text/unicode",str,strLength);
        if (str) str = str.value.QueryInterface(Components.interfaces.nsISupportsString);
        var clip; if (str) clip = str.data.substring(0, strLength.value / 2);
        n.value = v.substring(0, start) + clip + v.substring(end, v.length);
        n.setSelectionRange(start + clip.length,start + clip.length);
        dump('Pasted ' + clip + '\n');
    } catch(E) {
        alert(E);
    }
}

dump('exiting util/clipboard.js\n');
