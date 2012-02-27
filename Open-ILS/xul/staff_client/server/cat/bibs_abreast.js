var error;
var network;
var record_ids;
var lead_record;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for bibs_abreast.xul');
        JSAN.use('util.functional');
        JSAN.use('util.widgets');
        JSAN.use('cat.util');
        JSAN.use('util.network');

        network = new util.network();

        record_ids = xul_param('record_ids') || [];
        record_ids = util.functional.unique_list_values( record_ids );

        // Merge UI 
        if (xul_param('merge')) {
            var x = document.getElementById('merge_bar');
            x.hidden = false;
            var y = document.getElementById('merge_button');
            y.addEventListener('command', merge_records, false);
            var z = document.getElementById('cancel_button');
            z.addEventListener('command', function() {
                x.hidden = true;
                y.disabled = true;
                var merge_bars = util.widgets.find_descendants_by_name(document,'merge_bar');
                for (var i = 0; i < merge_bars.length; i++) { merge_bars[i].hidden = true; }
            }, false);
        }

        // Display the records
        for (var i = 0; i < record_ids.length; i++) {
            render_bib(record_ids[i]);
        }

        /*if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name('Test'); } catch(E) { alert(E); }
        }*/

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}

function render_bib(record_id) {
    var main = document.getElementById('main');
    var template = main.firstChild;
    var new_node = template.cloneNode(true);
    main.appendChild(new_node);
    new_node.hidden = false;

    var splitter_template = template.nextSibling;
    var splitter = splitter_template.cloneNode(true);
    main.appendChild(splitter);
    splitter.hidden = false;

    render_bib_brief(new_node,record_id);

    var xul_deck = util.widgets.find_descendants_by_name(new_node,'bib_deck')[0];
    var deck = new util.deck(xul_deck);

    // merge UI
    if (xul_param('merge')) {
        var merge_bar = util.widgets.find_descendants_by_name(new_node,'merge_bar')[0];
        merge_bar.hidden = false;
        var lead_button = util.widgets.find_descendants_by_name(new_node,'lead_button')[0];
        lead_button.addEventListener('click', function() {
            lead_record = record_id;
            dump('record_id = ' + record_id + '\n');
            document.getElementById('merge_button').disabled = false;
        }, false);
    }

    // remove_me button
    var remove_me = util.widgets.find_descendants_by_name(new_node,'remove_me')[0];
    remove_me.addEventListener('command', function() {
        if (lead_record == record_id) {
            lead_record = undefined;
            document.getElementById('merge_button').disabled = true;
        }
        record_ids = util.functional.filter_list( record_ids, function(o) { return o != record_id; } );
        main.removeChild(new_node);
        main.removeChild(splitter);
        if (main.childNodes.length == 4) {
            document.getElementById('merge_bar').hidden = true;
            document.getElementById('merge_button').disabled = true;
            var merge_bars = util.widgets.find_descendants_by_name(document,'merge_bar');
            for (var i = 0; i < merge_bars.length; i++) { merge_bars[i].hidden = true; }
        }
        if (main.childNodes.length == 2) { xulG.close_tab(); }
    }, false);

    // radio buttons
    var view_bib = util.widgets.find_descendants_by_name(new_node,'view_bib')[0];
    var edit_bib = util.widgets.find_descendants_by_name(new_node,'edit_bib')[0];
    var holdings = util.widgets.find_descendants_by_name(new_node,'holdings')[0];

    view_bib.addEventListener('command', function() {
        set_view_pane(deck,record_id);
    }, false); 

    edit_bib.addEventListener('command', function() {
        set_edit_pane(deck,record_id);
    }, false); 

    holdings.addEventListener('command', function() {
        set_item_pane(deck,record_id);
    }, false); 

    set_view_pane(deck,record_id);

}

function render_bib_brief(new_node,record_id) {
    // iframe
    var bib_brief = util.widgets.find_descendants_by_name(new_node,'bib_brief')[0];
    bib_brief.setAttribute('src', urls.XUL_BIB_BRIEF_VERTICAL);
    get_contentWindow(bib_brief).xulG = { 'docid' : record_id };
}

function set_view_pane(deck,record_id) {
    deck.set_iframe( urls.XUL_MARC_VIEW, {}, { 'docid' : record_id } );
}

function set_item_pane(deck,record_id) {
    var my_xulG = { 'docid' : record_id }; for (var i in xulG) { my_xulG[i] = xulG[i]; }
    deck.set_iframe( urls.XUL_COPY_VOLUME_BROWSE, {}, my_xulG );
}

function set_edit_pane(deck,record_id) {
    var my_xulG = {
        'record' : { 'url' : '/opac/extras/supercat/retrieve/marcxml/record/' + record_id, "id": record_id, "rtype": "bre" },
        'fast_add_item' : function(doc_id,cn_label,cp_barcode) {
            try {
                return cat.util.fast_item_add(doc_id,cn_label,cp_barcode);
            } catch(E) {
                alert('Error in bibs_abreast.js, set_edit_pane, fast_item_add: ' + E);
            }
        },
        'save' : {
            'label' : document.getElementById('offlineStrings').getString('cat.save_record'),
            'func' : function (new_marcxml) {
                try {
                    var r = network.simple_request('MARC_XML_RECORD_UPDATE', [ ses(), record_id, new_marcxml ]);
                    if (typeof r.ilsevent != 'undefined') {
                        throw(r);
                    } else {
                        return {
                            'id' : r.id(),
                            'oncomplete' : function() {}
                        };
                    }
                } catch(E) {
                    alert('Error in bibs_abreast.js, set_edit_pane, save: ' + E);
                }
            }
        },
        'lock_tab' : xulG.lock_tab(),
        'unlock_tab' : xulG.unlock_tab()
    };
    for (var i in xulG) { my_xulG[i] = xulG[i]; }
    deck.set_iframe( urls.XUL_MARC_EDIT, {}, my_xulG );
}

function merge_records() {
    try {
        var robj = network.simple_request('MERGE_RECORDS',
            [
                ses(),
                lead_record,
                util.functional.filter_list( record_ids,
                    function(o) {
                        return o != lead_record;
                    }
                )
            ]
        );
        if (typeof robj.ilsevent != 'undefined') {
            switch(Number(robj.ilsevent)) {
                case 5000 /* PERM_FAILURE */: break;
                default: throw(robj);
            }
        }
        if (typeof xulG.on_merge == 'function') {
            xulG.on_merge(robj);
        }
        var opac_url = xulG.url_prefix('opac_rdetail') + lead_record;
        var content_params = {
            'session' : ses(),
            'authtime' : ses('authtime'),
            'opac_url' : opac_url,
        };
        xulG.set_tab(
            xulG.url_prefix('XUL_OPAC_WRAPPER'),
            {'tab_name':'Retrieving title...'},
            content_params
        );
    } catch(E) {
        alert('Error in bibs_abreast.js, merge_records(): ' + E);
    }
}
