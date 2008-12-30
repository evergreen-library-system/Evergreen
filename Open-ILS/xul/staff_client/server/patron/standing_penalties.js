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
            if (data.list.csp[i].id() >= 100 ) {
                list.append(
                    {
                        'row' : {
                            'my' : {
                                'csp' : data.list.csp[i],
                                'au' : xulG.patron
                            }
                        }
                    }
                );
            }
        };

    } catch(E) {
        alert(E);
    }
}
