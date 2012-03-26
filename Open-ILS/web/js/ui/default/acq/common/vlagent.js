dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');

function VLAgent(args) {
    args = args || {};
    for (var key in args) { 
        this[key] = args[key]; 
    }

    this.widgets = [  
        {key : 'import_no_match'},
        {key : 'auto_overlay_exact'},
        {key : 'auto_overlay_1match'},
        {key : 'auto_overlay_best_match'},
        {key : 'match_quality_ratio'},
        {key : 'queue_name'},
        {key : 'create_assets'},
        {key : 'match_set', cls : 'vms'},
        {key : 'bib_source', cls : 'cbs'},
        {key : 'merge_profile', cls : 'vmp'},
        {key : 'fall_through_merge_profile', cls : 'vmp'},
        {key : 'existing_queue', cls : 'vbq'}
    ];
    
    this.loaded = false;

    this.init = function() {
        var self = this;

        dojo.forEach(this.widgets,
            function(widg) {
                if (widg.cls) { // selectors

                    new openils.widget.AutoFieldWidget({
                        fmClass : widg.cls,
                        selfReference : true,
                        orgLimitPerms : [self.limitPerm || 'CREATE_PURCHASE_ORDER'],
                        parentNode : dojo.byId('acq_vl:' + widg.key),
                        searchFilter : (widg.cls == 'vbq') ? {queue_type : 'acq'} : null,
                        useWriteStore :  (widg.cls == 'vbq')
                    }).build(function(dijit) { 
                        widg.dijit = dijit; 
                        self.attachOnChange(widg);
                    }); 

                } else { // bools
                    widg.dijit = dijit.byId('acq_vl:' + widg.key);
                    if (!widg.dijit) return; // some fields optional
                    self.attachOnChange(widg);
                }
            }
        );
        
        // loaded != all widgets are done rendering,
        // only that init() has been called.
        this.loaded = true;
    }

    this.attachOnChange = function(widg) {
        var self = this;
        var qInputChange;

        var qSelChange = function(val) {
            // user selected a queue from the selector;  clear the text input 
            // and set the item import profile already defined for the queue

            var qInput = self.getDijit('queue_name');
            var matchSetSelector = self.getDijit('match_set');
            var qSelector = self.getDijit('existing_queue');

            if(val) {
                qSelector.store.fetch({
                    query : {id : val+''},
                    onComplete : function(items) {
                        matchSetSelector.attr('value', items[0].match_set[0] || '');
                        matchSetSelector.attr('disabled', true);
                    }
                });
            } else {
                matchSetSelector.attr('value', '');
                matchSetSelector.attr('disabled', false);
            }

            // detach and reattach to avoid onchange firing while when we clear
            dojo.disconnect(qInput._onchange);
            qInput.attr('value', '');
            qInput._onchange = dojo.connect(qInput, 'onChange', qInputChange);
        }

        qInputChange = function(val) {

            var qSelector = self.getDijit('existing_queue');
            var matchSetSelector = self.getDijit('match_set');
            var foundMatch = false;

            if (val) {

                // if the user entered the name of an existing queue, update the 
                // queue selector to match the value (and clear the text input 
                // via qselector onchange)
                qSelector.store.fetch({
                    query:{name:val},
                    onComplete:function(items) {
                        if(items.length == 0) return;
                        var item = items[0];
                        qSelector.attr('value', item.id);
                        foundMatch = true;
                    }
                });
            }

            if (!foundMatch) {
                self.getDijit('match_set').attr('disabled', false);
                dojo.disconnect(qSelector._onchange);
                qSelector.attr('value', '');
                qSelector._onchange = dojo.connect(qSelector, 'onChange', qSelChange);
            }
        }

        if (widg.key == 'existing_queue') {
            var qSelector = self.getDijit('existing_queue');
            qSelector._onchange = dojo.connect(qSelector, 'onChange', qSelChange);
        } else if(widg.key == 'queue_name') {
            var qInput = self.getDijit('queue_name');
            qInput._onchange = dojo.connect(qInput, 'onChange', qInputChange);
        }
    }

    this.getDijit = function(key) {
        return this.widgets.filter(function(w) {return (w.key == key)})[0].dijit;
    }

    this.values = function() {
        var values = {};
        dojo.forEach(this.widgets,
            function(widg) {
                if (widg.dijit)
                    values[widg.key] = widg.dijit.attr('value');
            }
        );
        return values;
    }

    this.handleResponse = function(resp, oncomplete) {
        if(!resp) return;
        var res = {}

        console.log('vandelay import returned : ' + js2JSON(resp));

        // update the display counts
        dojo.byId('acq_vl:li-processed').innerHTML = resp.li;
        dojo.byId('acq_vl:vqbr-processed').innerHTML = resp.vqbr;
        dojo.byId('acq_vl:bibs-processed').innerHTML = resp.bibs;
        dojo.byId('acq_vl:lid-processed').innerHTML = resp.lid;
        dojo.byId('acq_vl:debits-processed').innerHTML = resp.debits_accrued;
        dojo.byId('acq_vl:copies-processed').innerHTML = resp.copies;

        if (resp.complete) {

            if(resp.picklist) {
                res.picklist_url = oilsBasePath + '/acq/picklist/view/' + resp.picklist.id();
            } 

            if(resp.purchase_order) {
                res.po_url = oilsBasePath + '/acq/po/view/' + resp.purchase_order.id();
            }

            if (resp.queue) {
                var newQid = resp.queue.id();
                res.queue_url = oilsBasePath + '/vandelay/vandelay?qtype=bib&qid=' + newQid;

                var qInput = this.getDijit('queue_name');

                if (newQName = qInput.attr('value')) {
                    // user created a new queue.  Fetch the new queue object,
                    // replace the ReadStore with a WriteStore and insert.
                    qInput.attr('value', '');
                    var qSelector = this.getDijit('existing_queue');
                    var newQ = new openils.PermaCrud().retrieve('vbq', newQid);
                    qSelector.store.newItem(newQ.toStoreItem());
                    qSelector.attr('value', newQid);
                }
            }

            if (oncomplete) 
                oncomplete(resp, res);

            return res;
        }

        return false; // not yet complete
    }
}
