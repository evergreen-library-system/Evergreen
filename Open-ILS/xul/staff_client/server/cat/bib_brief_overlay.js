dump('loading bib_brief_overlay.js\n');

function bib_brief_overlay(params) {
    try {

        var net; var session;

        if (params.network) {
            net = params.network;
        } else {
            JSAN.use('util.network');
            net = new util.network();
        }

        if (params.session) {
            session = params.session;
        } else {
            session = ses(); // For some reason, this breaks, starting with an internal instantiation of util.error failing because util.error being an object instead of a constructor
        }


        // See if we have mvr or mvr.id, and possibly retrieve the mvr ourselves
        if (params.mvr_id && ! params.mvr) {
            var robj = net.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative',[ params.mvr_id ]);
            if (typeof robj.ilsevent != 'undefined') throw(robj); 
            params.mvr = robj;
        }
        if (params.mvr && !params.mvr_id) params.mvr_id = params.mvr.doc_id();

        // Ditto with the bre
        if ( (params.bre_id || params.mvr_id) && ! params.bre) {
            var robj = net.simple_request('FM_BRE_RETRIEVE_VIA_ID.authoritative',[ session, [ (params.bre_id||params.mvr_id) ] ]);
            if (typeof robj.ilsevent != 'undefined') throw(robj); 
            params.bre = robj[0];
        }

        JSAN.use('util.widgets');
        function set(name,value) { 
            var nodes = document.getElementsByAttribute('name',name); 
            for (var i = 0; i < nodes.length; i++) {
                util.widgets.set_text( nodes[i], value ); 
            }
            return nodes.length;
        }
        function set_tooltip(name,value) { 
            var nodes = document.getElementsByAttribute('name',name); 
            for (var i = 0; i < nodes.length; i++) {
                nodes[i].setAttribute('tooltiptext',value);
            }
            return nodes.length;
        }


        // Use the list column definitions for rendering the mvr against the elements in bib_brief_overlay.xul
        JSAN.use('circ.util');
        var columns = circ.util.columns({});
        for (var i = 0; i < columns.length; i++) {
            var c = columns[i];
            //dump('considering column ' + c.id + '... ');
            if (c.fm_class == 'mvr' || c.fm_class == 'bre') {
                //dump('is an mvr or bre... ');
                if (typeof c.render == 'function') { // Non-function renders are deprecated
                    //dump('render is a function... ');
                    var value;
                    try { 
                        value = c.render( { 'mvr' : params.mvr, 'acp' : params.acp, 'bre' : params.bre } ); 
                    } catch(E) { 
                        value = ''; 
                        //dump('Error in bib_brief_overlay(), with render() for c.id = ' + c.id + ' : ' + E + '\n'); 
                    }
                    //dump('value = ' + value + '\n');
                    var n = set(c.id, value ? value : '');
                    if (c.id == 'tcn_source') set_tooltip('tcn',value);
                    if (c.id == 'doc_id') set_tooltip('title',value);
                    //dump('set text on ' + n + ' elements\n');
                } else {
                    //dump('render is not a function\n');
                }
            } else {
                //dump('is not an mvr or bre\n');
            }
        }

    } catch(E) {
        alert(location.href + '\nError in bib_brief_overlay(' + js2JSON(params) + '): ' + E);
        return;
    }
}
