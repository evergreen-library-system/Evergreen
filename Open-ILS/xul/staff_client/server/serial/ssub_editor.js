dump('entering serial/ssub_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.ssub_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('serial/ssub_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};

};

serial.ssub_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'ssub',
    'fm_type_plural' : 'ssubs',
    'can_have_notes' : true,

    'init' : function (params) {
        var obj = this;

        params.retrieve_function = 'FM_SSUB_FLESHED_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        /* Do it */
        obj.summarize( obj.ssubs );
        obj.render();
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'reset' : serial.editor_base.editor_base_reset,

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */

    'apply' : function(field, value) {
        var obj = this;

        if (field == 'start_date' || field == 'end_date') {
            if (value == '') { value = null; }
        }

        obj.editor_base_apply(field, value);
    },


    /******************************************************************************************************/
    /* These need data from the middle layer to render */

    /*
    function init_panes0() {
    obj.special_exception = {};
    obj.special_exception[$('catStrings').getString('staff.cat.copy_editor.field.owning_library.label')] = function(label,value) {
            JSAN.use('util.widgets');
            if (value>0) { // an existing call number
                obj.network.simple_request(
                    'FM_ACN_RETRIEVE.authoritative',
                    [ value ],
                    function(req) {
                        var cn = '??? id = ' + value;
                        try {
                            cn = req.getResultObject();
                        } catch(E) {
                            obj.error.sdump('D_ERROR','callnumber retrieve: ' + E);
                        }
                        util.widgets.set_text(label,obj.data.hash.aou[ cn.owning_lib() ].shortname() + ' : ' + cn.label());
                    }
                );
            } else { // a yet to be created call number
                if (obj.callnumbers) {
                    util.widgets.set_text(label,obj.data.hash.aou[ obj.callnumbers[value].owning_lib ].shortname() + ' : ' + obj.callnumbers[value].label);
                }
            }
        };
    },
    */

    /******************************************************************************************************/
    /* These get show in the left panel */

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

        'left_pane' :
        [
            [
                'id',
                { 
                    //input: 'c = function(v){ obj.apply("distribution",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

                }
            ],
            [
                'owning_lib',
                {
                    render: 'typeof fm.owning_lib() == "object" ? fm.owning_lib().shortname() : obj.data.hash.aou[ fm.owning_lib() ].shortname()',
                    input: 'c = function(v){ obj.apply("owning_lib",v); if (typeof post_c == "function") post_c(v); }; x = util.widgets.make_menulist( util.functional.map_list( obj.data.list.aou, function(myobj) { var sname = myobj.shortname(); for (i = sname.length; i < 20; i++) sname += " "; return [ myobj.name() ? sname + " " + myobj.name() : myobj.shortname(), myobj.id(), false, ( obj.data.hash.aout[ myobj.ou_type() ].depth() * 2), ]; }), obj.data.list.au[0].ws_ou()); x.setAttribute("value",obj.editor_values.owning_lib); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'owning_lib',
                    dropdown_key: 'fm.owning_lib() == null ? null : typeof fm.owning_lib() == "object" ? fm.owning_lib().id() : fm.owning_lib()',
                }
            ],
        ],

            'right_pane' :
        [
            [
                'start_date',
                { 
                    render: 'fm.start_date() == null ? "" : util.date.formatted_date( fm.start_date(), "%F");',
                    input: 'c = function(v){ obj.apply("start_date",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.start_date); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'start_date',
                    required: true
                }
            ],
            [
                'end_date',
                {
                    render: 'fm.end_date() == null ? "" : util.date.formatted_date( fm.end_date(), "%F");',
                    input: 'c = function(v){ obj.apply("end_date",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.end_date); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'end_date'
                }
            ],
            [
                'expected_date_offset',
                { 
                    input: 'c = function(v){ obj.apply("expected_date_offset",v); if (typeof post_c == "function") post_c(v); }; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.expected_date_offset); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'expected_date_offset'
                }
            ],
        ],

        };
    },

    /******************************************************************************************************/
    /* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

    'summarize' : serial.editor_base.editor_base_summarize,

    /******************************************************************************************************/
    /* Display the summarized data and inputs for editing */

    'render' : serial.editor_base.editor_base_render,

    /******************************************************************************************************/
    /* This actually draws the change button and input widget for a given field */
    'render_input' : serial.editor_base.editor_base_render_input,

    /******************************************************************************************************/
    /* save the subscriptions */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.subscription.fleshed.batch.update');
    },

    /******************************************************************************************************/
    /* spawn notes interface */

    'notes' : function() {
        var obj = this;
        JSAN.use('util.window'); var win = new util.window();
        win.open(
            urls.XUL_SERIAL_NOTES, 
            $('serialStrings').getString('staff.serial.ssub_editor.notes'),'chrome,resizable,modal',
            { 'object_id' : obj.ssubs[0].id(), 'function_type' : 'SSUBN', 'object_type' : 'subscription', 'constructor' : ssubn }
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes
};

dump('exiting serial/ssub_editor.js\n');
