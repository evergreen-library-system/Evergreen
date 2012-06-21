dojo.require('dijit.layout.TabContainer');
dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.MarcXPathParser');
dojo.require('openils.widget.OrgUnitFilteringSelect');


var provider;
var xpathParser = new openils.MarcXPathParser();
var subFields= [];
var adminPermOrgs = [];
var viewPermOrgs = [];
var user;
var viewPerms = [
    'ADMIN_PROVIDER', 
    'MANAGE_PROVIDER', 
    'VIEW_PROVIDER'
]; 
    

function draw() {

    user = new openils.User();

    if(providerId) {
        drawOneProvider();
        return;
    }

    openils.Util.hide('provider-details-div');

    // after a provider is created, load the provider page
    pListGrid.onPostCreate = function(fmObject) {
        location.href = location.href + '/' + fmObject.id();
    }

    user.buildPermOrgSelector(
        viewPerms,
        contextOrgSelector, null,

        function() {
            if (!contextOrgSelector.attr('value')) return

            dojo.connect(contextOrgSelector, 'onChange', drawProviderGrid);

            // fetch the admin org units
            user.getPermOrgList(
                'ADMIN_PROVIDER',

                function(list) {
                    adminPermOrgs = list;

                    // fetch the view org units
                    user.getPermOrgList(
                        viewPerms,
                        function(list2) {
                            viewPermOrgs = list2
                            drawProviderGrid();
                        },
                        true, true
                    );
                },
                true, true
            );
        }
    );
}


function drawOneProvider() {
    openils.Util.hide('provider-list-div');
   
    var pcrud = new openils.PermaCrud();
    pcrud.retrieve('acqpro', providerId, {
        oncomplete : function(r) {
            provider = openils.Util.readResponse(r);
            console.log('provider is' + js2JSON(provider));
            var pane = new openils.widget.EditPane({fmObject:provider, paneStackCount:2}, dojo.byId('provider-summary-pane'));
            pane.startup();
            console.log("pane started");
            dojo.connect(providerTabs, 'selectChild', drawProviderSummary);                        
        }
    });
  
    drawProviderSummary();
}


function drawProviderGrid() {
    pListGrid.resetStore();

    // view providers for here plus children
    var list = fieldmapper.aou.descendantNodeList(
        contextOrgSelector.attr('value'), true, true);

    pListGrid.loadAll(
        {order_by : [ // sort providers I can edit to the front
            {   'class' : 'acqpro',
                field : 'owner',
                compare : {'in' : adminPermOrgs},
                direction : 'desc'
            },
            {   'class' : 'acqpro',
                field : 'name'
            }
        ]}, 
        {'owner' : list}
    );
}

function drawProviderSummary(child) {
    var loadedTabs = {'provider-address' : true};
    if(child){   
        if(loadedTabs[child.id]) return;
        loadedTabs[child.id] = true;
        switch(child.id) {
        case 'tab-pro-contact': 
            pcListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            pcListGrid.resetStore();
            pcListGrid.loadAll({
                oncomplete:function(r) {
                    var count = 0; 
                    pcListGrid.store.fetch( {
                        onComplete:function(list) { 
                            count =  list.length
                            if (count>=1) {
                                var contactIds = [];                                                    
                                dojo.forEach(list, function(item) {
                                        contactIds.push(pcListGrid.store.getValue(item, 'id')); 
                                });
                            
                                pcaListGrid.overrideEditWidgets.contact = new
                                dijit.form.FilteringSelect({store: pcListGrid.store});
                                pcaListGrid.resetStore();
                                pcaListGrid.loadAll({order_by:{acqpca : 'contact'}}, {contact: contactIds});

                            } else { 
                                return;
                            }            
                        }
                    });
                }
            }, {provider : providerId});
            
            break;

        case 'tab-attr': 
            padListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            padListGrid.resetStore();
            padListGrid.loadAll({order_by:{acqlipad : 'code'}}, {provider : providerId});
            break;

        case 'tab-hold': 
            phsListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            phsListGrid.overrideEditWidgets.name = holdingSubfieldSelector;
            phsListGrid.onEditPane = function(pane) {
                holdingSubfieldSelector.attr('value', pane.fmObject.name());
            }
            phsListGrid.resetStore();
            phsListGrid.loadAll({order_by:{acqphsm : 'name'}}, {provider : providerId});
            break;

        case "tab-invoice":
            invListGrid.resetStore();
            invListGrid.loadAll(
                {"order_by": {"acqinv": "recv_date DESC"}},
                {"provider": providerId}
            );
            break;

        default:
            paListGrid.overrideEditWidgets.provider = new
                dijit.form.TextBox({disabled: 'true', value: providerId});
            paListGrid.resetStore();
            paListGrid.loadAll({order_by:{acqpa:'provider'}}, {provider: providerId}); 
        }
        
    } else {
        paListGrid.overrideEditWidgets.provider = new
            dijit.form.TextBox({disabled: 'true', value: providerId});
        paListGrid.resetStore();
        paListGrid.loadAll({order_by:{acqpa:'provider'}}, {provider: providerId}); 
    }
}


function getParsedTag(rowIndex, item) {
    return item && xpathParser.parse(padListGrid.store.getValue(item, 'xpath')).tags;
}


function getParsedSubf(rowIndex, item) {
    if(item) {
        var subfields = xpathParser.parse(padListGrid.store.getValue(item, 'xpath')).subfields;
        return subfields.join(',');
    }
    return'';
}


openils.Util.addOnLoad(draw);
