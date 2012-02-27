<!--
vim: noet:ts=4:sw=4:
-->
dump('entering admin/offline_manage_xacts.js\n');

if (typeof admin == 'undefined') admin = {};
admin.offline_manage_xacts = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
}

admin.offline_manage_xacts.prototype = {

    'sel_list' : [],
    'seslist' : [],
    'sel_errors' : [],

    'init' : function( params ) {

        var obj = this;

        JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

        obj.init_list(); obj.init_script_list(); obj.init_error_list();

        obj.retrieve_seslist(); obj.render_seslist();

        var x = document.getElementById('create');
        if (obj.check_perm(['OFFLINE_UPLOAD'])) {
            x.disabled = false;
            x.addEventListener('command',function() { try{obj.create_ses();}catch(E){alert(E);} },false);
        }

        x = obj.$('upload');
        x.addEventListener('command',function() { try{obj.upload();}catch(E){alert(E);} },false);

        x = obj.$('refresh');
        x.addEventListener('command',function() { try{$('deck').selectedIndex=0;obj.retrieve_seslist();obj.render_seslist();}catch(E){alert(E);} },false);

        x = obj.$('execute');
        x.addEventListener('command',function() { try{obj.execute_ses();}catch(E){alert(E);} },false);

        x = obj.$('retrieve_item');
        x.addEventListener('command',function() { try{obj.retrieve_item();}catch(E){alert(E);} },false);

        x = obj.$('retrieve_patron');
        x.addEventListener('command',function() { try{obj.retrieve_patron();}catch(E){alert(E);} },false);

        x = obj.$('retrieve_details');
        x.addEventListener('command',function() { try{obj.retrieve_details();}catch(E){alert(E);} },false);

        obj.$('deck').selectedIndex = 0;
    },

    '$' : function(id) { return document.getElementById(id); },

    'init_list' : function() {
        var obj = this; JSAN.use('util.list'); JSAN.use('util.date'); JSAN.use('patron.util');
        obj.list = new util.list('session_tree');
        obj.list.init( {
            'columns' : [
                {
                    'id' : 'org', 'hidden' : 'true', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.organization'),
                    'render' : function(my) { return obj.data.hash.aou[ my.org ].shortname(); }
                },
                { 
                    'id' : 'description', 'flex' : '2',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.description'),
                    'render' : function(my) { return my.description; }
                },
                {
                    'id' : 'create_time', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.date_created'),
                    'render' : function(my) { if (my.create_time) { var x = new Date(); x.setTime(my.create_time+"000"); return util.date.formatted_date(x,"%F %H:%M"); } else { return ""; }; }
                },
                {
                    'id' : 'creator', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.created_by'),
                    'render' : function(my) { var staff_obj = patron.util.retrieve_name_via_id( ses(), my.creator ); return staff_obj[0] + " @ " + obj.data.hash.aou[ staff_obj[3] ].shortname(); }
                },
                { 
                    'id' : 'count', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.upload_count'), 
                    'render' : function(my) { return my.scripts.length; }
                },
                { 
                    'id' : 'num_complete', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.transactions_processed'), 
                    'render' : function(my) { return my.num_complete; }
                },
                { 
                    'id' : 'in_process', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.processing'),
                    'render' : function(my) {
                        if (my.end_time) {
                            return $('adminStrings').getString('staff.admin.offline_manage_xacts.completed')
                        } else {
                            return get_bool(my.in_process) ? $('adminStrings').getString('staff.admin.offline_manage_xacts.yes') : $('adminStrings').getString('staff.admin.offline_manage_xacts.no')
                        };
                    }
                },
                {
                    'id' : 'start_time', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.date_started'),
                    'render' : function(my) { if (my.start_time) {var x = new Date(); x.setTime(my.start_time+"000"); return util.date.formatted_date(x,"%F %H:%M");} else { return ""; }; }
                },
                {
                    'id' : 'end_time', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.date_completed'),
                    'render' : function(my) { if (my.end_time) {var x = new Date(); x.setTime(my.end_time+"000"); return util.date.formatted_date(x,"%F %H:%M");} else { return ""; }; }
                },
                { 
                    'id' : 'key', 'hidden' : 'true', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_list.session'),
                    'render' : function(my) { return my.key; }
                },
            ],
            'on_select' : function(ev) {
                try {
                    $('deck').selectedIndex = 0;
                    $('execute').disabled = true;
                    $('upload').disabled = true;
                    setTimeout(
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var sel = obj.list.retrieve_selection();
                                obj.sel_list = util.functional.map_list(
                                    sel,
                                    function(o) { return o.getAttribute('retrieve_id'); }
                                );
                                if (obj.sel_list.length == 0) return;
                                {    
                                    var upload = true; var process = true;

                                    if (obj.sel_list.length > 1) upload = false;

                                    if (obj.seslist[ obj.sel_list[0] ].end_time) {
                                        upload = false; process = false;
                                    }
                                    if (obj.seslist[ obj.sel_list[0] ].in_process == 1) {
                                        upload = false; process = false;
                                    }

                                    /* should we really have this next restriction? */
                                    for (var i = 0; i < obj.seslist[ obj.sel_list[0] ].scripts.length; i++) {
                                        if (obj.seslist[ obj.sel_list[0] ].scripts[i].workstation ==
                                            obj.data.ws_name ) upload = false;
                                    }

                                    if (upload) {
                                        if (obj.check_perm(['OFFLINE_UPLOAD'])) {
                                            document.getElementById('upload').disabled = false;
                                        }
                                    } else {
                                        document.getElementById('upload').disabled = true;
                                    }
                                    if (process) {
                                        if (obj.check_perm(['OFFLINE_EXECUTE'])) {
                                            document.getElementById('execute').disabled = false;    
                                        }
                                    } else {
                                        document.getElementById('execute').disabled = true;    
                                    }
                                }
                                var complete = false;
                                for (var i = 0; i < obj.sel_list.length; i++) { 
                                    if (obj.seslist[ obj.sel_list[i] ].end_time) { complete = true; }
                                }
                                if (complete) {
                                    obj.render_errorlist();
                                } else {
                                    if (obj.seslist[ obj.sel_list[0] ].in_process == 1) {
                                        obj.render_status();
                                    } else {
                                        obj.render_scriptlist();
                                    }
                                }
                            } catch(E) {
                                alert('on_select: ' + E);
                            }
                        }, 0
                    );
                } catch(E) {
                    alert('on_select:\nobj.seslist.length = ' + obj.seslist.length + '  obj.sel_list.length = ' + obj.sel_list.length + '\nerror: ' + E);
                }
            }
        } );


    },

    'init_script_list' : function() {
        var obj = this; JSAN.use('util.list'); JSAN.use('util.date'); JSAN.use('patron.util');
        obj.script_list = new util.list('script_tree');
        obj.script_list.init( {
            'columns' : [
                {
                    'id' : 'create_time', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_script_list.date_uploaded'),
                    'render' : function(my) { if (my.create_time) { var x = new Date(); x.setTime(my.create_time+"000"); return util.date.formatted_date(x,"%F %H:%M"); } else { return ""; }; }
                },
                {
                    'id' : 'requestor', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_script_list.uploaded_by'),
                    'render' : function(my) { var staff_obj = patron.util.retrieve_name_via_id( ses(), my.requestor ); return staff_obj[0] + " @ " + obj.data.hash.aou[ staff_obj[3] ].shortname(); }
                },
                { 
                    'id' : 'time_delta', 'hidden' : 'true', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_script_list.time_delta'),
                    'render' : function(my) { return my.time_delta; }
                },
                { 
                    'id' : 'workstation', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_script_list.workstation'),
                    'render' : function(my) { return my.workstation; }
                },
            ]
        } );


    },

    'init_error_list' : function() {
        var obj = this; JSAN.use('util.list');  JSAN.use('util.date'); JSAN.use('patron.util'); JSAN.use('util.functional');
        obj.error_list = new util.list('error_tree');
        obj.error_list.init( {
            'columns' : [
                {
                    'id' : 'workstation', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.workstation'),
                    'render' : function(my) { return my.command._workstation ? my.command._workstation : my.command._worksation; }
                },
                {
                    'id' : 'timestamp', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.timestamp'),
                    'render' : function(my) { if (my.command.timestamp) { var x = new Date(); x.setTime(my.command.timestamp+"000"); return util.date.formatted_date(x,"%F %H:%M"); } else { return my.command._realtime; }; }
                },
                {
                    'id' : 'type', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.type'),
                    'render' : function(my) { return my.command.type; }
                },
                { 
                    'id' : 'ilsevent', 'hidden' : 'true', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.event_code'),
                    'render' : function(my) { return my.event.ilsevent; }
                },
                { 
                    'id' : 'textcode', 'flex' : '1', 
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.event_name'),
                    'render' : function(my) { return typeof my.event.textcode != 'undefined' ? my.event.textcode : util.functional.map_list( my.event, function(o) { return o.textcode; }).join('/'); }
                },
                {
                    'id' : 'desc', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.event_description'),
                    'render' : function(my) { return my.event.desc; }
                },
                {
                    'id' : 'i_barcode', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.item_barcode'),
                    'render' : function(my) { return my.command.barcode ? my.command.barcode : ""; }
                },
                {
                    'id' : 'p_barcode', 'flex' : '1',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.patron_barcode'),
                    'render' : function(my) { if (my.command.patron_barcode) { return my.command.patron_barcode; } else { if (my.command.user.card.barcode) { return my.command.user.card.barcode; } else { return ""; } }; }
                },
                {
                    'id' : 'duedate', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.due_date'),
                    'render' : function(my) { return my.command.due_date || ""; }
                },
                {
                    'id' : 'backdate', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.backdate'),
                    'render' : function(my) { return my.command.backdate || ""; }
                },
                {
                    'id' : 'count', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.count'),
                    'render' : function(my) { return my.command.count || ""; }
                },
                {
                    'id' : 'noncat', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.noncat'),
                    'render' : function(my) { return get_bool(my.command.noncat) ? $('adminStrings').getString('staff.admin.offline_manage_xacts.yes') : $('adminStrings').getString('staff.admin.offline_manage_xacts.no'); }
                },
                {
                    'id' : 'noncat_type', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.noncat_type'),
                    'render' : function(my) { return data.hash.cnct[ my.command.noncat_type ] ? obj.data.hash.cnct[ my.command.noncat_type ].name() : ""; }
                },
                {
                    'id' : 'noncat_count', 'flex' : '1', 'hidden' : 'true',
                    'label' : $('adminStrings').getString('staff.admin.offline_manage_xacts.init_error_list.noncat_count'),
                    'render' : function(my) { return my.command.noncat_count || ""; }
                },
            ],
            'on_select' : function(ev) {
                try {
                    var sel = obj.error_list.retrieve_selection();
                    obj.sel_errors = util.functional.map_list(
                        sel,
                        function(o) { return o.getAttribute('retrieve_id'); }
                    );
                    if (obj.sel_errors.length > 0) {
                        obj.$('retrieve_item').disabled = false;
                        obj.$('retrieve_patron').disabled = false;
                        obj.$('retrieve_details').disabled = false;
                    } else {
                        obj.$('retrieve_item').disabled = true;
                        obj.$('retrieve_patron').disabled = true;
                        obj.$('retrieve_details').disabled = true;
                    }
                } catch(E) {
                    alert(E);
                }
            }
        } );

        var export_button = document.getElementById('export_btn');
        if (export_button) export_button.addEventListener(
            'command',
            function(ev) {
                try {
                    obj.error_list.dump_csv_to_clipboard();
                } catch(E) {
                    obj.error.standard_unexpected_error_alert('export',E); 
                }
            },
            false
        );
        
        var print_export_button = document.getElementById('print_export_btn');
        if (print_export_button) print_export_button.addEventListener(
            'command',
            function(ev) {
                try {
                    obj.error_list.on_all_fleshed =
                        function() {
                            try {
                                dump( obj.error_list.dump_csv() + '\n' );
                                //copy_to_clipboard(obj.error_list.dump_csv());
                                JSAN.use('util.print'); var p = new util.print();
                                p.simple( obj.error_list.dump_csv(), { 'content_type' : 'text/plain' } );
                                setTimeout(function(){ obj.error_list.on_all_fleshed = null; },0);
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('export',E); 
                            }
                        }
                    obj.error_list.full_retrieve();
                } catch(E) {
                    obj.error.standard_unexpected_error_alert('print export',E); 
                }
            },
            false
        );

    },

    'check_perm' : function(perms) {
        var obj = this;
        try {
            var robj = obj.network.simple_request('PERM_CHECK',[ses(),obj.data.list.au[0].id(),obj.data.list.au[0].ws_ou(),perms]);
            if (typeof robj.ilsevent != 'undefined') {
                obj.error.standard_unexpected_error_alert('check permission',E);
                return false;
            }
            return robj.length == 0 ? true : false;
        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.check_perm'),E);
        }
    },

    'execute_ses' : function() {
        var obj = this;

        try {

        clear_the_cache();
        obj.data.stash_retrieve();

        for (var i = 0; i < obj.sel_list.length; i++) {

            var url  = xulG.url_prefix('XUL_OFFLINE_MANAGE_XACTS_CGI?ses=')
                + window.escape(ses())
                + "&action=execute" 
                + "&seskey=" + window.escape(obj.seslist[obj.sel_list[i]].key)
                + "&ws=" + window.escape(obj.data.ws_name);
            var x = new XMLHttpRequest();
            x.open("GET",url,false);
            x.send(null);

            dump(url + ' = ' + x.responseText + '\n' );
            if (!x.responseText) {
                throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.bad_cgi_response'));
            }
            var robj = JSON2js(x.responseText);

            if (robj.ilsevent != 0) { alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.execute_error') + ' ' + x.responseText); }

            obj.retrieve_seslist(); obj.render_seslist();
        }

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.session_execute_error'),E);
        }
    },

    'ses_errors' : function() {
        var obj = this;

        try {

        clear_the_cache();
        obj.data.stash_retrieve();

        var url  = xulG.url_prefix('XUL_OFFLINE_MANAGE_XACTS_CGI?ses=')
            + window.escape(ses())
            + "&action=status" 
            + "&seskey=" + window.escape(obj.seslist[ obj.sel_list[0] ].key)
            + "&ws=" + window.escape(obj.data.ws_name)
            + '&status_type=exceptions';
        var x = new XMLHttpRequest();
        x.open("GET",url,false);
        x.send(null);

        dump(url + ' = ' + x.responseText + '\n' );
        if (!x.responseText) {
            throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.bad_cgi_response'));
        }
        var robj = JSON2js(x.responseText);

        return { 'errors' : robj, 'description' : obj.seslist[ obj.sel_list[0] ].description };

        } catch(E) {
            throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.session_retrieval') + ' ' + E);
        }

    },

    'rename_file' : function() {
        var obj = this;

        try {

        JSAN.use('util.file'); 
        var pending = new util.file('pending_xacts');
        if ( !pending._file.exists() ) {
            throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.non_existent_file'));
        }
        obj.transition_filename = 'pending_xacts_' + new Date().getTime();
        var count = 0;
        var file = new util.file(obj.transition_filename);
        while (file._file.exists()) {
            obj.transition_filename = 'pending_xacts_' + new Date().getTime();
            file = new util.file(obj.transition_filename);
            if (count++>100) {
                throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.unique_file'));
            }
        }
        pending._file.moveTo(null,obj.transition_filename);

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.renaming_file'),E);
        }
    },

    'revert_file' : function() {
        var obj = this;

        try {

        JSAN.use('util.file');
        var pending = new util.file('pending_xacts');
        if (pending._file.exists()) { 
            obj.error.yns_alert(
                    $('adminStrings').getFormattedString('staff.admin.offline_manage_xacts.error.transaction_conflicts', [obj.transition_filename]),
                    $('adminStrings').getString('staff.admin.offline_manage_xacts.error.transaction_conflicts.title'),
                    $('adminStrings').getString('staff.admin.offline_manage_xacts.error.transaction_conflicts.ok'),
                    null,
                    null,
                    $('adminStrings').getString('staff.admin.offline_manage_xacts.error.transaction_conflicts.confirm')
            );
            return;
        }
        var file = new util.file(obj.transition_filename);
        file._file.moveTo(null,'pending_xacts');

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.reverting_file'),E);
        }
    },

    'archive_file' : function() {
        var obj = this;

        try {

        JSAN.use('util.file');
        var file = new util.file(obj.transition_filename);
        if (file._file.exists()) file._file.moveTo(null,obj.transition_filename + '.complete');

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.archiving_file'),E);
        }
    },

    'upload' : function() {
        var obj = this;

        try {

        if (obj.sel_list.length == 0) { 
            alert($('adminStrings').getString('staff.admin.offline_manage_xacts.session_upload'));
            return;
        }
        if (obj.sel_list.length > 1) {
            alert($('adminStrings').getString('staff.admin.offline_manage_xacts.single_session_upload'));
            return;
        }

        JSAN.use('util.file');

        var file = new util.file('pending_xacts');
        if (!file._file.exists()) {
            alert($('adminStrings').getString('staff.admin.offline_manage_xacts.no_transactions'));
            return;
        }

        obj.rename_file();

        obj.data.stash_retrieve();
        var seskey = obj.seslist[ obj.sel_list[0] ].key;
        JSAN.use('util.widgets');
        var xx = document.getElementById('iframe_placeholder'); util.widgets.remove_children(xx);
        var x = document.createElement('iframe'); xx.appendChild(x); x.flex = 1;
        x.setAttribute(
            'src',
            window.xulG.url_prefix('XUL_REMOTE_BROWSER')
            /*
            + '?url=' + window.escape(
                urls.XUL_OFFLINE_UPLOAD_XACTS
                + '?ses=' + window.escape(ses())
                + '&seskey=' + window.escape(seskey)
                + '&ws=' + window.escape(obj.data.ws_name)
                + '&delta=' + window.escape('0')
                + '&filename=' + window.escape( obj.transition_filename )
            )
            */
        );
        var newG = { 
            'url' : urls.XUL_OFFLINE_UPLOAD_XACTS,
            'url_prefix' : window.xulG.url_prefix, 
            'passthru_content_params' : {
                'ses' : ses(),
                'seskey' : seskey,
                'ws' : obj.data.ws_name,
                'delta' : 0,
                'filename' : obj.transition_filename,
                'url_prefix' : window.xulG.url_prefix,
                'handle_event' : function(robj){
                    try {
                        dump('robj = ' + js2JSON(robj) + '\n');
                        if ( robj.ilsevent != 0 ) {
                            obj.revert_file();
                            alert($('adminStrings').getFormattedString('staff.admin.offline_manage_xacts.error.uploading_file') + '\n' + js2JSON(robj));
                        } else {
                            obj.archive_file();
                        }
                        obj.retrieve_seslist(); obj.render_seslist();
                        setTimeout(
                            function() {
                                JSAN.use('util.widgets');
                                util.widgets.remove_children('iframe_placeholder');
                            },0
                        );
                    } catch(E) {
                        alert('handle_event error: ' + E);
                    }
                } 
            }
        };
        get_contentWindow(x).xulG = newG;

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.uploading_transactions'),E);
        }
    },

    'ses_status' : function() {
        var obj = this;

        try {

        clear_the_cache();
        obj.data.stash_retrieve();

        var url  = xulG.url_prefix('XUL_OFFLINE_MANAGE_XACTS_CGI?ses=')
            + window.escape(ses())
            + "&action=status" 
            + "&seskey=" + window.escape(obj.seslist[obj.sel_list[0]].key)
            + "&ws=" + window.escape(obj.data.ws_name)
            + "&status_type=scripts";
        var x = new XMLHttpRequest();
        x.open("GET",url,false);
        x.send(null);

        dump(url + ' = ' + x.responseText + '\n' );
        if (!x.responseText) {
            throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.bad_cgi_response'));
        }
        var robj = JSON2js(x.responseText);

        return robj;

        } catch(E) {

            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.retrieving_session'),E);
            return { 'ilsevent' : -2 };    

        }
    },

    'create_ses' : function() {

        var obj = this;

        try {

        var desc = window.prompt(
                $('adminStrings').getString('staff.admin.offline_manage_xacts.create_session.prompt'),
                '',
                $('adminStrings').getString('staff.admin.offline_manage_xacts.create_session')
        );
        if (desc=='' || desc==null) { return; }

        clear_the_cache();
        obj.data.stash_retrieve();

        var url  = xulG.url_prefix('XUL_OFFLINE_MANAGE_XACTS_CGI?ses=')
            + window.escape(ses())
            + "&action=create" 
            + "&desc=" + window.escape(desc)
            + "&ws=" + window.escape(obj.data.ws_name);
        var x = new XMLHttpRequest();
        x.open("GET",url,false);
        x.send(null);

        dump(url + ' = ' + x.responseText + '\n' );
        if (!x.responseText) {
            throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.bad_cgi_response'));
        }
        var robj = JSON2js(x.responseText);
        if (robj.ilsevent == 0) {
            obj.retrieve_seslist(); obj.render_seslist();
        } else {
            alert($('adminStrings').getFormattedString('staff.admin.offline_manage_xacts.error.create_session.alert', [x.responseText]));
        }

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.create_session'), E);
        }

    },

    'retrieve_seslist' : function() {

        var obj = this;

        try {

            clear_the_cache();
            obj.data.stash_retrieve();

            var url = xulG.url_prefix('XUL_OFFLINE_MANAGE_XACTS_CGI?ses=') 
                + window.escape(ses())
                + "&action=status"
                + "&org=" + window.escape(obj.data.list.au[0].ws_ou())
                + "&status_type=sessions";
            var x = new XMLHttpRequest();
            x.open("GET",url,false);
            x.send(null);

            dump(url + ' = ' + typeof(x.responseText) + '\n' );

            if (!x.responseText) {
                throw($('adminStrings').getString('staff.admin.offline_manage_xacts.error.bad_cgi_response'));
            }

            var robj = JSON2js( x.responseText );
            if (typeof robj.ilsevent != 'undefined') throw(robj);

            if (!robj) throw(robj);

            obj.seslist = robj.sort(
                function(a,b) {
                    return b.create_time - a.create_time;
                }
            );

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.retrieving_sessions'),E);
        }
    },

    'render_seslist' : function() {

        var obj = this;

        try {

        var old_idx = obj.list.node.currentIndex;
        if (old_idx < 0) old_idx = 0;

        obj.list.clear();

        var funcs = [];
        for (var i = 0; i < obj.seslist.length; i++) {
            funcs.push( 
                function(idx,row){ 
                    return function(){
                        obj.list.append( { 'retrieve_id' : idx, 'row' : row, 'no_auto_select' : true, 'to_bottom' : true } );
                        //if (idx == old_idx) obj.list.node.view.selection.select(idx);
                    };
                }(i,{ 'my' : obj.seslist[i] }) 
            );
        }

        JSAN.use('util.exec'); var exec = new util.exec();
        exec.chain( funcs );

        document.getElementById('execute').disabled = true;
        document.getElementById('upload').disabled = true;

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.rendering_session'),E);
        }
    },

    'render_scriptlist' : function() {

        dump('render_scriptlist\n');

        var obj = this;

        try { 

        document.getElementById('deck').selectedIndex = 1;

        obj.script_list.clear();

        var status = obj.ses_status();
        $('status_caption').setAttribute('label', $('adminStrings').getFormattedString('staff.admin.offline_manage_xacts.upload_status', [status.description]));

        var scripts = status.scripts;

        var funcs = [];
        for (var i = 0; i < scripts.length; i++) {
            funcs.push( 
                function(row){ 
                    return function(){
                        obj.script_list.append( { 'row' : row, 'no_auto_select' : true  } );
                    };
                }({ 'my' : scripts[i] }) 
            );
        }
        JSAN.use('util.exec'); var exec = new util.exec();
        exec.chain( funcs );

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.rendering_script'),E);
        }
    },
    
    'render_errorlist' : function() {

        dump('render_errorlist\n');

        var obj = this;

        try {

        document.getElementById('deck').selectedIndex = 2;

        obj.error_list.clear();

        var error_meta = obj.ses_errors();
        $('errors_caption').setAttribute('label',$('adminStrings').getFormattedString('staff.admin.offline_manage_xacts.error.rendering_errors', [error_meta.description]));

        obj.errors = error_meta.errors;

        var funcs = [];
        for (var i = 0; i < obj.errors.length; i++) {
            funcs.push( 
                function(idx,row){ 
                    return function(){
                        obj.error_list.append( { 'retrieve_id' : idx, 'row' : row, 'no_auto_select' : true  } );
                    };
                }(i,{ 'my' : obj.errors[i] }) 
            );
        }
        JSAN.use('util.exec'); var exec = new util.exec();
        exec.chain( funcs );

        } catch(E) {
            obj.error.standard_unexpected_error_alert($('adminStrings').getString('staff.admin.offline_manage_xacts.error.rendering_error_list'),E);
        }
    },

    'render_status' : function() {
    
        dump('render_status\n');

        document.getElementById('deck').selectedIndex = 3;

    },

    'retrieve_item' : function() {
        var obj = this;
        try {
            var barcodes = [];
            for (var i = 0; i < obj.sel_errors.length; i++) {
                var error = obj.errors[ obj.sel_errors[i] ];
                if ( ! error.command.barcode ) continue; 
                if ( [ '', ' ', '???' ].indexOf( error.command.barcode ) != -1 ) continue;
                barcodes.push( error.command.barcode );
            }
            if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
                try {
                    var url = urls.XUL_COPY_STATUS;
                        //+ '?barcodes=' + window.escape( js2JSON(barcodes) );
                    window.xulG.new_tab(
                        url, {}, { 'barcodes' : barcodes }
                    );
                } catch(E) {
                    alert(E);
                }
            }
        } catch(E) {
            alert(E);
        }
    },

    'retrieve_patron' : function() {
        var obj = this;
        var patrons = {};
        try {
            for (var i = 0; i < obj.sel_errors.length; i++) {
                var error = obj.errors[ obj.sel_errors[i] ];
                if ( ! error.command.patron_barcode ) continue; 
                if ( [ '', ' ', '???' ].indexOf( error.command.patron_barcode ) != -1 ) continue;
                patrons[ error.command.patron_barcode ] = true;
            }
            for (var barcode in patrons) {
                if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
                    try {
                        window.xulG.new_patron_tab(
                            {}, { 'barcode' : barcode }
                        );
                    } catch(E) {
                        alert(E);
                    }
                }

            }
        } catch(E) {
            alert(E);
        }
    },

    'retrieve_details' : function() {
        var obj = this;
        JSAN.use('util.window'); var win = new util.window();
        try {
            for (var i = 0; i < obj.sel_errors.length; i++) {
                var error = obj.errors[ obj.sel_errors[i] ];
                win.open(
                    'data:text/plain,' + window.escape(
                        'Details:\n' + obj.error.pretty_print(js2JSON(error))
                    ),
                    'offline_error_details',
                    'height=780,width=580,scrollbars=yes,chrome,resizable,modal'
                );
            }
        } catch(E) {
            alert(E);
        }

    }
}

dump('exiting admin/offline_manage_xacts.js\n');
