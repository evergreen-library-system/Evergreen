dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.widget.AutoGrid');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var contextOrg;

function setup() {

    if(reqId) {
        drawRequest();
    } else {
        drawList();
    }
}

function drawRequest() {
    // hide the grid and the context selector
    // draw a detail page for a particular request
    // including ability to add request to a picklist
    // and to "reject" it (aka apply a cancel reason)
}


// format the title data as id:title
function getTitle(idx, item) {
    if(item) {
        return this.grid.store.getValue(item, 'id') + ':' + 
        this.grid.store.getValue(item, 'title');
    }
    return ''
}

// turn id:title into a url
function formatTitle(value) {
    if(value) {
        var parts = value.split(/:/);
        return '<a href="' + oilsBasePath + 
            '/acq/picklist/user_request/' + parts[0] + '">' + parts[1] + '</a>';
    }
}

function drawList() {
    buildGrid();

    var connect = function() {
        dojo.connect(contextOrgSelector, 'onChange',
            function() {
                contextOrg = this.attr('value');
                rGrid.resetStore();
                buildGrid();
            }
        );
    };

    new openils.User().buildPermOrgSelector(
        'CREATE_PICKLIST', contextOrgSelector, null, connect);
}

function buildGrid() {

    if(contextOrg == null)
        contextOrg = openils.User.user.ws_ou();

    rGrid.loadAll(
        {   order_by : {aur : 'request_date'},
            join : 'au' 
        },
        {
            cancel_reason : null,
            '+au' : {
                home_ou : fieldmapper.aou.descendantNodeList(contextOrg).map(
                    function(item) { return item.id(); })
            }
        }
    );
}

openils.Util.addOnLoad(setup);


