var FETCH_DESK_PAYMENTS = 'open-ils.circ:open-ils.circ.money.org_unit.desk_payments';
var FETCH_USER_PAYMENTS = 'open-ils.circ:open-ils.circ.money.org_unit.user_payments';

var myPerms = [ 'VIEW_TRANSACTION' ];
var crBaseOrg;

function crInit() {
    fetchUser();
    $('user').appendChild(text(USER.usrname()));

    setTimeout( 
        function() { 
            fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
            crSetCals();
            crBuildOrgs();
            crDrawRange();
        }, 
        20 
    );
}

function crSetCals() {

    Calendar.setup({
        inputField  : "cr_start",
        ifFormat    : "%Y-%m-%d",
        button      : "cr_start_trigger",
        align       : "Tl",           
        singleClick : true
    });

    Calendar.setup({
        inputField  : "cr_end",
        ifFormat    : "%Y-%m-%d",
        button      : "cr_end_trigger",
        align       : "Tl",           
        singleClick : true
    });

    var d = new Date();
    var y = d.getYear()+1900;
    var m = ((d.getMonth()+1)+'').replace(/^(\d)$/,'0$1');
    var da = (d.getDate()+'').replace(/^(\d)$/,'0$1');

    var dat = y+'-'+m+'-'+da;
    $('cr_start').value = dat;
    $('cr_end').value = dat;
}


function crCurrentOrg() {
    var selector = $('cr_orgs');
    return getSelectorVal(selector);
}

function crBuildOrgs() {

    var org = findOrgUnit(PERMS['VIEW_TRANSACTION']);

    if(!org) {
        $('cr_orgs').disabled = true;
        return;
    }

    org = findOrgUnit(org);
    var type = findOrgType(org.ou_type()) ;

    var selector = $('cr_orgs');
    buildOrgSel(selector, org, type.depth());

    for( var i = 0; i < selector.options.length; i++ ) {
        var opt = selector.options[i];
        if( !isTrue(findOrgType( findOrgUnit(opt.value).ou_type() ).can_have_users()) )
            opt.disabled = true;
    }

    selector.onchange = crDrawRange;

    crBaseOrg = org;

    var gotoOrg = USER.ws_ou();
    if( ! setSelector( selector, gotoOrg ) ) {
        gotoOrg = USER.home_ou();
        setSelector( selector, gotoOrg );
    }

    return gotoOrg;
}

function crDrawRange() {
    var org = crCurrentOrg();

    removeChildren($('cr_desk_payments'));
    removeChildren($('cr_user_payments'));

    var req = new Request( FETCH_DESK_PAYMENTS, SESSION, 
        org, $('cr_start').value, $('cr_end').value );
    req.callback(
        function(r) {
            drawFMObjectTable( { dest : 'cr_desk_payments', obj : r.getResultObject(), moneySummaryRow : true });
            sortables_init();
        }
    );
    req.send();

    var req = new Request( FETCH_USER_PAYMENTS, SESSION, 
        org, $('cr_start').value, $('cr_end').value );
    req.callback(
        function(r) {
            drawFMObjectTable( { dest : 'cr_user_payments', obj : r.getResultObject(), moneySummaryRow : true });
            sortables_init();
        }
    );
    req.send();
}




