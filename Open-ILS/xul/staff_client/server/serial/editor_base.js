dump('entering serial/editor_base.js\n');
// vim:et:sw=4:ts=4:

if (typeof serial == 'undefined') serial = {};

serial.editor_base = {

    'editor_base_init' : function (params) {
        var obj = this;
        try {
            /******************************************************************************************************/
            /* setup JSAN and some initial libraries */

            if (typeof JSAN == 'undefined') {
                throw( $('commonStrings').getString('common.jsan.missing') );
            }
            JSAN.errorLevel = "die"; // none, warn, or die
            JSAN.addRepository('/xul/server/');
            JSAN.use('util.error'); obj.error = new util.error();
            obj.error.sdump('D_TRACE','my_init() for serial/editor_base.js');

            JSAN.use('util.functional');
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            JSAN.use('util.network'); obj.network = new util.network();


            /******************************************************************************************************/
            /* base vars */

            obj.docid = xul_param('docid',{'modal_xulG':true});
            
            if (typeof params.handle_update == 'undefined') {
                obj.handle_update = xul_param('handle_update',{'modal_xulG':true});
            } else {
                obj.handle_update = params.handle_update;
            }

            obj.trigger_refresh = params.trigger_refresh;
            obj.refresh_command = params.refresh_command;
            var fm_type = obj.fm_type;
            var fm_type_plural = obj.fm_type_plural;
            var retrieve_function = params.retrieve_function;
            var retrieve_params = params.retrieve_params;
            if (!retrieve_params) {
                retrieve_params = [];
            }
            if (params.xul_id_prefix) {
                obj.xul_id_prefix = params.xul_id_prefix;
            } else {
                obj.xul_id_prefix = fm_type;
            }

            /******************************************************************************************************/
            /* Get the fm_type ids from various sources and flesh them */

            var fm_type_ids = params[fm_type + '_ids'];
            if (!fm_type_ids) fm_type_ids = xul_param(fm_type + '_ids',{'concat':true,'JSON2js_if_cgi':true,'JSON2js_if_xulG':true,'JSON2js_if_xpcom':true,'stash_name':'temp_' + fm_type + '_ids','clear_xpcom':true,'modal_xulG':true});
            if (!fm_type_ids) fm_type_ids = [];

            obj[fm_type_plural] = [];
            retrieve_params.push(fm_type_ids);
            if (fm_type_ids.length > 0) obj[fm_type_plural] = obj.network.simple_request(
                retrieve_function,
                retrieve_params
            );


            /******************************************************************************************************/
            /* And other fleshed copies if any */

            if (!obj[fm_type_plural]) obj[fm_type_plural] = [];
            var fms = params[fm_type_plural];
            if (!fms) fms = xul_param(fm_type_plural,{'concat':true,'JSON2js_if_cgi':true,'JSON2js_if_xpcom':true,'stash_name':'temp_' + fm_type_plural,'clear_xpcom':true,'modal_xulG':true})
            if (fms) obj[fm_type_plural] = obj[fm_type_plural].concat(fms);


            // If we have just one, wrap in array
            if (!obj[fm_type_plural].length) {
                obj[fm_type_plural] = [obj[fm_type_plural]];
            }


            /******************************************************************************************************/

            //obj.init_panes0();
            obj.init_panes();

            /******************************************************************************************************/
            /* Is the interface an editor or a viewer, single or multi copy, existing copies or new copies? */

            var do_edit;
            if (typeof params.do_edit == 'undefined') {
                do_edit = xul_param('do_edit',{'modal_xulG':true});
            } else {
                do_edit = params.do_edit;
            }

            if (do_edit) { 

                // Editor desired, but let's check permissions
                obj.do_edit = false;

                try {
                    /* FIXME: add permission check
                    var check = obj.network.simple_request(
                        'PERM_MULTI_ORG_CHECK',
                        [ 
                            ses(), 
                            obj.data.list.au[0].id(), 
                            util.functional.map_list(
                                obj[fm_type_plural],
                                function (o) {
                                    var lib;
                                    var cn_id = o.call_number();
                                    if (cn_id == -1) {
                                        lib = o.circ_lib(); // base perms on circ_lib instead of owning_lib if pre-cat
                                    } else {
                                        if (! obj.map_acn[ cn_id ]) {
                                            var req = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ cn_id ]);
                                            if (typeof req.ilsevent == 'undefined') {
                                                obj.map_acn[ cn_id ] = req;
                                                lib = obj.map_acn[ cn_id ].owning_lib();
                                            } else {
                                                lib = o.circ_lib();
                                            }
                                        } else {
                                            lib = obj.map_acn[ cn_id ].owning_lib();
                                        }
                                    }
                                    return typeof lib == 'object' ? lib.id() : lib;
                                }
                            ),
                            obj[fm_type_plural].length == 1 ? [ 'UPDATE_COPY' ] : [ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
                        ]
                    ); */
                    var check = [];
                    obj.do_edit = check.length == 0;
                } catch(E) {
                    obj.error.standard_unexpected_error_alert('batch permission check',E);
                }

                if (obj.do_edit) {
                    $(obj.xul_id_prefix + '_save').setAttribute('hidden','false'); 
                } else {
                    $('top_nav').setAttribute('hidden','true');
                }
            } else {
                $('top_nav').setAttribute('hidden','true');
            }


            if (obj[fm_type_plural].length > 0 && obj[fm_type_plural][0].isnew()) {
                obj.mode = 'create';
                if (obj.can_have_notes) $(obj.xul_id_prefix + '_notes').setAttribute('hidden','true');
                $(obj.xul_id_prefix + '_save').setAttribute('label', $('serialStrings').getString('staff.serial.' + fm_type + '_editor.create.label'));
                $(obj.xul_id_prefix + '_save').setAttribute('accesskey', $('serialStrings').getString('staff.serial.' + fm_type + '_editor.create.accesskey'));
            } else if (obj.mode == 'create') { // switching from create to modify
                obj.mode = 'modify';
                if (obj.can_have_notes) $(obj.xul_id_prefix + '_notes').setAttribute('hidden','false');
                $(obj.xul_id_prefix + '_save').setAttribute('label', $('serialStrings').getString('staff.serial.' + fm_type + '_editor.modify.label'));
                $(obj.xul_id_prefix + '_save').setAttribute('accesskey', $('serialStrings').getString('staff.serial.' + fm_type + '_editor.modify.accesskey'));
            }
/*else {
                obj.panes_and_field_names.left_pane = 
                    [
                        [
                            $('catStrings').getString('staff.cat.copy_editor.status'),
                            { 
                                render: 'typeof fm.status() == "object" ? fm.status().name() : obj.data.hash.ccs[ fm.status() ].name()', 
                                input: obj.safe_to_edit_copy_status() ? 'c = function(v){ obj.apply("status",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.data.list.ccs, function(obj) { return [ obj.name(), obj.id(), typeof my_constants.magical_statuses[obj.id()] != "undefined" ? true : false ]; } ).sort() ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);' : undefined,
                                //input: 'c = function(v){ obj.apply("status",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( util.functional.filter_list( obj.data.list.ccs, function(obj) { return typeof my_constants.magical_statuses[obj.id()] == "undefined"; } ), function(obj) { return [ obj.name(), obj.id() ]; } ).sort() ); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                            }
                        ]
                    ].concat(obj.panes_and_field_names.left_pane);
            }*/

            if (obj[fm_type_plural].length != 1) {
                if (obj.can_have_notes) $(obj.xul_id_prefix + '_notes').setAttribute('hidden','true');
            }

            // clear change markers
            obj.changed = {};

            /******************************************************************************************************/
            /* Show the Record Details? (only for 'in_modal' mode)*/

            var bdb;
            if (xul_param('in_modal',{'modal_xulG':true}) && obj.docid) {
                bdb = document.getElementById('brief_display_box'); while(bdb.firstChild) bdb.removeChild(bdb.lastChild);
                var brief_display = document.createElement('iframe'); bdb.appendChild(brief_display); 
                brief_display.setAttribute( 'src', urls.XUL_BIB_BRIEF + '?docid=' + obj.docid); // this is a modal window, so can't push in xulG
                brief_display.setAttribute( 'flex','1' );
            }

            /******************************************************************************************************/
            /* Backup copies :) */

            obj['original_' + fm_type_plural] = js2JSON( obj[fm_type_plural] );

        } catch(E) {
            var err_msg = $("commonStrings").getFormattedString('common.exception', ['serial/' + fm_type +'_editor.js - init', E]);
            try { obj.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
            alert(err_msg);
        }
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'editor_base_reset' : function() {
        var obj = this;
        var fm_type_plural = obj.fm_type_plural;

        obj.changed = {};
        obj[fm_type_plural] = JSON2js( obj['original_' + fm_type_plural] );
        obj.summarize( obj[fm_type_plural] );
        obj.render();
    },

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */
    /* Don't forget to use util.money.sanitize if dealing with money values */

    'editor_base_apply' : function(field, value, loop_func) {
        var obj = this;
        var fm_type_plural = obj.fm_type_plural;

        var do_loop_func = (typeof loop_func == 'function');

        obj.error.sdump('D_TRACE','applying field = <' + field + '>  value = <' + value + '>\n');
        if (value == '<HACK:KLUDGE:NULL>') value = null;
        for (var i = 0; i < obj[fm_type_plural].length; i++) {
            var fm = obj[fm_type_plural][i];
            try {
                fm[field]( value ); fm.ischanged('1');
                if (do_loop_func) {
                    loop_func(fm);
                }
            } catch(E) {
                alert(E);
            }
        }
    },


    /******************************************************************************************************/
    /* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

    'editor_base_summarize' : function(my_fms) {
        var obj = this;
        var fm_type = obj.fm_type;
        /******************************************************************************************************/
        /* Setup */

        JSAN.use('util.date'); JSAN.use('util.money');
        obj.summary = {};
        obj.field_names = [];
        for (var i in obj.panes_and_field_names) {
            obj.field_names = obj.field_names.concat( obj.panes_and_field_names[i] );
        }

        /******************************************************************************************************/
        /* Loop through the field names */

        obj.missing_required = [];

        for (var i = 0; i < obj.field_names.length; i++) {

            var field_name = obj.field_names[i][0];
            var render = obj.field_names[i][1].render;
            var attr = obj.field_names[i][1].attr;
            var value_key = obj.field_names[i][1].value_key;
            var dropdown_key = obj.field_names[i][1].dropdown_key;
            var required = obj.field_names[i][1].required;
            obj.summary[ field_name ] = {};

            /******************************************************************************************************/
            /* Loop through the copies */

            for (var j = 0; j < my_fms.length; j++) {

                var fm = my_fms[j];
                var cmd = render || ('fm.' + field_name + '();');
                var value = '???';

                /**********************************************************************************************/
                /* Try to retrieve the value for this field for this copy */

                try { 
                    value = eval( cmd );
                    if (value == null) { // true for both 'null' and undefined
                        value = "";
                    }
                    if (dropdown_key) {
                        obj.editor_values[value_key] = eval(dropdown_key);
                    } else if (value_key) {
                        obj.editor_values[value_key] = value;
                    }
                    if (required && value == "") {
                        obj.missing_required.push(fieldmapper.IDL.fmclasses[fm_type].field_map[field_name].label); //TODO: consider applying a style
                    }

                    if (value == "") {
                        value = $('serialStrings').getString('serial.editor_base.unset');
                    }

                } catch(E) { 
                    obj.error.sdump('D_ERROR','Attempted ' + cmd + '\n' +  E + '\n'); 
                }
                if (typeof value == 'object' && value != null) {
                    alert('FIXME: field_name = <' + field_name + '>  value = <' + js2JSON(value) + '>\n');
                }

                /**********************************************************************************************/
                /* Tally the count */

                if (obj.summary[ field_name ][ value ]) {
                    obj.summary[ field_name ][ value ]++;
                } else {
                    obj.summary[ field_name ][ value ] = 1;
                }
            }
        }

        obj.error.sdump('D_TRACE','summary = ' + js2JSON(obj.summary) + '\n');
    },

    /******************************************************************************************************/
    /* Display the summarized data and inputs for editing */

    'editor_base_render' : function() {
        var obj = this;
        var fm_type = obj.fm_type;

        /******************************************************************************************************/
        /* Library setup and clear any existing interface */

        JSAN.use('util.widgets'); JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('util.functional');

        for (var i in obj.panes_and_field_names) {
            var p = document.getElementById(i);
            if (p) util.widgets.remove_children(p);
        }

        /******************************************************************************************************/
        /* Prepare the panes */

        var groupbox; var caption; var vbox; var grid; var rows;
        
        /******************************************************************************************************/
        /* Loop through the field names */

        for (h in obj.panes_and_field_names) {
            if (!document.getElementById(h)) continue;
            for (var i = 0; i < obj.panes_and_field_names[h].length; i++) {
                try {
                    var f = obj.panes_and_field_names[h][i]; var fn = f[0]; var attr = f[1].attr;
                    groupbox = document.createElement('groupbox'); document.getElementById(h).appendChild(groupbox);
                    if (attr) {
                        for (var a in attr) {
                            groupbox.setAttribute(a,attr[a]);
                        }
                    }
                    if (typeof obj.changed[fn] != 'undefined') {
                        groupbox.setAttribute('class','copy_editor_field_changed');
                    }
                    caption = document.createElement('caption'); groupbox.appendChild(caption);
                    if (f[1].label) {
                        caption.setAttribute('label',f[1].label);
                    } else {
                        caption.setAttribute('label',fieldmapper.IDL.fmclasses[fm_type].field_map[fn].label);
                    }
                    caption.setAttribute('id','caption_'+fn);
                    vbox = document.createElement('vbox'); groupbox.appendChild(vbox);
                    grid = util.widgets.make_grid( [ { 'flex' : 1 }, {}, {} ] ); vbox.appendChild(grid);
                    grid.setAttribute('flex','1');
                    rows = grid.lastChild;
                    var row;
                    
                    /**************************************************************************************/
                    /* Loop through each value for the field */

                    for (var j in obj.summary[fn]) {
                        var value = j; var count = obj.summary[fn][j];
                        row = document.createElement('row'); rows.appendChild(row);
                        var label1 = document.createElement('description'); row.appendChild(label1);
                        label1.setAttribute('id',fn + '_label');
                        //if (obj.special_exception[ fn ]) {
                        //	obj.special_exception[ fn ]( label1, value );
                        //} else {
                            label1.appendChild( document.createTextNode(value) );
                        //}
                        var label2 = document.createElement('description'); row.appendChild(label2);
                        var fm_count;
                        if (count == 1) {
                            fm_count = $('serialStrings').getString('staff.serial.' + fm_type +'_editor.count');
                        } else {
                            fm_count = $('serialStrings').getFormattedString('staff.serial.' + fm_type +'_editor.count.plural', [count]);
                        }
                        label2.appendChild( document.createTextNode(fm_count) );
                    }
                    var hbox = document.createElement('hbox'); 
                    hbox.setAttribute('id',fn);
                    groupbox.appendChild(hbox);
                    var hbox2 = document.createElement('hbox');
                    groupbox.appendChild(hbox2);

                    /**************************************************************************************/
                    /* Render the input widget */

                    if (f[1].input && obj.do_edit) {
                        obj.render_input(hbox,f[1]);
                    }

                } catch(E) {
                    obj.error.sdump('D_ERROR','copy editor: ' + E + '\n');
                }
            }
        }
        
        
        /******************************************************************************************************/
        /* Synchronize stat cat visibility with library filter menu, and default template selection */
        JSAN.use('util.file'); 
        var file = new util.file(fm_type + '_editor_prefs.'+obj.data.server_unadorned);
        obj[fm_type + '_editor_prefs'] = util.widgets.load_attributes(file);
        for (var i in obj[fm_type + '_editor_prefs']) {
            if (i.match(/filter_/) && obj[fm_type + '_editor_prefs'][i].checked == '') {
                try { 
                    obj.toggle_stat_cat_display( document.getElementById(i) ); 
                } catch(E) { alert(E); }
            }
        }
        if (obj.template_menu) obj.template_menu.value = obj.template_menu.getAttribute('value');

    },

    /******************************************************************************************************/
    /* This actually draws the change button and input widget for a given field */
    'editor_base_render_input' : function(node, blob) {
        var obj = this;
        var fm_type_plural = obj.fm_type_plural;

        try {
            // node = hbox ;    groupbox ->  hbox, hbox

            var groupbox = node.parentNode;
            var caption = groupbox.firstChild;
            var vbox = node.previousSibling;
            var hbox = node;
            var hbox2 = node.nextSibling;

            var input_cmd = blob.input;
            var render_cmd = blob.render;
            var attr = blob.attr;

            var block = false; var first = true;

            function on_mouseover(ev) {
                groupbox.setAttribute('style','background: white');
            }

            function on_mouseout(ev) {
                groupbox.setAttribute('style','');
            }

            vbox.addEventListener('mouseover',on_mouseover,false);
            vbox.addEventListener('mouseout',on_mouseout,false);
            groupbox.addEventListener('mouseover',on_mouseover,false);
            groupbox.addEventListener('mouseout',on_mouseout,false);
            groupbox.firstChild.addEventListener('mouseover',on_mouseover,false);
            groupbox.firstChild.addEventListener('mouseout',on_mouseout,false);

            function on_click(ev){
                try {
                    if (block) return; block = true;

                    function post_c(v, unchanged) {
                        try {
                            /* dbw2 not needed?
                            var t = input_cmd.match('apply_stat_cat') ? 'stat_cat' : ( input_cmd.match('apply_owning_lib') ? 'owning_lib' : 'attribute' );
                            var f;
                            switch(t) {
                                case 'attribute' :
                                    f = input_cmd.match(/apply.?\("(.+?)",/)[1];
                                break;
                                case 'stat_cat' :
                                    f = input_cmd.match(/apply_stat_cat\((.+?),/)[1];
                                break;
                                case 'owning_lib' :
                                    f = null;
                                break;
                            }
                            obj.changed[ hbox.id ] = { 'type' : t, 'field' : f, 'value' : v }; */
                            if (!unchanged) {
                                obj.changed[ hbox.id ] = true;
                            }
                            block = false;
                            setTimeout(
                                function() {
                                    obj.summarize( obj[fm_type_plural] );
                                    obj.render();
                                    document.getElementById(caption.id).focus();
                                }, 0
                            );
                        } catch(E) {
                            obj.error.standard_unexpected_error_alert('post_c',E);
                        }
                    }
                    var x; var c; eval( input_cmd );
                    if (x) {
                        util.widgets.remove_children(vbox);
                        util.widgets.remove_children(hbox);
                        util.widgets.remove_children(hbox2);
                        hbox.appendChild(x);
                        var apply = document.createElement('button');
                        apply.setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.apply.label'));
                        apply.setAttribute('accesskey', $('catStrings').getString('staff.cat.copy_editor.apply.accesskey'));
                        hbox2.appendChild(apply);
                        apply.addEventListener('command',function() { c(x.value); },false);
                        var cancel = document.createElement('button');
                        cancel.setAttribute('label', $('catStrings').getString('staff.cat.copy_editor.cancel.label'));
                        cancel.addEventListener('command',function() { setTimeout( function() { obj.summarize( obj[fm_type_plural] ); obj.render(); document.getElementById(caption.id).focus(); }, 0); }, false);
                        hbox2.appendChild(cancel);
                        setTimeout( function() { x.focus(); }, 0 );
                    }
                } catch(E) {
                    obj.error.standard_unexpected_error_alert('render_input',E);
                }
            }
            vbox.addEventListener('click',on_click, false);
            hbox.addEventListener('click',on_click, false);
            caption.addEventListener('click',on_click, false);
            caption.addEventListener('keypress',function(ev) {
                if (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* mac enter */) on_click();
            }, false);
            caption.setAttribute('style','-moz-user-focus: normal');
            caption.setAttribute('onfocus','this.setAttribute("class","outline_me")');
            caption.setAttribute('onblur','this.setAttribute("class","")');

        } catch(E) {
            obj.error.sdump('D_ERROR',E + '\n');
        }
    },

    /******************************************************************************************************/
    /* save or store the updated fms as appropriate */

    'editor_base_save' : function(update_method) {
        var obj = this;
        var fm_type_plural = obj.fm_type_plural;
        var fm_type = obj.fm_type;

        try {
            if (obj.handle_update) {
                try {
                    if (obj.missing_required.length > 0) {
                        alert($('serialStrings').getString('staff.serial.required_fields_alert') + obj.missing_required.join(', '));
                        return; //stop submission
                    }

                    //send fms to the update function
                    var r = obj.network.request(
                        'open-ils.serial',
                        update_method,
                        [ ses(), obj[fm_type_plural] ]
                    );
                    if (typeof r.ilsevent != 'undefined') {
                        obj.error.standard_unexpected_error_alert('serial ' + fm_type + ' update',r);
                    } else {
                        alert($('serialStrings').getString('staff.serial.editor_base.handle_update.success'));
                        obj.changed = {};
                        if (obj.trigger_refresh) {
                            obj.refresh_command();
                        } else {
                            obj.render();
                        }
                    }
                    /* FIXME -- revisit the return value here */
                } catch(E) {
                    alert($('serialStrings').getString('staff.serial.editor_base.handle_update.error') + ' ' + js2JSON(E));
                }
            } else if (xul_param('in_modal',{'modal_xulG':true})) {
                // TODO: this is to perhaps allow this editor to be called
                // in a modal window, but is unfinished functionality
                var xulG = {};
                xulG[fm_type_plural] = obj[fm_type_plural];
                update_modal_xulG(xulG);
            } else {
                obj.data['temp_' + fm_type_plural] = js2JSON( obj[fm_type_plural] );
                obj.data.stash('temp_' + fm_type_plural);
            }

            if (xul_param('in_modal',{'modal_xulG':true})) {
                window.close();
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(fm_type + '_editor save',E);
        }
    },

    /******************************************************************************************************/
    'editor_base_save_attributes' : function() {
        var obj = this;
        var fm_type = obj.fm_type;

        JSAN.use('util.widgets'); JSAN.use('util.file'); var file = new util.file(fm_type + '_editor_prefs.'+obj.data.server_unadorned);
        var what_to_save = {};
        for (var i in obj[fm_type + '_editor_prefs']) {
            what_to_save[i] = [];
            for (var j in obj[fm_type + '_editor_prefs'][i]) what_to_save[i].push(j);
        }
        util.widgets.save_attributes(file, what_to_save );
    }
};

dump('exiting serial/editor_base.js\n');
