dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');
dojo.require('openils.XUL');
dojo.require('dojox.form.CheckedMultiSelect');

var xulStorage;
var storekey = 'eg.acq.upload.';
var osetkey = 'acq.upload.default.';
var persistOrgSettings;

// map local dijit keys/names to their org setting counterparts
var setNameMap = {
    match_set : 'vandelay.match_set',
    merge_profile : 'vandelay.merge_profile',
    create_assets : 'vandelay.load_item_for_imported',
    match_quality_ratio : 'vandelay.quality_ratio',
    auto_overlay_1match : 'vandelay.merge_on_single',
    import_no_match : 'vandelay.import_non_matching',
    fall_through_merge_profile : 'vandelay.low_quality_fall_thru_profile',
    auto_overlay_exact : 'vandelay.merge_on_exact',
    auto_overlay_best_match : 'vandelay.merge_on_best'
}

// per-UI setting to change this?
// if true, set default widget values from org settings
// (when defined) regardless of any locally persisted value
var ouSettingTrumpsPersist = true;

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
        {key : 'existing_queue', cls : 'vbq'},
        {key : 'strip_field_groups', cls : 'vibtg'}
    ];

    this.loaded = false;

    this.init = function(oncomplete) {
        var self = this;

	xulStorage = openils.XUL.localStorage();

        // load org unit persist setting values
        fieldmapper.standardRequest(
            ['open-ils.actor','open-ils.actor.ou_setting.ancestor_default.batch'],
            {   async : true,
                params : [
                    new openils.User().user.ws_ou(),
                    [   osetkey + 'create_po',
                        osetkey + 'activate_po',
                        osetkey + 'provider',
                        osetkey + 'vandelay.match_set',
                        osetkey + 'vandelay.merge_profile',
                        osetkey + 'vandelay.import_non_matching',
                        osetkey + 'vandelay.merge_on_exact',
                        osetkey + 'vandelay.merge_on_best',
                        osetkey + 'vandelay.merge_on_single',
                        osetkey + 'vandelay.quality_ratio',
                        osetkey + 'vandelay.low_quality_fall_thru_profile',
                        osetkey + 'vandelay.load_item_for_imported'
                    ]
                ],
                oncomplete : function(r) {
                    persistOrgSettings = openils.Util.readResponse(r);
                    self.init2();
                    if (oncomplete) 
                        oncomplete();
                }
            }
        );
    };

    this.init2 = function() {
        var self = this;
        // fetch the strip field groups, then continue init-ing

        var owner = fieldmapper.aou.orgNodeTrail(
            fieldmapper.aou.findOrgUnit(new openils.User().user.ws_ou()));

        new openils.PermaCrud().search('vibtg',
            {   always_apply : 'f',
                owner: owner.map(function(org) { return org.id(); })
            }, 
            {   order_by : {vibtg : ['label']},
                async: true,
                oncomplete: function(r) {
                    var trashGroups = openils.Util.readResponse(r);
                    var sel = dijit.byId('acq_vl:strip_field_groups');

                    var widg = self.widgets.filter(function(w) {
                        return w.key == 'strip_field_groups'})[0];
                    widg.dijit = sel;

                    if (trashGroups.length == 0) {
                        openils.Util.hide('vl-trash-groups-row');

                    } else {

                        dojo.forEach(trashGroups, function(grp) {
                            var sn = fieldmapper.aou.findOrgUnit(
                                grp.owner()).shortname();
                            var opt = {
                                label : grp.label() + '&nbsp;(' + sn + ')',
                                value : grp.id()
                            };
                            sel.addOption(opt);
                        });

                        self.readCachedValue(sel, 'strip_field_groups');
                    }

                    self.init3();
                }
            }
        );

    },

    this.init3 = function() {
        var self = this;

        dojo.forEach(this.widgets,
            function(widg) {
                var key = widg.key;

                // strip-fields widget built above
                if (key == 'strip_field_groups') return;

                if (widg.cls) { // selectors

                    new openils.widget.AutoFieldWidget({
                        fmClass : widg.cls,
                        selfReference : true,
                        orgLimitPerms : [self.limitPerm || 'CREATE_PURCHASE_ORDER'],
                        parentNode : dojo.byId('acq_vl:' + key),
                        searchFilter : (widg.cls == 'vbq') ? {queue_type : 'acq'} : null,
                        useWriteStore :  (widg.cls == 'vbq')
                    }).build(function(dij) { 
                        widg.dijit = dij; 
                        if (!key.match(/queue/))
                            self.readCachedValue(dij, key);
                        self.attachOnChange(widg);
                    }); 

                } else { // bools
                    widg.dijit = dijit.byId('acq_vl:' + key);
                    if (!widg.dijit) return; // some fields optional
                    if (!key.match(/queue/))
                        self.readCachedValue(widg.dijit, key);
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
        var self = this;
        var values = {};
        dojo.forEach(this.widgets,
            function(widg) {
                if (widg.dijit) {
                    values[widg.key] = widg.dijit.attr('value');
                    if (!widg.key.match(/queue/))
                        self.writeCachedValue(widg.dijit, widg.key);
                }
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
    };

    this.readCachedValue = function(dij, key, ousOnly) {
        var val;
        var setname = osetkey + (setNameMap[key] ? setNameMap[key] : key);

        if (ouSettingTrumpsPersist && persistOrgSettings[setname]) {
            val = persistOrgSettings[setname].value;
        } else {
            if (!ousOnly)
                val = xulStorage.getItem(storekey + key);
            if (!val && persistOrgSettings[setname])
                val = persistOrgSettings[setname].value;
        }

        if (val) dij.attr('value', val);
        return val;
    };

    this.writeCachedValue = function(dij, key) {
        var setname = osetkey + (setNameMap[key] ? setNameMap[key] : key);

        if (ouSettingTrumpsPersist && persistOrgSettings[setname]) {
            // don't muck up localStorage if we're using org settings
            xulStorage.removeItem(storekey + key);

        } else {
            var val = dij.attr('value');

            if (val === null || val === false || val == '') {
                xulStorage.removeItem(storekey + key);
            } else {
                xulStorage.setItem(storekey + key, val);
            }
        }
    };
}
