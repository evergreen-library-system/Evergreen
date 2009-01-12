if(!dojo._hasResource['openils.widget.EditDialog']) {
    dojo.provide('openils.widget.EditDialog');
    dojo.require('openils.widget.EditPane');
    dojo.require('dijit.Dialog');


    /**
     * Given a fieldmapper object, this builds a pop-up dialog used for editing the object
     */

    dojo.declare(
        'openils.widget.EditDialog',
        [dijit.Dialog],
        {
            fmClass : '',
            fmObject : null,
            mode : 'update',
            fieldOrder : null, // ordered list of field names, optional.

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                this.inherited(arguments);
                var pane = new openils.widget.EditPane();
                pane.mode = this.mode;
                pane.fmClass = this.fmClass;
                pane.fmObject = this.fmObject;
                pane.fieldOrder = this.fieldOrder;
                pane.startup();
                this.domNode.appendChild(pane.domNode);
            }
        }
    );
}

