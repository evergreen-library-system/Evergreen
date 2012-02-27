var g = {};

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for toolbar.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data();
        g.data.stash_retrieve();

        JSAN.use('util.widgets');
        JSAN.use('util.functional');

        dojo.require('openils.PermaCrud');

        g.pcrud = new openils.PermaCrud({
            authtoken :ses()
        });

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name($('adminStrings').getString('staff.admin.toolbar.tab_name')); } catch(E) { alert(E); }
        }

        init_lists();
        $('list_actions').appendChild( g.list1.render_list_actions() );
        g.list1.set_list_actions();
        populate_list1();
        render_lib_menu();

        // toolbutton manipulators
        $('Add').addEventListener('command',Add,'false');
        $('Remove').addEventListener('command',Remove,'false');
        $('Up').addEventListener('command',Up,'false');
        $('Down').addEventListener('command',Down,'false');

        // toolbar manipulators
        $('Delete').addEventListener('command',Delete,'false');
        $('New').addEventListener('command',New,'false');
        $('Cancel').addEventListener('command',Cancel,'false');
        $('Save').addEventListener('command',Save,'false');

        // restore the toolbar selection
        window.addEventListener(
            'unload',
            function(ev) {
                xulG.render_toolbar_layout();
            },
            false
        );

        // i18n
        $('context_org').setAttribute('label', fieldmapper.IDL.fmclasses.atb.field_map.org.label);
        $('context_usr').setAttribute('label', fieldmapper.IDL.fmclasses.atb.field_map.usr.label);
        $('context_ws').setAttribute('label', fieldmapper.IDL.fmclasses.atb.field_map.ws.label);

    } catch(E) {
        try { g.error.standard_unexpected_error_alert('admin/toolbar.xul',E); } catch(F) { alert(E); }
    }
}

function init_lists() {
    try {
        JSAN.use('util.list'); JSAN.use('patron.util');

        // list1 = main list containing the action.toolbar entries
        // list2 = left list containing available toolbar buttons
        // list3 = right list containing selected toolbar buttons

        init_list1();
        init_list2();
        init_list3();

    } catch(E) {
        alert('Error in toolbar.js, init_lists(): ' + E);
    }
}

function init_list1() {
    try {
        g.list1 = new util.list('atb_tree');

        var list1_columns = g.list1.fm_columns('atb',{
            '*':{'hidden':true, 'flex':0},
            'atb_usr' : {
                'hidden' : false,
                'render' : function(my) {
                    if (! my.atb.usr()) return;
                    return my.atb.usr() == ses('staff_id')
                        ? ses('staff_usrname')
                        : patron.util.retrieve_au_via_id(ses(),my.atb.usr()).usrname();
                }
            },
            'atb_org' : {
                'hidden' : false,
                'fleshed_display_field' : 'shortname'
            },
            'atb_ws' : {
                'hidden' : false,
                'render' : function(my) {
                    if (! my.atb.ws()) return;
                    return my.atb.ws() == ses('ws_id')
                        ? ses('ws_name')
                        : my.atb.ws();
                }
            },
            'atb_label' : { 'hidden' : false, 'flex' : 1 },
            'atb_layout' : { 'hidden' : false, 'flex' : 2 }
        });

        g.list1.init({
            'columns' : list1_columns,
            'on_select' : handle_list1_selection
        });
    } catch(E) {
        alert('Error in toolbar.js, init_list1(): ' + E);
    }
}

function handle_list1_selection(ev) {
    try {
        if (oils_lock > 0) {
            if (g.list1.node.currentIndex != g.list1_last_index) {
                alert( $('adminStrings').getString('staff.admin.toolbar.unsaved_changes') );
                g.list1.node.view.selection.select( g.list1_last_index );
            }
            return util.widgets.stop_event(ev);
        }
        g.list1_last_index = g.list1.node.currentIndex;
        g.selected_atb = get_atb_from_selection();
        if (!g.selected_atb) { return; }
        if (g.selected_atb.org()) {
            $('lib_menu').value = g.selected_atb.org();
            $('context').selectedIndex = 0;
        }
        if (g.selected_atb.ws()) { $('context').selectedIndex = 1; }
        if (g.selected_atb.usr()) { $('context').selectedIndex = 2; }
        g.layout = JSON2js(g.selected_atb.layout());
        populate_list2_list3();
        xulG.render_toolbar_layout(g.layout);
    } catch(E) {
        alert('Error in toolbar.js, handle_list1_selection(): ' + E);
    }
}

