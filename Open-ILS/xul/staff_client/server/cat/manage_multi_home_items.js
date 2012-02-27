var data; var list; var error; var net; var sound;
var rows = {};
var bpbcm_barcode_map = {};

var commonStrings;
var catStrings;

//// parent interfaces may call this
function default_focus() { document.getElementById('scanbox').focus(); }
////

function my_init() {
    try {
        commonStrings = $('commonStrings');
        catStrings = $('catStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('util.error'); error = new util.error();
        JSAN.use('util.sound'); sound = new util.sound();
        JSAN.use('util.widgets');
        JSAN.use('util.functional');
        JSAN.use('util.list');
        JSAN.use('OpenILS.data'); data = new OpenILS.data();
        data.stash_retrieve();
        JSAN.use('util.network'); net = new util.network();
        dojo.require('openils.PermaCrud');
        JSAN.use('cat.util');

        init_menu();
        init_list();
        $('list_actions').appendChild( list.render_list_actions() );
        list.set_list_actions();
        populate_list();
        $('submit').addEventListener('command', function() { handle_submit(true); }, false);
        $('remove').addEventListener('command', function() { handle_remove(); }, false);
        $('change').addEventListener('command', function() { handle_change(); }, false);
        $('opac').addEventListener('command', function() { handle_opac(); }, false);
        $('scanbox').addEventListener('keypress', handle_keypress, false);
        default_focus();

        if (typeof xulG.set_tab_name == 'function') {
            xulG.set_tab_name(
                catStrings.getFormattedString(
                    'staff.cat.manage_multi_bib_items.tab_name',
                    [ xul_param('docid') ]
                )
            );
        }

        if (! xul_param('no_bib_summary')) {
            if (typeof bib_brief_overlay == 'function') {
                $("bib_brief_groupbox").hidden = false;
                bib_brief_overlay( { 'mvr_id' : xul_param('docid') } );
            }
        }

    } catch(E) {
        alert('Error in manage_multi_home_items.js, my_init(): ' + E);
    }
}

function init_menu() {
    try {
        var ml = util.widgets.make_menulist(
            util.functional.map_list(
                data.list.bpt.sort( function(a,b) {
                    if (a.name().toUpperCase() < b.name().toUpperCase()) return -1;
                    if (a.name().toUpperCase() > b.name().toUpperCase()) return 1;
                    return 0;
                }),
                function(obj) {
                    return [ obj.name(), obj.id() ];
                }
            )
        );
        ml.setAttribute('id','bpt_menu');
        $('menu_placeholder').appendChild(ml);
    } catch(E) {
        alert('Error in manage_multi_home_items.js, init_menu(): ' + E);
    }
}

function init_list() {
    try {
        list = new util.list( 'list' );
        list.init( 
            {
                'retrieve_row' : function(params) {
                    if (params.row.my.bpbcm) {
                        params.treeitem_node.setAttribute('retrieve_id',params.row.my.bpbcm.id());
                    }
                    params.on_retrieve(params.row);
                    return params.row;
                },
                'columns' : [
                    {
                        'id' : 'result',
                        'label' : 'Result',
                        'flex' : 1,
                        'primary' : false,
                        'hidden' : false,
                        'editable' : false, 'render' : function(my) { return my.result; }
                    }
                ].concat(
                    list.fm_columns('acp', {
                        '*' : { 'expanded_label' : false, 'hidden' : true },
                        'acp_barcode' : { 'hidden' : false },
                        'acp_opac_visible' : { 'hidden' : false },
                        'acp_holdable' : { 'hidden' : false }
                    })
                ).concat(
                    list.fm_columns('mvr', {
                        '*' : { 'expanded_label' : false, 'hidden' : true }, 
                        'mvr_title' : { 'hidden' : false },
                        'mvr_author' : { 'hidden' : false },
                        'mvr_isbn' : { 'hidden' : false },
                        'mvr_tcn' : { 'hidden' : false },
                        'mvr_id' : { 'hidden' : false }
                    })
                ).concat(
                    list.fm_columns('bpbcm', {
                        '*' : { 'expanded_label' : false, 'hidden' : true },
                        'bpbcm_peer_type' : {
                            'hidden' : false,
                            'render' : function(my) { return my.bpbcm ? data.hash.bpt[ my.bpbcm.peer_type() ].name() : ''; }
                        }
                    })
                )
            }
        );
    } catch(E) {
        alert('Error in manage_multi_home_items.js, init_list(): ' + E);
    }
}

function handle_keypress(ev) {
    try {
        if (ev.keyCode && ev.keyCode == 13) {
            handle_submit(true);
        }
    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_keypress(): ' + E);
    }
}

function handle_submit(create,my_bpbcm,my_barcode) {
    try {
        var barcode;
        if (create) {
            if (my_barcode) {
                barcode = my_barcode;
            } else {
                barcode = $('scanbox').value;
                $('scanbox').value = '';
                default_focus();
            }
        }

        var placeholder_acp = new acp();
        placeholder_acp.barcode(barcode);
        var row_params = {
            'row' : {
                'my' : {
                    'acp' : placeholder_acp,
                    'bpbcm' : my_bpbcm
                }
            }
        };

        if (barcode && rows[barcode]) {
                var node = rows[barcode].treeitem_node;
                var parentNode = node.parentNode;
                parentNode.removeChild( node );
                delete(rows[barcode]);
        }

        row_params = list.append(row_params);
        if (barcode) {
            rows[barcode] = row_params;
        }

        function handle_req(req) {
            try {
                var robj = req.getResultObject();
                row_params.row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.error');
                if (typeof robj.ilsevent != 'undefined') {
                    row_params.row.my.result = robj.textcode;
                } else {
                    rows[robj.copy.barcode()] = row_params;
                    if (row_params.row.my.bpbcm) {
                        bpbcm_barcode_map[ row_params.row.my.bpbcm.id() ] = robj.copy.barcode();
                    }

                    row_params.row.my.acp = robj.copy;
                    row_params.row.my.mvr = robj.mvr;

                    if (create && robj.mvr.doc_id() != xul_param('docid')) {
                        var new_bpbcm = new bpbcm();
                            new_bpbcm.isnew(1);
                            new_bpbcm.peer_type($('bpt_menu').value);
                            new_bpbcm.peer_record(xul_param('docid'));
                            new_bpbcm.target_copy(robj.copy.id());
                        var pcrud = new openils.PermaCrud( { authtoken :ses() });
                        pcrud.create(new_bpbcm, {
                            "onerror" : function(r) {
                                dump('onerror, r = ' + js2JSON(r) + '\n');
                            },
                            "oncomplete": function (r, objs) {
                                try {
                                    var obj = objs[0];
                                    if (obj) {
                                        row_params.row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.success');
                                        row_params.row.my.bpbcm = obj;
                                        bpbcm_barcode_map[ obj.id() ] = robj.copy.barcode();
                                    } else {
                                        row_params.row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.failed');
                                        sound.bad();
                                    }
                                    list.refresh_row( row_params );
                                } catch(E) {
                                    alert('Error in manage_multi_home_items.js, handle_submit, pcrud create oncomplete callback: ' + E);
                                }
                            }
                        });
                    } else {
                        if (robj.mvr.doc_id() != xul_param('docid')) {
                            row_params.row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.item_linked_to_bib');
                        } else {
                            row_params.row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.item_native_to_bib');
                        }
                    }
                }
                list.refresh_row( row_params );
            } catch(E) {
                alert('Error in manage_multi_home_items.js, handle_submit, acp details callback: ' + E);
            }
        }

        if (my_bpbcm) {
            net.simple_request(
                'FM_ACP_DETAILS', // FIXME: want this to be authoritative
                [ ses(), my_bpbcm.target_copy() ],
                handle_req
            );
        } else {
            net.simple_request(
                'FM_ACP_DETAILS_VIA_BARCODE.authoritative',
                [ ses(), barcode ],
                handle_req
            );
        }

    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_submit(): ' + E);
    }
}

function populate_list() {
    try {
        var pcrud = new openils.PermaCrud( { authtoken :ses() });
        pcrud.search(
            'bpbcm',
            {
                peer_record : xul_param('docid')
            },
            {
                async : true,
                streaming : true,
                onerror : function(r) {
                        alert('Error in manage_multi_home_items.js, populate_list(), pcrud.search onerror: ' + r);
                },
                oncomplete : function() {
                    if (xul_param('barcodes')) { // incoming from Holdings Maintenance
                        handle_barcodes( xul_param('barcodes') );
                    }
                },
                onresponse : function(r) {
                    try {
                        var my_bpbcm = openils.Util.readResponse(r);
                        if (typeof my_bpbcm.ils_event != 'undefined') { throw(my_bpbcm); }
                        handle_submit(false,my_bpbcm);
                    } catch(E) {
                        alert('Error in manage_multi_home_items.js, populate_list(), pcrud.search onresponse: ' + E);
                    }
                }
            }
        );

    } catch(E) {
        alert('Error in manage_multi_home_items.js, populate_list(): ' + E);
    }
}

function handle_change() {
    try {
        var node_list = list.retrieve_selection();
        var eligibles = [];
        for (var i = 0; i < node_list.length; i++) {
            var retrieve_id = node_list[i].getAttribute('retrieve_id');
            if (retrieve_id && retrieve_id != 'undefined') {
                eligibles.push( retrieve_id );
            }
        }
        if (eligibles.length > 0) {
            var new_peer_type = widget_prompt( $('bpt_menu').cloneNode(true), {
                'title' : catStrings.getString('staff.cat.manage_multi_bib_items.prompt.title')
            });

            if (new_peer_type) {
                var bpbcm_list = [];
                for (var i = 0; i < eligibles.length; i++) {
                    var obj = rows[ bpbcm_barcode_map[ eligibles[i] ] ].row.my.bpbcm;
                    obj.ischanged(1);
                    obj.peer_type( new_peer_type );
                    bpbcm_list.push( obj );
                }
                var pcrud = new openils.PermaCrud( { authtoken :ses() });
                pcrud.update(
                    bpbcm_list, {
                        'async' : false,
                        'onerror': function(r) {
                            dump('onerror: ' + r + '\n');
                        },
                        'onresponse': function(r) {
                            dump('onresponse: ' + r + '\n');
                        },
                        'oncomplete': function(r,ids) {
                            dump('oncomplete: r = ' + r + '\n\tids = ' + js2JSON(ids) + '\n');
                            for (var i = 0; i < ids.length; i++) {
                                var bpbcm_id = ids[i];
                                try {
                                    rows[ bpbcm_barcode_map[ bpbcm_id ] ].row.my.bpbcm.peer_type( new_peer_type );
                                    rows[ bpbcm_barcode_map[ bpbcm_id ] ].row.my.result = catStrings.getString('staff.cat.manage_multi_bib_items.result.column.value.peer_type_updated');
                                    list.refresh_row( rows[ bpbcm_barcode_map[ bpbcm_id ] ] );
                                } catch(E) {
                                    alert('error in oncomplete: ' + E);
                                }
                            }
                        }
                    }
                );
            }
        }

    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_change(): ' + E);
    }
}

function handle_remove() {
    try {
        var node_list = list.retrieve_selection();
        var eligibles = [];
        for (var i = 0; i < node_list.length; i++) {
            var retrieve_id = node_list[i].getAttribute('retrieve_id');
            if (retrieve_id && retrieve_id != 'undefined') {
                eligibles.push( retrieve_id );
            }
        }
        if (eligibles.length > 0) {
            if (window.confirm(
                eligibles.length == 1
                ? catStrings.getFormattedString(
                        'staff.cat.manage_multi_bib_items.prompt.confirm.unlink_item_from_bib.singular',
                        [ xul_param('docid') ]
                )
                : catStrings.getFormattedString(
                        'staff.cat.manage_multi_bib_items.prompt.confirm.unlink_item_from_bib.plural',
                        [ xul_param('docid'), eligibles.length ]
                ))
            ) {
                var bpbcm_list = [];
                for (var i = 0; i < eligibles.length; i++) {
                    var obj = rows[ bpbcm_barcode_map[ eligibles[i] ] ].row.my.bpbcm;
                    obj.isdeleted(1);
                    bpbcm_list.push( obj );
                }
                var pcrud = new openils.PermaCrud( { authtoken :ses() });
                pcrud.eliminate(
                    bpbcm_list, {
                        'async' : false,
                        'onerror': function(r) {
                            dump('onerror: ' + r + '\n');
                        },
                        'onresponse': function(r) {
                            dump('onresponse: ' + r + '\n');
                        },
                        'oncomplete': function(r,ids) {
                            dump('oncomplete: r = ' + r + '\n\tids = ' + js2JSON(ids) + '\n');
                            for (var i = 0; i < ids.length; i++) {
                                var bpbcm_id = ids[i];
                                try {
                                    var node = rows[ bpbcm_barcode_map[ bpbcm_id ] ].treeitem_node;
                                    var parentNode = node.parentNode;
                                    parentNode.removeChild( node );
                                    delete(rows[ bpbcm_barcode_map[ bpbcm_id ] ]);
                                } catch(E) {
                                    alert('error in oncomplete: ' + E);
                                }
                            }
                        }
                    }
                );
            }
        }

    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_remove(): ' + E);
    }
}

function handle_opac() {
    try {
        var node_list = list.retrieve_selection();
        var eligibles = [];
        for (var i = 0; i < node_list.length; i++) {
            var retrieve_id = node_list[i].getAttribute('retrieve_id');
            if (retrieve_id && retrieve_id != 'undefined') {
                eligibles.push( retrieve_id );
            }
        }
        if (eligibles.length > 0) {
            var selection_list = [];
            for (var i = 0; i < eligibles.length; i++) {
                selection_list.push({
                    'barcode' : bpbcm_barcode_map[ eligibles[i] ]
                });
            }
            cat.util.show_in_opac(selection_list);
        }

    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_opac(): ' + E);
    }
}

function handle_barcodes(barcodes) {
    try {
        var funcs = [];

        for (var i = 0; i < barcodes.length; i++) {
            if (typeof rows[barcodes[i]] == 'undefined') {
                funcs.push(
                    function(barcode) {

                        return function() {
                            handle_submit(true,null,barcode);
                        };

                    }(barcodes[i])
                )
            }
        }

        JSAN.use('util.exec'); var exec = new util.exec();
        exec.timer( funcs, 500 );

        funcs.push(
            function() {
                exec.clear_timer();
            }
        );

    } catch(E) {
        alert('Error in manage_multi_home_items.js, handle_barcodes(): ' + E);
    }
}
