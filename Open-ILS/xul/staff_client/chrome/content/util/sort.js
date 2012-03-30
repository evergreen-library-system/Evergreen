dump('entering util/sort.js\n');

if (typeof util == 'undefined') var util = {};
util.sort = {};

util.sort.EXPORT_OK    = [ 
    'dispatch'
];
util.sort.EXPORT_TAGS    = { ':all' : util.sort.EXPORT_OK };

util.sort.dispatch = function(what,sortDir) {
    try {
        dump('util.sort.dispatch('+what+','+sortDir+');\n');
        JSAN.use('util.widgets');
        util.widgets.dispatch('sort_'+what+'_'+sortDir, document.popupNode);
    } catch(E) {
        alert(E);
    }
}

dump('exiting util/sort.js\n');