function get_atb_from_selection() {
    try {

        var selected = g.list1.retrieve_selection();
        if (selected.length > 0) {
            var treeitem = selected[0]; // seltype="single", so can be only one
            return g.list1_map[ treeitem.getAttribute('unique_row_counter') ].row.my.atb;
        } else {
            return null;
        }

    } catch(E) {
        alert('Error in toolbar.js, get_atb_id_from_selection(): ' + E);
    }
}

function init_list2() {
    try {
        g.list2 = new util.list('left');

        var list2_columns = [
            {
                'id' : 'value',
                'label' : $('adminStrings').getString('staff.admin.toolbar.button_id.header'),
                'render' : function(my) { return my.value; },
                'flex' : 1
            },
            {
                'id' : 'label',
                'label' : $('adminStrings').getString('staff.admin.toolbar.label.header'),
                'render' : function(my) { return my.label; },
                'flex' : 1
            }
        ];

        g.list2.init({
            'columns' : list2_columns
        });

    } catch(E) {
        alert('Error in toolbar.js, init_list2(): ' + E);
    }
}

function get_list2_values_from_selection() {
    try {
        var values = [];
        var selected = g.list2.retrieve_selection();
        for (var i = 0; i < selected.length; i++) {
            var treeitem = selected[i];
            values.push( g.list2_map[ treeitem.getAttribute('unique_row_counter') ].row.my.value );
        }
        return values;
    } catch(E) {
        alert('Error in toolbar.js, get_list2_values_from_selection(): ' + E);
    }
}

function init_list3() {
    try {
        g.list3 = new util.list('right');

        var list3_columns = [
            {
                'id' : 'value',
                'label' : $('adminStrings').getString('staff.admin.toolbar.button_id.header'),
                'render' : function(my) { return my.value; },
                'flex' : 1
            },
            {
                'id' : 'label',
                'label' : $('adminStrings').getString('staff.admin.toolbar.label.header'),
                'render' : function(my) { return my.label; },
                'flex' : 1
            }
        ];

        g.list3.init({
            'columns' : list3_columns
        });

    } catch(E) {
        alert('Error in toolbar.js, init_list2(): ' + E);
    }
}

function get_list3_values_from_selection() {
    try {
        var values = [];
        var selected = g.list3.retrieve_selection();
        for (var i = 0; i < selected.length; i++) {
            var treeitem = selected[i];
            values.push( g.list3_map[ treeitem.getAttribute('unique_row_counter') ].row.my.value );
        }
        return values;
    } catch(E) {
        alert('Error in toolbar.js, get_list3_values_from_selection(): ' + E);
    }
}

function populate_list1() {
    try {
        g.list1.clear();
        g.list1_map = {};
        for (var i = 0; i < g.data.list.atb.length; i++) {
            var rdata = g.list1.append({
                'row' : {
                    'my' : {
                        'atb' : g.data.list.atb[i]
                    }
                }
            });
            g.list1_map[ rdata.unique_row_counter ] = rdata;
        }
    } catch(E) {
        alert('Error in toolbar.js, populate_list1(): ' + E);
    }
}

