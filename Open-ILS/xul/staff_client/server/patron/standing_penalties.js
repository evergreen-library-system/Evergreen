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
        JSAN.use('patron.util'); JSAN.use('util.list'); JSAN.use('util.functional');

        var list = new util.list( 'csp_list' );
        list.init( 
            {
                'columns' : patron.util.csp_columns({}),
                'map_row_to_columns' : patron.util.std_map_row_to_columns(),
                'retrieve_row' : function(params) { params.row_node.setAttribute('retrieve_id',params.row.my.csp.id()); params.on_retrieve(params.row); return params.row; },
                'on_select' : function(ev) {
                    var sel = list.retrieve_selection();
                    var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
                    if (ids.length > 0) {
                        document.getElementById('cmd_apply_penalty').setAttribute('disabled','false');
                        document.getElementById('cmd_remove_penalty').setAttribute('disabled','false');
                    } else {
                        document.getElementById('cmd_apply_penalty').setAttribute('disabled','true');
                        document.getElementById('cmd_remove_penalty').setAttribute('disabled','true');
                    }
                }
            } 
        );

        for (var i = 0; i < data.list.csp.length; i++) {
            if (data.list.csp[i].id() > 100 ) {
            //if (true) {
                list.append(
                    {
                        'row' : {
                            'my' : {
                                'csp' : data.list.csp[i],
                                'au' : xulG.patron,
                                'ausp' : util.functional.find_list( xulG.patron.standing_penalties(), function(o) { dump(js2JSON(o) + '\n'); return o.standing_penalty().id() == data.list.csp[i].id(); } )
                            }
                        }
                    }
                );
            }
        };

        document.getElementById('cmd_apply_penalty').addEventListener(
            'command',
            function() {
                var sel = list.retrieve_selection();
                var ids = util.functional.map_list( sel, function(o) { return JSON2js( o.getAttribute('retrieve_id') ); } );
                if (ids.length > 0) {

                    var note = window.prompt(patronStrings.getString('staff.patron.standing_penalty.note_prompt'),'',patronStrings.getString('staff.patron.standing_penalty.note_title'));

                    function gen_func(id) {
                        return function() {
                            var penalty = new ausp();
                            penalty.usr( xulG.patron.id() );
                            penalty.isnew( 1 );
                            penalty.standing_penalty( id );
                            penalty.org_unit( ses('ws_ou') );
                            penalty.note( note );
                            var req = net.simple_request( 'FM_AUSP_APPLY', [ ses(), penalty ] );
                            if (typeof req.ilsevent != 'undefined' || String(req) != '1') {
                                error.standard_unexpected_error_alert(patronStrings.getFormattedString('staff.patron.standing_penalty.apply_error',[data.hash.csp[id].name()]),req);
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

    } catch(E) {
        alert(E);
    }
}
