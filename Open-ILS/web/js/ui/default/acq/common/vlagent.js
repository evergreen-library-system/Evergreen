dojo.require('openils.widget.AutoFieldWidget');

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
                        parentNode : dojo.byId('acq_vl:' + widg.key)
                    }).build(function(dijit) { 
                        widg.dijit = dijit; 
                    }); 

                } else { // bools
                    widg.dijit = dijit.byId('acq_vl:' + widg.key);
                }
            }
        );
        
        // loaded != all widgets are done rendering,
        // only that init() has been called.
        this.loaded = true;
    }

    this.values = function() {
        var values = {};
        dojo.forEach(this.widgets,
            function(widg) {
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
                res.queue_url = oilsBasePath + '/vandelay/vandelay?qtype=bib&qid=' + resp.queue.id();
            }

            if (oncomplete) 
                oncomplete(resp, res);

            return res;
        }

        return false; // not yet complete
    }
}