function populate_list2_list3(list3_idx) {
    try {

        g.list2.clear(); g.list2_map = {};
        g.list3.clear(); g.list3_map = {};

        var seen = {};

        // populate list3, keep track of what to filter from list2
        for (var i = 0; i < g.layout.length; i++) {

            var value = g.layout[i];
            var label;

            if (value.match('toolbarseparator')) {
                label = $('adminStrings').getString('staff.admin.toolbar.toolbar_separator.list_entry');
            } else if (value.match('toolbarspacer')) {
                label = $('adminStrings').getString('staff.admin.toolbar.toolbar_spacer.list_entry');
            } else {
                label = g.data.toolbar_buttons[value];
                seen[value] = true;
            }

            var rdata3 = g.list3.append({
                'row' : {
                    'my' : {
                        'value' : value,
                        'label' : label
                    }
                },
                'to_bottom' : true,
                'no_auto_select' : typeof list3_idx != 'undefined' ? true : undefined
            });
            g.list3_map[ rdata3.unique_row_counter ] = rdata3;
        }

        if (list3_idx) {
            if (list3_idx < 0) { list3_idx = 0; }
            if (list3_idx >= g.list3.node.view.rowCount) { list3_idx = g.list3.node.view.rowCount - 1; }
            g.list3.node.view.selection.select(list3_idx);
        }

        // populate list2
        var list2_data = [];
        for (var value in g.data.toolbar_buttons) {
            if (seen[value]) { continue; }
            list2_data.push( { 'value' : value, 'label' : g.data.toolbar_buttons[value] } );
        }
        list2_data.sort(
            function(a,b) {
                if (a.label < b.label) { return -1; }
                if (a.label > b.label) { return 1; }
                return 0;
            }
        );
        list2_data = [
            { 'value' : 'toolbarseparator', 'label' : $('adminStrings').getString('staff.admin.toolbar.toolbar_separator.list_entry') },
            { 'value' : 'toolbarspacer', 'label' : $('adminStrings').getString('staff.admin.toolbar.toolbar_spacer.list_entry') }
            //,{ 'value' : null, 'label' : '---' } // if we want to visually separate the spacer/separator from the other actions
        ].concat(list2_data);

        for (var i = 0; i < list2_data.length; i++) {
            var rdata2 = g.list2.append({
                'row' : {
                    'my' : list2_data[i]
                },
                'to_bottom' : true
            });
            g.list2_map[ rdata2.unique_row_counter ] = rdata2;
        }

    } catch(E) {
        alert('Error in toolbar.js, populate_list2_list3(): ' + E);
    }
}

function render_lib_menu() {
    try {
        var list = util.functional.map_list(
            g.data.list.aou,
            function(o) {
                var sname = o.shortname(); for (i = sname.length; i < 20; i++) sname += ' ';
                return [
                    o.name() ? sname + ' ' + o.name() : o.shortname(),
                    o.id(),
                    false,
                    ( g.data.hash.aout[ o.ou_type() ].depth() * 2),
                ];
            }
        );
        var ml = util.widgets.make_menulist( list, ses('ws_ou') );
        ml.setAttribute('id','lib_menu');

        var x = $('lib_menu_placeholder');
        if (x) {
            util.widgets.remove_children(x);
            x.appendChild(ml);
        }

    } catch(E) {
        alert('Error in toolbar.js, render_lib_menu(): ' + E);
    }
}

function lock_top_buttons() {
    try {
        oils_lock_page();
        $('New').disabled = true;
        $('Delete').disabled = true;
        $('Save').disabled = false;
        $('Cancel').disabled = false;
    } catch(E) {
        alert('Error in toolbar.js, lock_top_buttons(): ' + E);
    }
}

function unlock_top_buttons() {
    try {
        oils_unlock_page();
        $('New').disabled = false;
        $('Delete').disabled = false;
        $('Save').disabled = true;
        $('Cancel').disabled = true;
    } catch(E) {
        alert('Error in toolbar.js, lock_top_buttons(): ' + E);
    }
}

function Add(ev) {
    try {
        lock_top_buttons();
        var values_to_add = get_list2_values_from_selection();
        var temp = get_list3_values_from_selection();
        var add_after_this_value = temp[ temp.length - 1 ]; // last selected value from list3
        var add_after_this_position = g.layout.indexOf(add_after_this_value) + 1;

        for (var i = values_to_add.length - 1; i >= 0; i--) { // iterate backwards so that we add them forwards
            if (!values_to_add[i]) { continue; }
            if (values_to_add[i].match('toolbarseparator') || values_to_add[i].match('toolbarspacer')) {
                values_to_add[i] = values_to_add[i] + '.' + (new Date()).getTime();
            }
            g.layout.splice(add_after_this_position,0,values_to_add[i]);
        }

        populate_list2_list3();
        xulG.render_toolbar_layout(g.layout);

    } catch(E) {
        alert('Error in toolbar.js, Add(): ' + E);
    }
}

function Remove(ev) {
    try {
        lock_top_buttons();
        var values_to_remove = get_list3_values_from_selection();
        for (var i = 0; i < values_to_remove.length; i++) {
            var idx = g.layout.indexOf(values_to_remove[i]);
            g.layout.splice(idx,1);
        }

        populate_list2_list3();
        xulG.render_toolbar_layout(g.layout);

    } catch(E) {
        alert('Error in toolbar.js, Remove(): ' + E);
    }
}

