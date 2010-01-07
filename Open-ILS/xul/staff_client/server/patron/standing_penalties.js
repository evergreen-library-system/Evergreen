function penalty_init() {
    try {
        commonStrings = document.getElementById('commonStrings');
        patronStrings = document.getElementById('patronStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        XML_HTTP_SERVER = data.server_unadorned;

        JSAN.use('util.error'); var error = new util.error();
        JSAN.use('util.network'); var net = new util.network();
        JSAN.use('patron.util'); JSAN.use('util.list'); JSAN.use('util.functional'); JSAN.use('util.widgets');

        var list = new util.list( 'ausp_list' );
        list.init( 
            {
                'columns' : patron.util.ausp_columns({}),
                'map_row_to_columns' : patron.util.std_map_row_to_columns(),
                'retrieve_row' : function(params) { 
                    params.row_node.setAttribute('retrieve_id',params.row.my.ausp.id()); 
                    params.on_retrieve(params.row); 
                    return params.row; 
                },
                'on_select' : function(ev) {
                    var sel = list.retrieve_selection();
                    var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
                    if (ids.length > 0) {
                        document.getElementById('cmd_remove_penalty').setAttribute('disabled','false');
                    } else {
                        document.getElementById('cmd_remove_penalty').setAttribute('disabled','true');
                    }
                }
            } 
        );

        var rows = [];
        for (var i = 0; i < xulG.patron.standing_penalties().length; i++) {
            var row_params = {
                'row' : {
                    'my' : {
                        'ausp' : xulG.patron.standing_penalties()[i],
                        'csp' : xulG.patron.standing_penalties()[i].standing_penalty(),
                        'au' : xulG.patron,
                    }
                }
            };
            rows[ xulG.patron.standing_penalties()[i].id() ] = list.append( row_params );
        };

        var csp_list = document.getElementById('csp_list');
        util.widgets.remove_children(csp_list);
        for (var i = 0; i < data.list.csp.length; i++) {
            if (data.list.csp[i].id() > 100) {
                var menuitem = document.createElement('menuitem'); csp_list.appendChild(menuitem);
                menuitem.setAttribute('label',data.list.csp[i].label());
                menuitem.setAttribute('value',data.list.csp[i].id());
                menuitem.setAttribute('id','csp_'+data.list.csp[i].id());
                if (util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.standing_penalty().id() == data.list.csp[i].id(); } )) {
                    menuitem.setAttribute('disabled','true');
                }
                menuitem.addEventListener(
                    'command',
                    function(ev) {
                        var id = ev.target.getAttribute('value');

                        var note = window.prompt(patronStrings.getString('staff.patron.standing_penalty.note_prompt'),'',patronStrings.getString('staff.patron.standing_penalty.note_title'));

                        var penalty = new ausp();
                        penalty.usr( xulG.patron.id() );
                        penalty.isnew( 1 );
                        penalty.standing_penalty( id );
                        penalty.org_unit( ses('ws_ou') );
                        penalty.note( note );
                        net.simple_request(
                            'FM_AUSP_APPLY', 
                            [ ses(), penalty ],
                            function(reqobj) {
                                var req = reqobj.getResultObject();
                                if (typeof req.ilsevent != 'undefined') {
                                    error.standard_unexpected_error_alert(patronStrings.getFormattedString('staff.patron.standing_penalty.apply_error',[data.hash.csp[id].name()]),req);
                                } else {
                                    penalty.id(req);
                                    xulG.patron.standing_penalties( xulG.patron.standing_penalties().concat( penalty ) );
                                    var row_params = {
                                        'row' : {
                                            'my' : {
                                                'ausp' : penalty,
                                                'csp' : data.hash.csp[ penalty.standing_penalty() ],
                                                'au' : xulG.patron,
                                            }
                                        }
                                    };
                                    rows[ req ] = list.append( row_params );
                                    ev.target.setAttribute('disabled','true');
                                }
                                if (xulG && typeof xulG.refresh == 'function') {
                                    xulG.refresh();
                                }
                                document.getElementById('progress').hidden = true;
                            }
                        );

                        document.getElementById('progress').hidden = false;
                    },
                    false
                );
            }
        }


        document.getElementById('cmd_remove_penalty').addEventListener(
            'command',
            function() {
                var sel = list.retrieve_selection();
                var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
                if (ids.length > 0) {
                    function gen_func(id) {
                        return function() {
                            try {
                                var penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == id; } );
                                penalty.isdeleted(1);

                                var req = net.simple_request( 'FM_AUSP_REMOVE', [ ses(), penalty ] );
                                if (typeof req.ilsevent != 'undefined' || String(req) != '1') {
                                    error.standard_unexpected_error_alert(patronStrings.getFormattedString('staff.patron.standing_penalty.remove_error',[id]),req);
                                } else {
                                    var node = rows[ id ].my_node;
                                    var parentNode = node.parentNode;
                                    parentNode.removeChild( node );
                                    delete(rows[ id ]);
                                    var csp_id = typeof penalty.standing_penalty() == 'object' ? penalty.standing_penalty().id() : penalty.standing_penalty();
                                    document.getElementById('csp_'+csp_id).setAttribute('disabled','false');
                                }
                            } catch(E) {
                                alert(E);
                            }
                        }; 
                    }

                    var funcs = [];
                    for (var i = 0; i < ids.length; i++) {
                        funcs.push( gen_func(ids[i]) );
                    } 
                    funcs.push(
                        function() {
                            if (xulG && typeof xulG.refresh == 'function') {
                                xulG.refresh();
                            }
                            document.getElementById('progress').hidden = true;
                        }
                    );
                    document.getElementById('progress').hidden = false;
                    JSAN.use('util.exec'); var exec = new util.exec();
                    exec.chain(funcs);
                }
            },
            false
        );

        document.getElementById('cmd_edit_penalty').addEventListener(
            'command',
            function() {
                var sel = list.retrieve_selection();
                var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
                if (ids.length > 0) {
                    var note = window.prompt(
                        patronStrings.getString( 'staff.patron.standing_penalty.note_prompt.' + (ids.length == 1 ? 'singular' : 'plural') ),
                        '',
                        patronStrings.getString( 'staff.patron.standing_penalty.note_prompt.title' )
                    );
                    if (note == null) { return; } /* cancel */
                    for (var i = 0; i < ids.length; i++) {
                        var penalty = util.functional.find_list( xulG.patron.standing_penalties(), function(o) { return o.id() == ids[i]; } );
                        penalty.note( note ); /* this is for rendering, and propogates by reference to the object associated with the row in the GUI */
                    } 
                    document.getElementById('progress').hidden = false;
                    net.simple_request( 
                        'FM_AUSP_UPDATE_NOTE', [ ses(), ids, note ],
                        function(reqObj) {
                            var req = reqObj.getResultObject();
                            if (typeof req.ilsevent != 'undefined' || String(req) != '1') {
                                error.standard_unexpected_error_alert(patronStrings.getString('staff.patron.standing_penalty.update_error'),req);
                            } else {
                                for (var i = 0; i < ids.length; i++) {
                                    list.refresh_row( rows[ ids[i] ] );
                                }
                            }
                            if (xulG && typeof xulG.refresh == 'function') {
                                xulG.refresh();
                            }
                            document.getElementById('progress').hidden = true;
                        }
                    );
                }
            },
            false
        );


    } catch(E) {
        alert(E);
    }
}
