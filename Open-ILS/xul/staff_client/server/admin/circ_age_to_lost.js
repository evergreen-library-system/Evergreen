var error;
var data;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for circ_age_to_lost.xul');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        build_pgt_list();
        build_ou_list();

        $('doit').addEventListener('command',doit,false);

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name( $('offlineStrings').getString('menu.cmd_local_admin_age_overdue_circulations_to_lost.tab') ); } catch(E) { alert(E); }
        }

    } catch(E) {
        alert('Error in admin/circ_age_to_lost.xul, my_init(): ' + E);
    }
}

function doit(ev) {
    try {
        $('checkbox').disabled = true;
        ev.target.disabled = true;
        $('deck').selectedIndex = 1;
        var profile = $('profile').value;
        var circ_lib = $('circ_lib').value;

        function response_handler(e,r,list) {
            try {
                var result;
                switch(e) {
                    case 'oncomplete' : return; break;
                    default: result = r.recv().content(); break;
                }
                dump(e + ' result = ' + js2JSON(result) + '\n');
                if (typeof result.progress != 'undefined') {

                    $('results_label').setAttribute('value', $('adminStrings').getFormattedString('staff.admin.age_overdue_circulations_to_lost.chunks_processed',[result.progress]) );

                } else if (typeof result.created != 'undefined') {

                    $('results_label').setAttribute('value', $('adminStrings').getFormattedString('staff.admin.age_overdue_circulations_to_lost.events_created',[result.created]) );
                    $('deck').selectedIndex = 0;

                } else if (typeof result.error != 'undefined') {

                    $('deck').selectedIndex = 0;
                    throw(result.error);

                } else {
                    throw(result);
                }
            } catch(E) {
                $('deck').selectedIndex = 0;
                alert('Error in admin/circ_age_to_lost.js, doit(), ' + e + ': ' + r + ' => ' + E);
            }
        }
        dump('firing ' + api.FM_CIRC_AGE_TO_LOST.method + ' with profile ' + profile + ' and circ_lib ' + circ_lib + '\n');
        fieldmapper.standardRequest(
            [ api.FM_CIRC_AGE_TO_LOST.app, api.FM_CIRC_AGE_TO_LOST.method ],
            {   async: true,
                params: [ses(), { 'user_profile' : profile, 'circ_lib' : circ_lib } ],
                onresponse: function(r) { response_handler('onresponse',r); },
                oncomplete: function(r) { response_handler('oncomplete',r); },
                onerror: function(r) { response_handler('onerror',r); }
            }
        );

    } catch(E) {
        alert('Error in admin/circ_age_to_lost.js, doit(): ' + E);
    }
}

function build_pgt_list() {
    JSAN.use('util.functional'); JSAN.use('util.widgets');
    var default_profile = data.tree.pgt.id();
    var menu_data = util.functional.map_list( 
        data.list.pgt,
        function(obj) { 
            var sname = obj.name();
            for (i = sname.length; i < 20; i++) {
                sname += ' ';
            }
            var depth = 0; var p = obj;
            while (p = data.hash.pgt[ p.parent() ]) { depth++; }
            return [ 
                obj.description() ? sname + ' : ' + obj.description() : obj.name(),
                obj.id(), 
                false, // disable menuentry?
                ( depth * 2) // spaces of indentation
            ]; 
        }
    );
    var ml = util.widgets.make_menulist( menu_data, default_profile );
    ml.setAttribute('id','profile'); $('x_profile').appendChild(ml);
}

function build_ou_list() {
    JSAN.use('util.file'); JSAN.use('util.widgets');
    var file = new util.file('offline_ou_list');
    if (file._file.exists()) {
        var menu_data = file.get_object(); file.close();
        for (var i = 0; i < menu_data[0].length; i++) { // make sure all entries are enabled
            menu_data[0][i][2] = false;
        }
        ml = util.widgets.make_menulist( menu_data[0], menu_data[1] );
        ml.setAttribute('id','circ_lib'); $('x_circ_lib').appendChild(ml);
    } else {
        throw('Missing file offline_ou_list in build_ou_list()');
    }
}

