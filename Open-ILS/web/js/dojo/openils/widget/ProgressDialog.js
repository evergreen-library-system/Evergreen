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
            message : '',

            startup : function() {
                this.inherited(arguments);
                this.progress = new dijit.ProgressBar();
                this.progress.startup();
                openils.Util.addCSSClass(this.progress.domNode, 'oils-progress-dialog');
                this.containerNode.appendChild(this.progress.domNode);
            },

            update : function() {
                this.progress.update.apply(this.progress, arguments);
            },

            show : function(ind, msg) {
                if(ind || this.indeterminate) {
                    this.progress.indeterminate = true;
                    this.update();
                } else {
                    this.progress.indeterminate = false;
                }

                if(msg || (msg = this.message) ) {
                    if(!this.msgDiv) {
                        this.msgDiv = dojo.create('div', {innerHTML : msg});
                    }
                    this.containerNode.insertBefore(this.msgDiv, this.progress.domNode);
                } else {
                    if(this.msgDiv) {
                        this.containerNode.removeChild(this.msgDiv);
                        this.msgDiv = null;
                    }
                }
                    
                this.inherited(arguments);
            },

            update_message : function(msg) {
                if(msg || (msg = this.message) ) {
                    if(!this.msgDiv) {
                        this.msgDiv = dojo.create('div', {innerHTML : msg});
                        this.containerNode.insertBefore(this.msgDiv, this.progress.domNode);
                    } else {
                        this.msgDiv.innerHTML = msg;
                    }
                } else {
                    if(this.msgDiv) {
                        this.containerNode.removeChild(this.msgDiv);
                        this.msgDiv = null;
                    }
                }
            }
        }
    );
}
 
