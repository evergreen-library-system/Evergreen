dump('entering serial/sitem_editor.js\n');
// vim:noet:sw=4:ts=4:

JSAN.addRepository('/xul/server/');
JSAN.use('serial.editor_base');

if (typeof serial == 'undefined') serial = {};
serial.sitem_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
        JSAN.use('util.network'); this.network = new util.network();
    } catch(E) {
        dump('serial/sitem_editor: ' + E + '\n');
    }

    /* This keeps track of what fields have been edited for styling purposes */
    this.changed = {};

    /* This holds the original values for prepopulating the field editors */
    this.editor_values = {};
};

serial.sitem_editor.prototype = {
    // we could do this with non-standard '__proto__' property instead
    'editor_base_init' : serial.editor_base.editor_base_init,
    'editor_base_apply' : serial.editor_base.editor_base_apply,
    'editor_base_save' : serial.editor_base.editor_base_save,

    'fm_type' : 'sitem',
    'fm_type_plural' : 'sitems',
    'can_have_notes' : true,

    'init' : function (params) {
        var obj = this;

        params.retrieve_function = 'FM_SITEM_FLESHED_BATCH_RETRIEVE.authoritative';

        obj.editor_base_init(params);

        /* Do it */
        obj.summarize( obj.sitems );
        obj.render();
    },

    /******************************************************************************************************/
    /* Restore backup copies */

    'reset' :  serial.editor_base.editor_base_reset,

    /******************************************************************************************************/
    /* Apply a value to a specific field on all the copies being edited */

    'apply' : function(field,value) {
        var obj = this;
        JSAN.use('util.date');
        if (field == 'date_expected') {
            if (value == '') {
                alert("Date Expected cannot be unset.");
                return false;
            } else if (!util.date.check('YYYY-MM-DD',value)) {
                alert("Invalid Date");
                return false;
            }
        } else if (field == 'date_received') { // manually unset not allowed
            if (value == '') {
                alert("Date Received cannot be manually unset; use 'Reset to Expected' instead.");
                return false;
            } else if (!util.date.check('YYYY-MM-DD',value)) {
                alert("Invalid Date");
                return false;
            }
        }
        obj.editor_base_apply(field, value);
        return true;
    },

    /******************************************************************************************************/

    'init_panes' : function () {
        var obj = this;
        obj.panes_and_field_names = {

        /* These get shown in the left panel */
        'sitem_editor_left_pane' :
        [
            [
                'id',
                { 
                }
            ],
            [
                'status',
                { 
                }
            ]
        ],
        /* These get shown in the middle panel */
        'sitem_editor_middle_pane' :
        [
            [
                'distribution',
                {
                    render: 'fm.stream().distribution().label() == null ? "" : fm.stream().distribution().label();',
                    label: fieldmapper.IDL.fmclasses.sstr.field_map.distribution.label

                }
            ],
            [
                'unit',
                {
                    render: 'fm.unit() == null ? "" : "#" + fm.unit().id();',
                }
            ],
        ],

        /* These get shown in the right panel */
        'sitem_editor_right_pane' :
        [
            [
                'date_expected',
                {
                    render: 'fm.date_expected() == null ? "" : util.date.formatted_date( fm.date_expected(), "%F");',
                    input: 'c = function(v){ var applied = obj.apply("date_expected",v); if (typeof post_c == "function") post_c(v, !applied);}; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.date_expected); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
                    value_key: 'date_expected'
                }
            ],
            [
                'date_received',
                {
                    render: 'fm.date_received() == null ? "" : util.date.formatted_date( fm.date_received(), "%F");',
                    input: 'if (obj.editor_values.date_received) { c = function(v){ var applied = obj.apply("date_received",v); if (typeof post_c == "function") post_c(v, !applied);}; x = document.createElement("textbox"); x.setAttribute("value",obj.editor_values.date_received); x.addEventListener("apply",function(f){ return function(ev) { f(ev.target.value); } }(c), false); } else { alert("Cannot edit Date Received for unreceived items."); block = false; }',
                    value_key: 'date_received'
                }
            ],
        ],

        };
    },

    /******************************************************************************************************/
    /* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

    'summarize' :  serial.editor_base.editor_base_summarize,

    /******************************************************************************************************/
    /* Display the summarized data and inputs for editing */

    'render' :  serial.editor_base.editor_base_render,

    /******************************************************************************************************/
    /* This actually draws the change button and input widget for a given field */
    'render_input' : serial.editor_base.editor_base_render_input,

    /******************************************************************************************************/
    /* save the items */

    'save' : function() {
        var obj = this;
        obj.editor_base_save('open-ils.serial.item.fleshed.batch.update');
    },

    /******************************************************************************************************/
    /* spawn notes interface */

    'notes' : function() {
        var obj = this;
        JSAN.use('util.window'); var win = new util.window();
        win.open(
            urls.XUL_SERIAL_NOTES, 
            //+ '?copy_id=' + window.escape(obj.sitems[0].id()),
            'Item Notes','chrome,resizable,modal',
            { 'object_id' : obj.sitems[0].id(), 'function_type' : 'SIN', 'object_type' : 'item', 'constructor' : sin }
        );
    },

    /******************************************************************************************************/
    'save_attributes' : serial.editor_base.editor_base_save_attributes

};

dump('exiting serial/sitem.js\n');
