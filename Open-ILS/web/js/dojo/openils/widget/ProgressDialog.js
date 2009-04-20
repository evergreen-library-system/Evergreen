if(!dojo._hasResource['openils.widget.ProgressDialog']) {
    dojo.provide('openils.widget.ProgressDialog');
    dojo.require('dijit.ProgressBar');
    dojo.require('dijit.Dialog');
    dojo.require('openils.Util');

    /**
     * A popup dialog with an embedded progress bar.  imagine that.
     */

    dojo.declare(
        'openils.widget.ProgressDialog',
        [dijit.Dialog],
        {
            indeterminate : false,

            startup : function() {
                this.inherited(arguments);
                this.progress = new dijit.ProgressBar();
                this.progress.indeterminate = this.indeterminate;
                this.progress.startup();
                openils.Util.addCSSClass(this.progress.domNode, 'oils-progress-dialog');
                this.containerNode.appendChild(this.progress.domNode);
                if(this.indeterminate) this.update();
            },

            update : function() {
                this.progress.update.apply(this.progress, arguments);
            },

            setInd : function(isInd) {
                this.progress.indeterminate = this.indeterminate = isInd;
            }
        }
    );
}
 
