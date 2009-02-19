/**
var dialog = new openils.widget.EditDialog({
    fmObject: survey,
    fieldOrder: ['id', 'name', 'description', 'start_date', 'end_date']
});
dialog.startup();
dialog.show();
*/



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
            editPane : null, // reference to our EditPane object

            constructor : function(args) {
                this.editPane = new openils.widget.EditPane(args);
                var self = this;

                this.editPane.onCancel = function() { 
                    if(args.onCancel)
                        args.onCancel();
                    self.hide(); 
                }

                this.editPane.onPostSubmit = function(r) { 
                    self.hide(); 
                    if(args.onPostSubmit)
                        args.onPostSubmit(r);
                }
            },

            /**
             * Builds a basic table of key / value pairs.  Keys are IDL display labels.
             * Values are dijit's, when values set
             */
            startup : function() {
                this.inherited(arguments);
                this.editPane.startup();
                this.domNode.appendChild(this.editPane.domNode);
            }
        }
    );
}

