dump('entering cat.z3950.js\n');

function $(id) { return document.getElementById(id); }

if (typeof cat == 'undefined') cat = {};
cat.z3950 = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('cat.z3950: ' + E + '\n');
    }
}

cat.z3950.prototype = {

    'creds_version' : 2,

    'number_of_result_sets' : 0,

    'result_set' : [],

    'limit' : 10,

    'init' : function( params ) {

        try {
            JSAN.use('util.widgets');

            var obj = this;

            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

            obj.load_creds();

            JSAN.use('circ.util');
            var columns = circ.util.columns(
                {
                    'tcn' : { 'hidden' : false },
                    'isbn' : { 'hidden' : false },
                    'title' : { 'hidden' : false, 'flex' : '1' },
                    'author' : { 'hidden' : false },
                    'edition' : { 'hidden' : false },
                    'pubdate' : { 'hidden' : false },
                    'publisher' : { 'hidden' : false },
                    'service' : { 'hidden' : false }
                }
            );

            JSAN.use('util.list'); obj.list = new util.list('results');
            obj.list.init(
                {
                    'columns' : columns,
                    'on_select' : function(ev) {
                        try {
                            JSAN.use('util.functional');
                            var sel = obj.list.retrieve_selection();
                            document.getElementById('sel_clip').setAttribute('disabled', sel.length < 1);
                            var list = util.functional.map_list(
                                sel,
                                function(o) {
                                    if ( $('jacket_image') ) {
                                        // A side-effect in this map function, mu hahaha
                                        if (o.getAttribute('isbn')) {
                                            $('jacket_image').setAttribute('src',urls.ac_jacket_large+o.getAttribute('isbn'));
                                            $('jacket_image').setAttribute('tooltiptext',urls.ac_jacket_large+o.getAttribute('isbn'));
                                        } else {
                                            $('jacket_image').setAttribute('src','');
                                            $('jacket_image').setAttribute('tooltiptext','');
                                        }
                                    }
                                    if (o.getAttribute('service') == 'native-evergreen-catalog') {
                                        $('mark_overlay_btn').disabled = false;
                                        $('show_in_catalog_btn').disabled = false;
                                        obj.controller.view.mark_overlay.setAttribute('doc_id',o.getAttribute('doc_id'));
                                    } else {
                                        $('mark_overlay_btn').disabled = true;
                                        $('show_in_catalog_btn').disabled = true;
                                    }
                                    return o.getAttribute('retrieve_id');
                                }
                            );
                            obj.error.sdump('D_TRACE','cat/z3950: selection list = ' + js2JSON(list) );
                            obj.controller.view.marc_import.disabled = false;
                            obj.controller.view.marc_import.setAttribute('retrieve_id',list[0]);
                            obj.data.init({'via':'stash'});
                            if (obj.data.marked_record) {
                                obj.controller.view.marc_import_overlay.disabled = false;
                            } else {
                                obj.controller.view.marc_import_overlay.disabled = true;
                            }
                            obj.controller.view.marc_import_overlay.setAttribute('retrieve_id',list[0]);
                            obj.controller.view.marc_view_btn.disabled = false;
                            obj.controller.view.marc_view_btn.setAttribute('retrieve_id',list[0]);
                        } catch(E) {
                            obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_list_init.list_construction_error'),E);
                        }
                    },
                }
            );

            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                        'sel_clip' : [ ['command'], function() { obj.list.clipboard(); } ],
                        'cmd_z3950_csv_to_clipboard' : [ ['command'], function() { obj.list.dump_csv_to_clipboard(); } ],
                        'cmd_z3950_csv_to_printer' : [ ['command'], function() { obj.list.dump_csv_to_printer(); } ], 
                        'cmd_z3950_csv_to_file' : [ ['command'], function() { obj.list.dump_csv_to_file( { 'defaultFileName' : 'z3950_results.txt' } ); } ],
                        'cmd_broken' : [
                            ['command'],
                            function() { alert('Not Yet Implemented'); }
                        ],
                        'result_message' : [['render'],function(e){return function(){};}],
                        'clear' : [
                            ['command'],
                            function() {
                                obj.clear();
                            }
                        ],
                        'save_creds' : [
                            ['command'],
                            function() {
                                obj.save_creds();
                                setTimeout( function() { obj.focus(); }, 0 );
                            }
                        ],
                        'marc_view_btn' : [
                            ['render'],
                            function(e) {
                                e.setAttribute('label', $("catStrings").getString('staff.cat.z3950.marc_view.label'));
                                e.setAttribute('accesskey', $("catStrings").getString('staff.cat.z3950.marc_view.accesskey'));
                            }
                        ],
                        'marc_view' : [
                            ['command'],
                            function(ev) {
                                try {
                                    var n = obj.controller.view.marc_view_btn;
                                    if (n.getAttribute('toggle') == '1') {
                                        document.getElementById('deck').selectedIndex = 0;
                                        n.setAttribute('toggle','0');
                                        n.setAttribute('label', $("catStrings").getString('staff.cat.z3950.marc_view.label'));
                                        n.setAttribute('accesskey', $("catStrings").getString('staff.cat.z3950.marc_view.accesskey'));
                                        document.getElementById('results').focus();
                                    } else {
                                        document.getElementById('deck').selectedIndex = 1;
                                        n.setAttribute('toggle','1');
                                        n.setAttribute('label', $("catStrings").getString('staff.cat.z3950.results_view.label'));
                                        n.setAttribute('accesskey', $("catStrings").getString('staff.cat.z3950.results_view.accesskey'));
                                        var f = get_contentWindow(document.getElementById('marc_frame'));
                                        var retrieve_id = n.getAttribute('retrieve_id');
                                        var result_idx = retrieve_id.split('-')[0];
                                        var record_idx = retrieve_id.split('-')[1];
                                        f.xulG = { 'marcxml' : obj.result_set[result_idx].records[ record_idx ].marcxml };
                                        f.my_init();
                                        f.document.body.firstChild.focus();
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_controller_init.marc_view_error'),E);
                                }
                            },
                        ],
                        'mark_overlay' : [
                            ['command'],
                            function() {
                                try {
                                    var doc_id = obj.controller.view.mark_overlay.getAttribute('doc_id');
                                    if (doc_id) {
                                        cat.util.mark_for_overlay(doc_id);
                                    }
                                } catch(E) {
                                    alert('Error in z3950.js, mark_overlay: ' + E);
                                }
                            }
                        ],
                        'show_in_catalog' : [
                            ['command'],
                            function() {
                                try {
                                    var doc_id = obj.controller.view.mark_overlay.getAttribute('doc_id');
                                    if (doc_id) {
                                        var opac_url = xulG.url_prefix('opac_rdetail') + doc_id;
                                        var content_params = { 
                                            'session' : ses(),
                                            'authtime' : ses('authtime'),
                                            'opac_url' : opac_url,
                                        };
                                        xulG.new_tab(
                                                     xulG.url_prefix('XUL_OPAC_WRAPPER'), 
                                                     {'tab_name': $("catStrings").getString('staff.cat.z3950.replace_tab_with_opac.tab_name')}, 
                                                     content_params
                                                     );
                                    }
                                } catch(E) {
                                    alert('Error in z3950.js, show_in_catalog: ' + E);
                                }
                            }
                        ],
                        'marc_import' : [
                            ['command'],
                            function() {
                                try {
                                    var retrieve_id = obj.controller.view.marc_import.getAttribute('retrieve_id');
                                    var result_idx = retrieve_id.split('-')[0];
                                    var record_idx = retrieve_id.split('-')[1];
                                    obj.spawn_marc_editor( 
                                        obj.result_set[ result_idx ].records[ record_idx ].marcxml,
                                        obj.result_set[ result_idx ].records[ record_idx ].service /* FIXME: we want biblio_source here */
                                    );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_controller_init.marc_import_error'),E);
                                }
                            },
                        ],
                        'marc_import_overlay' : [ 
                            ['command'],
                            function() {
                                try {
                                    var retrieve_id = obj.controller.view.marc_import_overlay.getAttribute('retrieve_id');
                                    var result_idx = retrieve_id.split('-')[0];
                                    var record_idx = retrieve_id.split('-')[1];
                                    obj.spawn_marc_editor_for_overlay( 
                                        obj.result_set[ result_idx ].records[ record_idx ].marcxml,
                                        obj.result_set[ result_idx ].records[ record_idx ].service /* FIXME: we want biblio_source here */
                                    );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_controller_init.marc_import_overlay_error'),E);
                                }
                            },
                        ],
                        'search' : [
                            ['command'],
                            function() {
                                obj.initial_search();
                            },
                        ],
                        'raw_search' : [ 
                            ['command'], 
                            function() { 
                                var raw = window.prompt(
                                    $("catStrings").getString('staff.cat.z3950.initial_search.raw_prompt.msg'),
                                    $("catStrings").getString('staff.cat.z3950.initial_search.raw_prompt.default_value'),
                                    $("catStrings").getString('staff.cat.z3950.initial_search.raw_prompt.title')
                                ); 
                                if (raw) obj.initial_raw_search(raw); 
                            } 
                        ], 
                        'page_next' : [
                            ['command'],
                            function() {
                                obj.page_next();
                            },
                        ],
                        'toggle_form_btn' : [
                            ['render'],
                            function(e) {
                                e.setAttribute('image',"/xul/server/skin/media/images/up_arrow.gif");
                                e.setAttribute('label',$("catStrings").getString('staff.cat.z3950.hide_top_pane.label'));
                                e.setAttribute('accesskey',$("catStrings").getString('staff.cat.z3950.hide_top_pane.accesskey'));
                            }
                        ],
                        'toggle_form' : [
                            ['command'],
                            function() {
                                var x = document.getElementById('top_pane');
                                document.getElementById('splitter_grippy2').doCommand();
                                var n = obj.controller.view.toggle_form_btn;
                                if (x.collapsed) {
                                    n.setAttribute('image',"/xul/server/skin/media/images/down_arrow.gif");
                                    n.setAttribute('label',$("catStrings").getString('staff.cat.z3950.unhide_top_pane.label'));
                                    n.setAttribute('accesskey',$("catStrings").getString('staff.cat.z3950.unhide_top_pane.accesskey'));
                                } else {
                                    n.setAttribute('image',"/xul/server/skin/media/images/up_arrow.gif");
                                    n.setAttribute('label',$("catStrings").getString('staff.cat.z3950.hide_top_pane.label'));
                                    n.setAttribute('accesskey',$("catStrings").getString('staff.cat.z3950.hide_top_pane.accesskey'));
                                }
                            },
                        ],
                        'splitter_grippy2' : [
                            ['click'],
                            function() {
                                var x = document.getElementById('top_pane');
                                var n = obj.controller.view.toggle_form_btn;
                                if (x.collapsed) {
                                    n.setAttribute('image',"/xul/server/skin/media/images/down_arrow.gif");
                                    n.setAttribute('label',$("catStrings").getString('staff.cat.z3950.unhide_top_pane.label'));
                                    n.setAttribute('accesskey',$("catStrings").getString('staff.cat.z3950.unhide_top_pane.accesskey'));
                                } else {
                                    n.setAttribute('image',"/xul/server/skin/media/images/up_arrow.gif");
                                    n.setAttribute('label',$("catStrings").getString('staff.cat.z3950.hide_top_pane.label'));
                                    n.setAttribute('accesskey',$("catStrings").getString('staff.cat.z3950.hide_top_pane.accesskey'));
                                }
                            }
                        ],
                        'service_rows' : [
                            ['render'],
                            function(e) {
                                return function() {
                                    try {

                                        function handle_switch(node) {
                                            try {
                                                $('search').setAttribute('disabled','true'); $('raw_search').setAttribute('disabled','true');
                                                obj.active_services = [];
                                                var snl = document.getElementsByAttribute('mytype','service_class');
                                                for (var i = 0; i < snl.length; i++) {
                                                    var n = snl[i];
                                                    if (n.nodeName == 'checkbox') {
                                                        if (n.checked) obj.active_services.push( n.getAttribute('service') );
                                                    }
                                                }
                                                if (obj.active_services.length > 0) {
                                                    $('search').setAttribute('disabled','false'); 
                                                }
                                                if (obj.active_services.length == 1) {
                                                    if (obj.active_services[0] != 'native-evergreen-catalog') { 
                                                        $('raw_search').setAttribute('disabled','false');
                                                    }
                                                }
                                                var nl = document.getElementsByAttribute('mytype','search_class');
                                                for (var i = 0; i < nl.length; i++) { nl[i].disabled = true; }
                                                var attrs = {};
                                                for (var j = 0; j < obj.active_services.length; j++) {
                                                    if (obj.services[obj.active_services[j]]) for (var i in obj.services[obj.active_services[j]].attrs) {
                                                        var attr = obj.services[obj.active_services[j]].attrs[i];
                                                        if (! attrs[i]) {
                                                            attrs[i] = { 'labels' : {} };
                                                        }
                                                        if (attr.label) {
                                                            attrs[i].labels[ attr.label ] = true;
                                                        } else if (document.getElementById('commonStrings').testString('staff.z39_50.search_class.' + i)) {
                                                            attrs[i].labels[ document.getElementById('commonStrings').getString('staff.z39_50.search_class.' + i) ] = true;
                                                        } else if (attr.name) {
                                                            attrs[i].labels[ attr.name ] = true;
                                                        } else {
                                                            attrs[i].labels[ i ] = true;
                                                        }

                                                    }
                                                    
                                                }

                                                function set_label(x,attr) {
                                                    var labels = [];
                                                    for (var j in attrs[attr].labels) {
                                                        labels.push(j);
                                                    }
                                                    if (labels.length > 0) {
                                                        x.setAttribute('value',labels[0]);
                                                        x.setAttribute('tooltiptext',labels.join(','));
                                                        if (labels.length > 1) x.setAttribute('class','multiple_labels');
                                                    }
                                                }

                                                for (var i in attrs) {
                                                    var x = document.getElementById(i + '_input');
                                                    if (x) {
                                                        x.disabled = false;
                                                        var y = document.getElementById(i + '_label',i);
                                                        if (y) set_label(y,i);
                                                    } else {
                                                        var rows = document.getElementById('query_inputs');
                                                        var row = document.createElement('row'); rows.appendChild(row);
                                                        var label = document.createElement('label');
                                                        label.setAttribute('id',i+'_label');
                                                        label.setAttribute('control',i+'_input');
                                                        label.setAttribute('search_class',i);
                                                        label.setAttribute('style','-moz-user-focus: ignore');
                                                        row.appendChild(label);
                                                        set_label(label,i);
                                                        label.addEventListener('click',function(ev){
                                                                var a = ev.target.getAttribute('search_class');
                                                                if (a) obj.default_attr = a;
                                                            },false
                                                        );
                                                        var tb = document.createElement('textbox');
                                                        tb.setAttribute('id',i+'_input');
                                                        tb.setAttribute('mytype','search_class');
                                                        tb.setAttribute('search_class',i);
                                                        row.appendChild(tb);
                                                        tb.addEventListener('keypress',function(ev) { return obj.handle_enter(ev); },false);
                                                    }
                                                }
                                            } catch(E) {
                                                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_controller_init.search_fields_error'),E);
                                            }
                                        }

                                        document.getElementById('native-evergreen-catalog_service').addEventListener('command',handle_switch,false);

                                        var robj = obj.network.simple_request(
                                            'RETRIEVE_Z3950_SERVICES',
                                            [ ses() ]
                                        );
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                        obj.services = robj;
                                        var x = document.getElementById('service_rows');
                                        var services = new Array();
                                        for (var i in obj.services) {
                                            var label;
                                            if (obj.services[i].label) {
                                                label = obj.services[i].label;
                                            } else if (obj.services[i].name) {
                                                label = obj.services[i].name;
                                            } else {
                                                label = i;
                                            }
                                            var j = [label, i];
                                            services.push(j);
                                        }
                                        services.sort();
                                        for (var j=0; j < services.length; j++) {
                                            var i = services[j][1];
                                            try {
                                                if (i == 'native-evergreen-catalog') continue;
                                                var r = document.createElement('row'); x.appendChild(r);
                                                var cb = document.createElement('checkbox'); 
                                                    cb.setAttribute('label',services[j][0]);
                                                    cb.setAttribute('tooltiptext',i + ' : ' + obj.services[i].db + '@' + obj.services[i].host + ':' + obj.services[i].port); 
                                                    cb.setAttribute('mytype','service_class'); cb.setAttribute('service',i);
                                                    cb.setAttribute('id',i+'_service'); r.appendChild(cb);
                                                    cb.addEventListener('command',handle_switch,false);
                                                var username = document.createElement('textbox'); username.setAttribute('id',i+'_username'); 
                                                if (obj.creds.hosts[ obj.data.server_unadorned ] && obj.creds.hosts[ obj.data.server_unadorned ].services[i]) username.setAttribute('value',obj.creds.hosts[ obj.data.server_unadorned ].services[i].username);
                                                r.appendChild(username);
                                                if (typeof obj.services[i].auth != 'undefined') username.hidden = ! get_bool( obj.services[i].auth );
                                                var password = document.createElement('textbox'); password.setAttribute('id',i+'_password'); 
                                                if (obj.creds.hosts[ obj.data.server_unadorned ] && obj.creds.hosts[ obj.data.server_unadorned ].services[i]) password.setAttribute('value',obj.creds.hosts[ obj.data.server_unadorned ].services[i].password);
                                                password.setAttribute('type','password'); r.appendChild(password);
                                                if (typeof obj.services[i].auth != 'undefined') password.hidden = ! get_bool( obj.services[i].auth );
                                            } catch(E) {
                                                alert(E);
                                            }
                                        }
                                        //obj.services[ 'native-evergreen-catalog' ] = { 'attrs' : { 'author' : {}, 'title' : {} } };
                                        setTimeout(
                                            function() { 
                                                if (obj.creds.hosts[ obj.data.server_unadorned ]) {
                                                    for (var i = 0; i < obj.creds.hosts[ obj.data.server_unadorned ].default_services.length; i++) {
                                                        var x = document.getElementById(obj.creds.hosts[ obj.data.server_unadorned ].default_services[i]+'_service');
                                                        if (x) x.checked = true;
                                                    }
                                                } else if (obj.creds.default_service) {
                                                    var x = document.getElementById(obj.creds.default_service+'_service');
                                                    if (x) x.checked = true;
                                                }
                                                handle_switch();
                                            },0
                                        );
                                    } catch(E) {
                                        obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.obj_controller_init.z39_service_error'),E);
                                    }
                                }
                            }
                        ],
                    }
                }
            );

            obj.controller.render();

            setTimeout( function() { obj.focus(); }, 0 );

            setInterval( 
                function() {
                    obj.data.init({'via':'stash'});
                    if (obj.data.marked_record) {
                        var sel = obj.list.retrieve_selection();
                        if (sel.length > 0) { obj.controller.view.marc_import_overlay.disabled = false; }
                        if ($("overlay_tcn_indicator")) {
                            if (obj.data.marked_record_mvr) {
                                $("overlay_tcn_indicator").setAttribute('value',$("catStrings").getFormattedString('staff.cat.z3950.marked_record_for_overlay_indicator.tcn.label',[obj.data.marked_record_mvr.tcn()]));
                            } else {
                                $("overlay_tcn_indicator").setAttribute('value',$("catStrings").getFormattedString('staff.cat.z3950.marked_record_for_overlay_indicator.record_id.label',[obj.data.marked_record]));
                            }
                        }
                    } else {
                        obj.controller.view.marc_import_overlay.disabled = true;
                        if ($("overlay_tcn_indicator")) {
                            $("overlay_tcn_indicator").setAttribute('value',$("catStrings").getString('staff.cat.z3950.marked_record_for_overlay_indicator.no_record.label'));
                        }
                    }
                }, 2000
            );

        } catch(E) {
            this.error.sdump('D_ERROR','cat.z3950.init: ' + E + '\n');
        }
    },

    'focus' : function() {
        var obj = this;
        var focus_me; var or_focus_me;
        for (var i = 0; i < obj.active_services.length; i++) {
            if (obj.creds.hosts[ obj.data.server_unadorned ] && obj.creds.hosts[ obj.data.server_unadorned ].services[ obj.active_services[i] ]) {
                var x = obj.creds.hosts[ obj.data.server_unadorned ].services[ obj.active_services[i] ].default_attr;
                if (x) { focus_me = x; break; }
            }
            if (obj.services[ obj.active_services[i] ]) for (var i in obj.services[ obj.active_services[i] ].attr) { or_focus_me = i; }
        }
        if (! focus_me) focus_me = or_focus_me;
        var xx = document.getElementById(focus_me+'_input'); if (xx) xx.focus();
    },

    'clear' : function() {
        var obj = this;
        var nl = document.getElementsByAttribute('mytype','search_class');
        for (var i = 0; i < nl.length; i++) { nl[i].value = ''; nl[i].setAttribute('value',''); }
        obj.focus();
    },

    'search_params' : {},

    'initial_search' : function() {
        try {
            var obj = this;
            obj.result_set = []; obj.number_of_result_sets = 0;
            JSAN.use('util.widgets');
            util.widgets.remove_children( obj.controller.view.result_message );
            var x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
            if (obj.active_services.length < 1) {
                x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.no_search_selection')));
                return;
            }
            x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.searching')));
            obj.search_params = {}; obj.list.clear();
            obj.controller.view.page_next.disabled = true;
            obj.controller.view.cmd_z3950_csv_to_file.setAttribute('disabled','true');
            obj.controller.view.cmd_z3950_csv_to_clipboard.setAttribute('disabled','true');
            obj.controller.view.cmd_z3950_csv_to_printer.setAttribute('disabled','true');

            obj.search_params.service_array = []; 
            obj.search_params.username_array = [];
            obj.search_params.password_array = [];
            for (var i = 0; i < obj.active_services.length; i++) {
                obj.search_params.service_array.push( obj.active_services[i] );
                obj.search_params.username_array.push( document.getElementById( obj.active_services[i]+'_username' ).value );
                obj.search_params.password_array.push( document.getElementById( obj.active_services[i]+'_password' ).value );
            }
            obj.search_params.limit = Math.ceil( obj.limit / obj.active_services.length );
            obj.search_params.offset = 0;

            obj.search_params.search = {};
            var nl = document.getElementsByAttribute('mytype','search_class');
            var count = 0;
            for (var i = 0; i < nl.length; i++) {
                if (nl[i].disabled) continue;
                if (nl[i].value == '') continue;
                count++;
                obj.search_params.search[ nl[i].getAttribute('search_class') ] = nl[i].value;
            }
            if (count>0) {
                obj.search();
            } else {
                util.widgets.remove_children( obj.controller.view.result_message );
            }
        } catch(E) {
            this.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.initial_search.failed_search'),E);
        }
    },

    'initial_raw_search' : function(raw) {
        try {
            var obj = this;
            obj.result_set = []; obj.number_of_result_sets = 0;
            JSAN.use('util.widgets');
            util.widgets.remove_children( obj.controller.view.result_message );
            var x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
            if (obj.active_services.length < 1) {
                x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.no_search_selection')));
                return;
            }
            if (obj.active_services.length > 1) {
                x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.too_many_selections')));
                return;
            }
            if (obj.active_services[0] == 'native-evergreen-catalog') {
                x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.raw_search_unsupported_for_native_catalog')));
                return;
            }
            x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.initial_search.searching')));
            obj.search_params = {}; obj.list.clear();
            obj.controller.view.page_next.disabled = true;
            obj.controller.view.cmd_z3950_csv_to_file.setAttribute('disabled','true');
            obj.controller.view.cmd_z3950_csv_to_clipboard.setAttribute('disabled','true');
            obj.controller.view.cmd_z3950_csv_to_printer.setAttribute('disabled','true');

            obj.search_params.service_array = []; 
            obj.search_params.username_array = [];
            obj.search_params.password_array = [];
            for (var i = 0; i < obj.active_services.length; i++) {
                obj.search_params.service_array.push( obj.active_services[i] );
                obj.search_params.username_array.push( document.getElementById( obj.active_services[i]+'_username' ).value );
                obj.search_params.password_array.push( document.getElementById( obj.active_services[i]+'_password' ).value );
            }
            obj.search_params.limit = Math.ceil( obj.limit / obj.active_services.length );
            obj.search_params.offset = 0;

            obj.search_params.query = raw;

            obj.search();
        } catch(E) {
            this.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.initial_search.failed_search'),E);
        }
    },

    'page_next' : function() {
        try {
            var obj = this;
            JSAN.use('util.widgets');
            util.widgets.remove_children( obj.controller.view.result_message );
            var x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
            x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.page_next.more_results')));
            obj.search_params.offset += obj.search_params.limit;
            obj.search();
        } catch(E) {
            this.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.page_next.subsequent_search_error'),E);
        }
    },

    'search' : function() {
        try {
            var obj = this;
            var method;
            if (typeof obj.search_params.query == 'undefined') {
                method = 'FM_BLOB_RETRIEVE_VIA_Z3950_SEARCH';
                obj.search_params.service = obj.search_params.service_array;
                obj.search_params.username = obj.search_params.username_array;
                obj.search_params.password = obj.search_params.password_array;
            } else {
                method = 'FM_BLOB_RETRIEVE_VIA_Z3950_RAW_SEARCH';
                obj.search_params.service = obj.search_params.service_array[0];
                obj.search_params.username = obj.search_params.username_array[0];
                obj.search_params.password = obj.search_params.password_array[0];
            }
            obj.network.simple_request(
                method,
                [ ses(), obj.search_params ],
                function(req) {
                    obj.handle_results(req.getResultObject())
                }
            );
            document.getElementById('deck').selectedIndex = 0;
        } catch(E) {
            this.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.search.search_error'),E);
        }
    },

    'handle_results' : function(results) {
        var obj = this;
        try {
            JSAN.use('util.widgets');
            util.widgets.remove_children( obj.controller.view.result_message ); var x;
            if (results == null) {
                x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
                x.appendChild( document.createTextNode($("catStrings").getString('staff.cat.z3950.handle_results.null_server_error')));
                return;
            }
            if (typeof results.ilsevent != 'undefined') {
                x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
                x.appendChild( document.createTextNode($("catStrings").getFormattedString('staff.cat.z3950.handle_results.server_error', [results.textcode, results.desc])));
                return;
            }
            obj.controller.view.cmd_z3950_csv_to_file.setAttribute('disabled','false');
            obj.controller.view.cmd_z3950_csv_to_clipboard.setAttribute('disabled','false');
            obj.controller.view.cmd_z3950_csv_to_printer.setAttribute('disabled','false');
            if (typeof results.length == 'undefined') results = [ results ];

            var total_showing = 0;
            var total_count = 0;
            var tooltip_msg = '';

            for (var i = 0; i < results.length; i++) {
                if (results[i].query) {
                    tooltip_msg += $("catStrings").getFormattedString('staff.cat.z3950.handle_results.raw_query', [results[i].query]) + '\n';
                }
                if (results[i].count) {
                    if (results[i].records) {
                        var showing = obj.search_params.offset + results[i].records.length; 
                        total_showing += obj.search_params.offset + results[i].records.length; 
                        total_count += results[i].count;
                        tooltip_msg += $("catStrings").getFormattedString('staff.cat.z3950.handle_results.showing_results', [(showing > results[i].count ? results[i].count : showing), results[i].count, results[i].service]) + '\n';
                    }
                    if (obj.search_params.offset + obj.search_params.limit <= results[i].count) {
                        obj.controller.view.page_next.disabled = false;
                    }
                } else {
                    tooltip_msg += $("catStrings").getFormattedString('staff.cat.z3950.handle_results.num_of_results', [(results[i].count ? results[i].count : 0)]) + '\n';
                }
                if (results[i].records) {
                    obj.result_set[ ++obj.number_of_result_sets ] = results[i];
                    obj.controller.view.marc_import.disabled = true;
                    obj.controller.view.marc_import_overlay.disabled = true;
                    var x = obj.controller.view.marc_view_btn;
                    if (x.getAttribute('toggle') == '0') x.disabled = true;
                    for (var j = 0; j < obj.result_set[ obj.number_of_result_sets ].records.length; j++) {
                        var f;
                        var n = obj.list.append(
                            {
                                'retrieve_id' : String( obj.number_of_result_sets ) + '-' + String( j ),
                                'row' : {
                                    'my' : {
                                        'mvr' : function(a){
                                            if (a.bibid) {
                                                // We have col definitions, etc.
                                                // expecting doc_id
                                                a.mvr.doc_id( a.bibid );
                                            }
                                            return a.mvr;
                                        }(obj.result_set[ obj.number_of_result_sets ].records[j]),
                                        'service' : results[i].service
                                    }
                                }
                            }
                        );
                        n.treeitem_node.setAttribute('isbn', function(a){return a;}(obj.result_set[ obj.number_of_result_sets ].records[j].mvr).isbn());
                        n.treeitem_node.setAttribute(
                            'service',
                            function(a){return a;}(
                                results[i].service
                            )
                        );
                        n.treeitem_node.setAttribute(
                            'doc_id',
                            function(a){return a;}(
                                (obj.result_set[ obj.number_of_result_sets ].records[j].mvr)
                            ).doc_id()
                        );

                        if (!f) { n.treeitem_node.parentNode.focus(); f = n; } 
                    }
                } else {
                    x = document.createElement('description'); obj.controller.view.result_message.appendChild(x);
                    x.appendChild(
                        document.createTextNode($("catStrings").getString('staff.cat.z3950.handle_results.result_error'))
                    );
                }
            }
            if (total_showing) {
                x = document.createElement('description'); 
                x.setAttribute('crop','end');
                x.setAttribute('tooltiptext',tooltip_msg);
                obj.controller.view.result_message.appendChild(x);
                x.appendChild(
                    document.createTextNode($("catStrings").getFormattedString('staff.cat.z3950.handle_results.showing_total_results',
                        [(total_showing > total_count ? total_count : total_showing), total_count]))
                );
            } else {
                x = document.createElement('description'); 
                x.setAttribute('crop','end');
                x.setAttribute('tooltiptext',tooltip_msg);
                obj.controller.view.result_message.appendChild(x);
                x.appendChild(
                    document.createTextNode($("catStrings").getFormattedString('staff.cat.z3950.handle_results.num_of_results', [(total_count ? total_count : 0)]))
                );
            }            

        } catch(E) {
            this.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.handle_results.search_result_error'),E);
        }
    },

    'replace_tab_with_opac' : function(doc_id) {
        var opac_url = xulG.url_prefix('opac_rdetail') + doc_id;
        var content_params = { 
            'session' : ses(),
            'authtime' : ses('authtime'),
            'opac_url' : opac_url,
        };
        xulG.set_tab(
            xulG.url_prefix('XUL_OPAC_WRAPPER'), 
            {'tab_name': $("catStrings").getString('staff.cat.z3950.replace_tab_with_opac.tab_name')}, 
            content_params
        );
    },

    'spawn_marc_editor' : function(my_marcxml,biblio_source) {
        var obj = this;

        function save_marc (new_marcxml) {
            try {
                var r = obj.network.simple_request('MARC_XML_RECORD_IMPORT', [ ses(), new_marcxml, biblio_source ]);
                if (typeof r.ilsevent != 'undefined') {
                    switch(Number(r.ilsevent)) {
                        case 1704 /* TCN_EXISTS */ :
                            var msg = $("catStrings").getFormattedString('staff.cat.z3950.spawn_marc_editor.same_tcn', [r.payload.tcn]);
                            var title = $("catStrings").getString('staff.cat.z3950.spawn_marc_editor.title');
                            var btn1 = $("catStrings").getString('staff.cat.z3950.spawn_marc_editor.btn1_overlay');
                            var btn2 = typeof r.payload.new_tcn == 'undefined' ? null : $("catStrings").getFormattedString('staff.cat.z3950.spawn_marc_editor.btn2_import', [r.payload.new_tcn]);
                            if (btn2) {
                                obj.data.init({'via':'stash'});
                                var robj = obj.network.simple_request(
                                    'PERM_CHECK',[
                                        ses(),
                                        obj.data.list.au[0].id(),
                                        obj.data.list.au[0].ws_ou(),
                                        [ 'ALLOW_ALT_TCN' ]
                                    ]
                                );
                                if (typeof robj.ilsevent != 'undefined') {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.permission_error'),E);
                                }
                                if (robj.length != 0) btn2 = null;
                            }
                            var btn3 = $("catStrings").getString('staff.cat.z3950.spawn_marc_editor.btn3_cancel_import');
                            var p = obj.error.yns_alert(msg,title,btn1,btn2,btn3,$("catStrings").getString('staff.cat.z3950.spawn_marc_editor.confirm_action'));
                            obj.error.sdump('D_ERROR','option ' + p + 'chosen');
                            switch(p) {
                                case 0:
                                    var r3 = obj.network.simple_request('MARC_XML_RECORD_UPDATE', [ ses(), r.payload.dup_record, new_marcxml, biblio_source ]);
                                    if (typeof r3.ilsevent != 'undefined') {
                                        throw(r3);
                                    } else {
                                        alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.successful_overlay'));
                                        return {
                                            'id' : r3.id(),
                                            'on_complete' : function() {
                                                try {
                                                    obj.replace_tab_with_opac(r3.id());
                                                } catch(E) {
                                                    alert(E);
                                                }
                                            }
                                        };
                                    }
                                break;
                                case 1:
                                    var r2 = obj.network.request(
                                        api.MARC_XML_RECORD_IMPORT.app,
                                        api.MARC_XML_RECORD_IMPORT.method + '.override',
                                        [ ses(), new_marcxml, biblio_source ]
                                    );
                                    if (typeof r2.ilsevent != 'undefined') {
                                        throw(r2);
                                    } else {
                                        alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.successful_import_with_new_tcn'));
                                        return {
                                            'id' : r2.id(),
                                            'on_complete' : function() {
                                                try {
                                                    obj.replace_tab_with_opac(r2.id());
                                                } catch(E) {
                                                    alert(E);
                                                }
                                            }
                                        };
                                    }
                                break;
                                case 2:
                                default:
                                    alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.import_cancelled'));
                                break;
                            }
                        break;
                        default:
                            throw(r);
                        break;
                    }
                } else {
                    alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.successful_import'));
                    return {
                        'id' : r.id(),
                        'on_complete' : function() {
                            try {
                                obj.replace_tab_with_opac(r.id());
                            } catch(E) {
                                alert(E);
                            }
                        }
                    };
                }
            } catch(E) {
                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor.import_error'),E);
            }
        };

        if ( $('marc_editor').checked ) {
            xulG.new_tab(
                xulG.url_prefix('XUL_MARC_EDIT'), 
                { 'tab_name' : 'MARC Editor' }, 
                { 
                    'marc_control_number_identifier': obj.data.hash.aous['cat.marc_control_number_identifier'] || 'Set cat.marc_control_number_identifier in Library Settings',
                    'record' : { 'marc' : my_marcxml, "rtype": "bre" },
                    'fast_add_item' : function(doc_id,cn_label,cp_barcode) {
                        try {
                            JSAN.use('cat.util'); return cat.util.fast_item_add(doc_id,cn_label,cp_barcode);
                        } catch(E) {
                            alert(E);
                        }
                    },
                    'save' : {
                        'label' : $("catStrings").getString('staff.cat.z3950.spawn_marc_editor.save_button_label'),
                        'func' : save_marc
                    },
                    'lock_tab' : xulG.lock_tab,
                    'unlock_tab' : xulG.unlock_tab
                } 
            );
        } else {
            save_marc(my_marcxml);
        }
    },

    'confirm_overlay' : function(record_ids) {
        var obj = this; // JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
        top_xml += '<description>'+$("catStrings").getString('staff.cat.z3950.confirm_overlay.description')+'</description>';
        top_xml += '<hbox><button id="lead" disabled="false" label="'+$("catStrings").getString('staff.cat.z3950.confirm_overlay.lead.label')+'" name="fancy_submit"';
        top_xml += ' accesskey="'+$("catStrings").getString('staff.cat.z3950.confirm_overlay.lead.accesskey')+'"/>';
        top_xml += ' <button label="'+$("catStrings").getString('staff.cat.z3950.confirm_overlay.cancel.label')+'" accesskey="'+
                        $("catStrings").getString('staff.cat.z3950.confirm_overlay.cancel.accesskey')+'" name="fancy_cancel"/></hbox></vbox>';

        var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
        xml += '<table width="100%"><tr valign="top">';
        for (var i = 0; i < record_ids.length; i++) {
            xml += '<td nowrap="nowrap"><iframe src="' + urls.XUL_BIB_BRIEF; 
            xml += '?docid=' + record_ids[i] + '" oils_force_external="true"/></td>';
        }
        xml += '</tr><tr valign="top">';
        for (var i = 0; i < record_ids.length; i++) {
            xml += '<td nowrap="nowrap"><iframe style="min-height: 1000px; min-width: 300px;" flex="1" src="' + urls.XUL_MARC_VIEW + '?docid=' + record_ids[i] + ' " oils_force_external="true"/></td>';
        }
        xml += '</tr></table></form>';
        // data.temp_merge_top = top_xml; data.stash('temp_merge_top');
        // data.temp_merge_mid = xml; data.stash('temp_merge_mid');
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            urls.XUL_FANCY_PROMPT,
            // + '?xml_in_stash=temp_merge_mid'
            // + '&top_xml_in_stash=temp_merge_top'
            // + '&title=' + window.escape('Record Overlay'),
            'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
            { 'top_xml' : top_xml, 'xml' : xml, 'title' : $("catStrings").getString('staff.cat.z3950.confirm_overlay.title') }
        );
        //data.stash_retrieve();
        if (fancy_prompt_data.fancy_status == 'incomplete') { alert($("catStrings").getString('staff.cat.z3950.confirm_overlay.aborted')); return false; }
        return true;
    },

    'spawn_marc_editor_for_overlay' : function(my_marcxml,biblio_source) {
        var obj = this;
        obj.data.init({'via':'stash'});
        if (!obj.data.marked_record) {
            alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.try_again'));
            return;
        }

        function overlay_marc (new_marcxml) {
            try {
                if (! obj.confirm_overlay( [ obj.data.marked_record ] ) ) { return; }
                var r = obj.network.simple_request('MARC_XML_RECORD_REPLACE', [ ses(), obj.data.marked_record, new_marcxml, biblio_source ]);
                if (typeof r.ilsevent != 'undefined') {
                    switch(Number(r.ilsevent)) {
                        case 1704 /* TCN_EXISTS */ :
                            var msg = $("catStrings").getFormattedString('staff.cat.z3950.spawn_marc_editor_for_overlay.same_tcn', [r.payload.tcn]);
                            var title = $("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.import_collision');
                            var btn1 = typeof r.payload.new_tcn == 'undefined' ? null : $("catStrings").getFormattedString('staff.cat.z3950.spawn_marc_editor_for_overlay.btn1_overlay', [r.payload.new_tcn]);
                            if (btn1) {
                                var robj = obj.network.simple_request(
                                    'PERM_CHECK',[
                                        ses(),
                                        obj.data.list.au[0].id(),
                                        obj.data.list.au[0].ws_ou(),
                                        [ 'ALLOW_ALT_TCN' ]
                                    ]
                                );
                                if (typeof robj.ilsevent != 'undefined') {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.permission_error'),E);
                                }
                                if (robj.length != 0) btn1 = null;
                            }
                            var btn2 = $("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.btn2_cancel');
                            var p = obj.error.yns_alert(msg,title,btn1,btn2,null, $("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.confirm_action'));
                            obj.error.sdump('D_ERROR','option ' + p + 'chosen');
                            switch(p) {
                                case 0:
                                    var r2 = obj.network.request(
                                        api.MARC_XML_RECORD_REPLACE.app,
                                        api.MARC_XML_RECORD_REPLACE.method + '.override',
                                        [ ses(), obj.data.marked_record, new_marcxml, biblio_source ]
                                    );
                                    if (typeof r2.ilsevent != 'undefined') {
                                        throw(r2);
                                    } else {
                                        alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.successful_overlay_with_new_TCN'));
                                        return {
                                            'id' : r2.id(),
                                            'on_complete' : function() {
                                                try {
                                                    obj.replace_tab_with_opac(r2.id());
                                                } catch(E) {
                                                    alert(E);
                                                }
                                            }
                                        };
                                    }
                                break;
                                case 1:
                                default:
                                    alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.cancelled_overlay'));
                                break;
                            }
                        break;
                        default:
                            throw(r);
                        break;
                    }
                } else {
                    alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.success_overlay'));
                    try {
                        obj.data.marked_record_mvr = null;
                        obj.data.marked_record = null;
                        obj.data.stash('marked_record');
                        obj.data.stash('marked_record_mvr');
                        obj.controller.view.marc_import_overlay.disabled = true;
                        if ($("overlay_tcn_indicator")) {
                            $("overlay_tcn_indicator").setAttribute('value',$("catStrings").getString('staff.cat.z3950.marked_record_for_overlay_indicator.no_record.label'));
                        }
                        xulG.set_statusbar(1, $("catStrings").getString('staff.cat.z3950.marked_record_for_overlay_indicator.no_record.label') );
                    } catch(E) {
                        dump('Error in z3950.js, post-overlay: ' + E + '\n');
                    }
                    return {
                        'id' : r.id(),
                        'on_complete' : function() {
                            try {
                                obj.replace_tab_with_opac(r.id());
                            } catch(E) {
                                alert(E);
                            }
                        }
                    };
                }
            } catch(E) {
                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.overlay_error'),E);
            }
        }

        if ( $('marc_editor').checked ) {
            xulG.new_tab(
                xulG.url_prefix('XUL_MARC_EDIT'), 
                { 'tab_name' : $("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.tab_name') },
                { 
                    'record' : { 'marc' : my_marcxml },
                    'fast_add_item' : function(doc_id,cn_label,cp_barcode) {
                        try {
                            JSAN.use('cat.util'); cat.util.fast_item_add(doc_id,cn_label,cp_barcode);
                        } catch(E) {
                            alert(E);
                        }
                    },
                    'save' : {
                        'label' : $("catStrings").getString('staff.cat.z3950.spawn_marc_editor_for_overlay.overlay_record_label'),
                        'func' : overlay_marc
                    }
                } 
            );
        } else {
            overlay_marc(my_marcxml);
        }
    },


    'load_creds' : function() {
        var obj = this;
        try {
            obj.creds = { 'version' : g.save_version, 'services' : {}, 'hosts' : {} };
            /*
                {
                    'version' : xx,
                    'default_service' : xx,
                    'services' : {

                        'xx' : {
                            'username' : xx,
                            'password' : xx,
                            'default_attr' : xx,
                        },

                        'xx' : {
                            'username' : xx,
                            'password' : xx,
                            'default_attr' : xx,
                        },
                    },
                    // new in version 2
                    'hosts' : {
                        'xxxx' : {
                            'default_services' : [ xx, ... ],
                            'services' : {

                                'xx' : {
                                    'username' : xx,
                                    'password' : xx,
                                    'default_attr' : xx,
                                },

                                'xx' : {
                                    'username' : xx,
                                    'password' : xx,
                                    'default_attr' : xx,
                                },
                            },
                        }
                    }
                }
            */
            JSAN.use('util.file'); var file = new util.file('z3950_store');
            if (file._file.exists()) {
                var creds = file.get_object(); file.close();
                if (typeof creds.version != 'undefined') {
                    if (creds.version >= obj.creds_version) {  /* so apparently, this guy is assuming that future versions will be backwards compatible */
                        if (typeof creds.hosts == 'undefined') creds.hosts = {};
                        obj.creds = creds;
                    }
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.load_creds.z3950_cred_error'),E);
        }
    },

    'save_creds' : function () {
        try {
            var obj = this;
            if (typeof obj.creds.hosts == 'undefined') obj.creds.hosts = {};
            if (typeof obj.creds.hosts[ obj.data.server_unadorned ] == 'undefined') obj.creds.hosts[ obj.data.server_unadorned ] = { 'services' : {} };
            obj.creds.hosts[ obj.data.server_unadorned ].default_services = obj.active_services;
            for (var i = 0; i < obj.creds.hosts[ obj.data.server_unadorned ].default_services.length; i++) {
                var service = obj.creds.hosts[ obj.data.server_unadorned ].default_services[i];
                if (typeof obj.creds.hosts[ obj.data.server_unadorned ].services[ service ] == 'undefined') {
                    obj.creds.hosts[ obj.data.server_unadorned ].services[ service ] = {}
                }
                obj.creds.hosts[ obj.data.server_unadorned ].services[service].username = document.getElementById(service + '_username').value;
                obj.creds.hosts[ obj.data.server_unadorned ].services[service].password = document.getElementById(service + '_password').value;
                if (obj.default_attr) {
                    obj.creds.hosts[ obj.data.server_unadorned ].services[service].default_attr = obj.default_attr;
                }
            }
            obj.creds.version = obj.creds_version;
            JSAN.use('util.file'); var file = new util.file('z3950_store');
            file.set_object(obj.creds);
            file.close();
        } catch(E) {
            obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.z3950.save_creds.z3950_cred_error'),E);
        }
    },

    'handle_enter' : function(ev) {
        var obj = this;
        if (ev.target.tagName != 'textbox') return;
        if (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* enter on a mac */) setTimeout( function() { obj.initial_search(); }, 0);
    },
}

dump('exiting cat.z3950.js\n');
