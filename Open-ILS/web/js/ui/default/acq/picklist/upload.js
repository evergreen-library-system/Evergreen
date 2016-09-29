dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.ComboBox');
dojo.require('dijit.form.Button');
dojo.require("dojo.io.iframe");
dojo.require('openils.User');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.acq.Picklist');
dojo.require('openils.XUL');
dojo.require('openils.PermaCrud');

var VANDELAY_URL = '/vandelay-upload';
var providerWidget;
var orderAgencyWidget;
var vlAgent;
var usingNewPl = false;

function init() {
    dojo.byId('acq-pl-upload-ses').value = openils.User.authtoken;
    vlAgent = new VLAgent();
    vlAgent.init(init2);
}

function init2() {

    loadYearSelector();

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'provider',
        orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
        parentNode : dojo.byId('acq-pl-upload-provider'),
    }).build(
        function(w) { 
            providerWidget = w;
            vlAgent.readCachedValue(w, 'provider', true);
        }
    );

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'ordering_agency',
        orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
        parentNode : dojo.byId('acq-pl-upload-agency'),
    }).build(
        function(w) { 
            orderAgencyWidget = w 
            vlAgent.readCachedValue(w, 'ordering_agency');
            dojo.connect(orderAgencyWidget, 'onChange', setDefaultFiscalYear);
        }
    );

    vlAgent.readCachedValue(acqPlUploadCreatePo, 'create_po');
    vlAgent.readCachedValue(acqPlUploadActivatePo, 'activate_po');

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.user.retrieve.atomic'],
        {   async: true,
            params: [openils.User.authtoken], 
            oncomplete : function(r) {
                var list = openils.Util.readResponse(r);
                acqPlUploadPlSelector.store = 
                    new dojo.data.ItemFileWriteStore({data:acqpl.toStoreData(list)});
            }
        }
    );
}

function setDefaultFiscalYear(org) {
    org = org || orderAgencyWidget.attr('value');

    // NOTE: Evergreen does not yet offer an interface for managing
    // fiscal years.  For now, make the fiscal year selector persistant
    vlAgent.readCachedValue(acqUploadYearSelector, 'fiscal_year');
    return;

    if (org) {

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.org_unit.current_fiscal_year'],
            {   params : [openils.User.authtoken, org],
                async : true,
                oncomplete : function(r) {
                    var year = openils.Util.readResponse(r);
                    acqUploadYearSelector.attr('value', year);
                }
            }
        );
    }
}

function acqUploadRecords() {

    // persist widget values
    vlAgent.writeCachedValue(acqPlUploadCreatePo, 'create_po');
    vlAgent.writeCachedValue(acqPlUploadActivatePo, 'activate_po');
    vlAgent.writeCachedValue(providerWidget, 'provider');
    vlAgent.writeCachedValue(orderAgencyWidget, 'ordering_agency');
    vlAgent.writeCachedValue(acqUploadYearSelector, 'fiscal_year');

    openils.Util.show('acq-pl-upload-progress');
    var picklist = acqPlUploadPlSelector.attr('value');
    if(picklist) {
        // ComboBox value is the display string.  find the actual picklist
        // and create a new one if necessary
        acqPlUploadPlSelector.store.fetch({
            query : {name:picklist}, 
            onComplete : function(items) {
                if(items.length == 0) {
                    // create a new picklist for these items
                    usingNewPl = true;
                    openils.acq.Picklist.create(
                        {name:picklist, org_unit: orderAgencyWidget.attr('value')},
                        function(plId) { acqSendUploadForm({picklist:plId}) }
                    );
                } else {
                    usingNewPl = false;
                    acqSendUploadForm({picklist:items[0].id[0]});
                }
            }
        });
    } else {
        acqSendUploadForm({picklist:null});
    }
}

function acqSendUploadForm(args) {
    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('acq-pl-upload-form'),
        handle: function(data, ioArgs){
            acqHandlePostUpload(data.documentElement.textContent, args.picklist);
        }
    });
}


function acqHandlePostUpload(key, plId) {

    var args = {
        picklist : plId,
        provider : providerWidget.attr('value'),
        ordering_agency : orderAgencyWidget.attr('value'),
        create_po : acqPlUploadCreatePo.attr('value'),
        activate_po : acqPlUploadActivatePo.attr('value'),
        vandelay : vlAgent.values(),
        fiscal_year : acqUploadYearSelector.attr('value')
    };

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.process_upload_records'],
        {   async: true,
            params: [openils.User.authtoken, key, args],
            onresponse : function(r) {

                vlAgent.handleResponse(
                    openils.Util.readResponse(r),
                    function(resp, res) {

                        openils.Util.hide('acq-pl-upload-complete-pl');
                        openils.Util.hide('acq-pl-upload-complete-po');
                        openils.Util.hide('acq-pl-upload-complete-q');
                        openils.Util.hide('acq-pl-upload-progress-bar');
                        openils.Util.show('acq-pl-upload-complete');

                        function activateLink(link, url, name) {
                            link = dojo.byId(link);
                            openils.Util.show(link);
                            if (name) link.innerHTML = name;
                            if (typeof xulG == 'undefined') { // browser
                                link.setAttribute('href', url); 
                            } else {
                                link.setAttribute('href', 'javascript:;'); // for linky-ness
                                if (window.IAMBROWSER) {
                                    link.onclick = function() { xulG.relay_url(url) };
                                } else {
                                    link.onclick = function() { openils.XUL.newTabEasy(url, null, null, true) };
                                }
                            }
                        }
                            
                        if(res.picklist_url) {
                            activateLink('acq-pl-upload-complete-pl', res.picklist_url);

                            // if the user entered a new picklist, refetch the set to pick
                            // up the ID and redraw the list with the new one selected
                            if (usingNewPl) {
                                var newPl = new openils.PermaCrud().retrieve('acqpl', resp.picklist.id());
                                acqPlUploadPlSelector.store.newItem(newPl.toStoreItem());
                                acqPlUploadPlSelector.attr('value', newPl.name());
                            }
                        } 

                        if(res.po_url) {
                            activateLink('acq-pl-upload-complete-po', res.po_url);
                        }

                        if (res.queue_url) {
                            activateLink('acq-pl-upload-complete-q', res.queue_url);
                        }
                    }
                );
            },
        }
    );
}

function loadYearSelector() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.org.years.retrieve'],
        {   async : true,
            params : [openils.User.authtoken, {}, {limit_perm : 'VIEW_FUND'}],
            oncomplete : function(r) {

                var yearList = openils.Util.readResponse(r);
                if(!yearList) return;
                yearList = yearList.map(function(year){return {year:year+''};}); // dojo wants strings

                var yearStore = {identifier:'year', name:'year', items:yearList};
                acqUploadYearSelector.store = new dojo.data.ItemFileReadStore({data:yearStore});

                // until an ordering agency is selected, default to the 
                // fiscal year of the workstation
                setDefaultFiscalYear(new openils.User().user.ws_ou());
            }
        }
    );
}



openils.Util.addOnLoad(init);

