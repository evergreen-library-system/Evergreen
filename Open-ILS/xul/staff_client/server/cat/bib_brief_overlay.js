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
                    if (c.id == 'title') set_tooltip('title',value);
                    if (c.id == 'author') set_tooltip('author',value);
                    //dump('set text on ' + n + ' elements\n');
                } else {
                    //dump('render is not a function\n');
                }
            } else {
                //dump('is not an mvr or bre\n');
            }
        }

        // Let's fetch a bib call number
        JSAN.use('OpenILS.data');
        var data = new OpenILS.data();
        var label_class = data.hash.aous['cat.default_classification_scheme'];
        if (!label_class) {
            label_class = 1;
        }
        var cn_blob_array = net.simple_request('BLOB_MARC_CALLNUMBERS_RETRIEVE',[params.mvr_id, label_class]);
        if (! cn_blob_array) { cn_blob_array = []; }
        var tooltip_text = '';
        for (var i = 0; i < cn_blob_array.length; i++) {
            var cn_blob_obj = cn_blob_array[i];
            for (var j in cn_blob_obj) {
                tooltip_text += j + ' : ' + cn_blob_obj[j] + '\n';
            }
        }
        if (tooltip_text) {
            var cn_blob_obj = cn_blob_array[0];
            for (var j in cn_blob_obj) {
                set('bib_call_number',cn_blob_obj[j]);
            }
            set_tooltip('bib_call_number',tooltip_text);
        }

    } catch(E) {
        alert(location.href + '\nError in bib_brief_overlay(' + js2JSON(params) + '): ' + E);
        return;
    }
}