function Up(ev) {
    try {
        lock_top_buttons();
        var values_to_move = get_list3_values_from_selection();
        var idx;
        for (var i = 0; i < values_to_move.length; i++) {
            idx = g.layout.indexOf(values_to_move[i]);
            if (idx == 0) { continue; }
            g.layout.splice(idx,1);
            g.layout.splice(idx-1,0,values_to_move[i]);
        }

        populate_list2_list3(idx-1);
        xulG.render_toolbar_layout(g.layout);

    } catch(E) {
        alert('Error in toolbar.js, Up(): ' + E);
    }
}

function Down(ev) {
    try {
        lock_top_buttons();
        var values_to_move = get_list3_values_from_selection();
        var idx;
        for (var i = values_to_move.length - 1; i >= 0; i--) {
            idx = g.layout.indexOf(values_to_move[i]);
            g.layout.splice(idx+2,0,values_to_move[i]);
            g.layout.splice(idx,1);
        }

        populate_list2_list3(idx+1);
        xulG.render_toolbar_layout(g.layout);

    } catch(E) {
        alert('Error in toolbar.js, Down(): ' + E);
    }
}

function Delete(ev) {
    try {
        g.selected_atb.isdeleted(1);

        g.pcrud.apply(g.selected_atb);

        delete g.data.hash.atb[ g.selected_atb.id() ];

        var idx;
        for (var i = 0; i < g.data.list.atb.length; i++) {
            if ( g.data.list.atb[i].id() == g.selected_atb.id() ) { idx = i; } 
        }
        g.data.list.atb.splice(idx,1);

        g.data.stash('hash','list');

        unlock_top_buttons();

        populate_list1();


    } catch(E) {
        alert('Error in toolbar.js, Delete(): ' + E);
    }
}

function New(ev) {
    try {
        var name = window.prompt('Enter label for toolbar:');
        if (!name) { return; }

        var new_atb = new atb();
        new_atb.isnew('1');
        new_atb.label(name);
        new_atb.layout('[]');
        new_atb.usr(ses('staff_id'));

        var rdata = g.list1.append({
            'row' : {
                'my' : {
                    'atb' : new_atb
                }
            }
        });
        g.list1_map[ rdata.unique_row_counter ] = rdata;

        setTimeout(
            function() {
                lock_top_buttons();
            }, 1000
        );

    } catch(E) {
        alert('Error in toolbar.js, New(): ' + E);
    }
}

function Cancel(ev) {
    try {
        unlock_top_buttons();
        g.selected_atb = get_atb_from_selection();
        if (!g.selected_atb) { return; }

        if (g.selected_atb.id()) { // existing atb

            g.layout = JSON2js(g.selected_atb.layout());
            populate_list2_list3();
            xulG.render_toolbar_layout(g.layout);

        } else { // new atb

            populate_list1();
            populate_list2_list3();
        }

    } catch(E) {
        alert('Error in toolbar.js, Cancel(): ' + E);
    }
}

function Save(ev) {
    try {
        g.selected_atb.layout( js2JSON( g.layout ) );
        switch($('context').selectedIndex) {
            case 0: // org
                g.selected_atb.org($('lib_menu').value);
                g.selected_atb.ws(null);
                g.selected_atb.usr(null);
            break;
            case 1: // ws
                g.selected_atb.org(null);
                g.selected_atb.ws(ses('ws_id'));
                g.selected_atb.usr(null);
            break;
            case 2: // usr
                g.selected_atb.org(null);
                g.selected_atb.ws(null);
                g.selected_atb.usr(ses('staff_id'));
            break;
        }
        g.selected_atb.ischanged(1);

        g.pcrud.apply(g.selected_atb);

        setTimeout( // is pcrud implicitly authoritative?
            function() {
                JSAN.use('util.network');
                var net = new util.network;
                var r = net.simple_request(
                    'FM_ATB_RETRIEVE_VIA_PCRUD',
                    [
                        ses(),
                        {
                            "-or": [
                                { "ws" : g.data.list.au[0].wsid() },
                                { "usr" : g.data.list.au[0].id() },
                                { "org" : util.functional.map_list( g.data.list.my_aou, function(o) { return o.id(); } ) }
                            ]
                        },
                        {
                            "order_by":{"atb":"label"}
                        }
                    ]
                );
                g.data.hash.atb = util.functional.convert_object_list_to_hash(r,null);
                g.data.list.atb = r;

                g.data.stash('hash','list');

                unlock_top_buttons();

                populate_list1();
            }, 1000
        );

    } catch(E) {
        alert('Error in toolbar.js, Save(): ' + E);
    }
}


