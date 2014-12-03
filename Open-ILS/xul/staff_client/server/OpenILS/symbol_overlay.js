dump('entering symbol/clipboard.js\n');

function $(id) { return document.getElementById(id); }

var el = {};

dojo.addOnLoad(
    function(){
        dojo.query('.plain').forEach(function(node,index,arr){
            addSymbolTrigger(node);
        });
    }
);

function addSymbolTrigger(node) {
    if (!node.getAttribute('eg_has_symbol_trigger')) {
        node.addEventListener(
            "keypress",
            function(event) { 
                if (event.charCode == 115 && event.ctrlKey){
                    setNod(node);
                    $('symbol-panel').openPopup(node, 'after_pointer' );
                }
            },
            true);
        node.setAttribute('eg_has_symbol_trigger', 1);
    }
}

function setNod(elm){
    el = elm;
}

function ret(ins, e){
    if (e.button == 0){
        $('symbol-panel').hidePopup();
        n = el;
        
        if (n.getAttribute('readonly')=='true') return;
        
        var v = n.value;
        var start = n.selectionStart;
        var end = n.selectionEnd;
        n.value = v.substring(0, start) + ins + v.substring(end, v.length);
        n.setSelectionRange(start + ins.length,start + ins.length);
    }
}
