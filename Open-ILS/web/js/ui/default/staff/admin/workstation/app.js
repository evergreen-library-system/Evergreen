/**
 * App to drive the base page. 
 * Login Form
 * Splash Page
 */

angular.module('egWorkstationAdmin', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/workstation/print/config', {
        templateUrl: './admin/workstation/t_print_config',
        controller: 'PrintConfigCtrl',
        resolve : resolver
    });

    $routeProvider.when('/admin/workstation/print/templates', {
        templateUrl: './admin/workstation/t_print_templates',
        controller: 'PrintTemplatesCtrl',
        resolve : resolver
    });

    $routeProvider.when('/admin/workstation/stored_prefs', {
        templateUrl: './admin/workstation/t_stored_prefs',
        controller: 'StoredPrefsCtrl',
        resolve : resolver
    });


    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/workstation/t_splash',
        controller : 'SplashCtrl',
        resolve : resolver
    });
}])

.controller('SplashCtrl',
       ['$scope','$window','$location','egCore','egConfirmDialog',
function($scope , $window , $location , egCore , egConfirmDialog) {

    var allWorkstations = [];
    var permMap = {};
    $scope.contextOrg = egCore.org.get(egCore.auth.user().ws_ou());

    egCore.perm.hasPermAt('REGISTER_WORKSTATION', true)
    .then(function(orgList) { 

        // hide orgs in the context org selector where this login
        // does not have the reg_ws perm
        $scope.wsOrgHidden = function(id) {
            return orgList.indexOf(id) == -1;
        }
        $scope.userHasRegPerm = 
            orgList.indexOf($scope.contextOrg.id()) > -1;
    });

    // fetch the stored WS info
    egCore.hatch.getItem('eg.workstation.all')
    .then(function(all) {
        allWorkstations = all || [];
        $scope.workstations = 
            allWorkstations.map(function(w) { return w.name });
        return egCore.hatch.getItem('eg.workstation.default');
    })
    .then(function(def) { 
        $scope.defaultWS = def;
        $scope.activeWS = $scope.selectedWS = egCore.auth.workstation() || def;
    });

    $scope.getWSLabel = function(ws) {
        return ws == $scope.defaultWS ? 
            egCore.strings.$replace(egCore.strings.DEFAULT_WS_LABEL, {ws:ws}) : ws;
    }

    $scope.setDefaultWS = function() {
        egCore.hatch.setItem(
            'eg.workstation.default', $scope.selectedWS)
        .then(function() { $scope.defaultWS = $scope.selectedWS });
    }

    $scope.cant_have_users = function (id) { return !egCore.org.CanHaveUsers(id); };
    $scope.cant_have_volumes = function (id) { return !egCore.org.CanHaveVolumes(id); };

    // redirect the user to the login page using the current
    // workstation as the workstation URL param
    $scope.useWS = function() {
        $window.location.href = $location
            .path('/login')
            .search({ws : $scope.selectedWS})
            .absUrl();
    }

    $scope.registerWS = function() {
        register_workstation(
            $scope.newWSName,
            $scope.contextOrg.shortname() + '-' + $scope.newWSName,
            $scope.contextOrg.id()
        );
    }

    function register_workstation(base_name, name, org_id, override) {

        var method = 'open-ils.actor.workstation.register';
        if (override) method += '.override';

        egCore.net.request(
            'open-ils.actor', method, egCore.auth.token(), name, org_id)

        .then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                console.log('register returned ' + evt.toString());

                if (evt.textcode == 'WORKSTATION_NAME_EXISTS' && !override) {
                    egConfirmDialog.open(
                        egCore.strings.WS_EXISTS, base_name, {  
                            ok : function() {
                                register_workstation(base_name, name, org_id, true);
                            },
                            cancel : function() {} 
                        }
                    );

                } else {
                    // TODO: provide permission error display
                    alert(evt.toString());
                }
            } else if (resp) {
                $scope.workstations.push(name);

                allWorkstations.push({   
                    id : resp,
                    name : name,
                    owning_lib : org_id
                });

                egCore.hatch.setItem(
                    'eg.workstation.all', allWorkstations)
                .then(function() {
                    if (allWorkstations.length == 1) {
                        // first one registerd, also mark it as the default
                        $scope.selectedWS = name;
                        $scope.setDefaultWS();
                    }
                });
            }
        });
    }

    $scope.wsOrgChanged = function(org) {
        $scope.contextOrg = org;
    }

    // ---------------------
    // Hatch Configs
    $scope.hatchURL = egCore.hatch.hatchURL();
    $scope.hatchRequired = 
        egCore.hatch.getLocalItem('eg.hatch.required');

    $scope.updateHatchRequired = function() {
        egCore.hatch.setLocalItem(
            'eg.hatch.required', $scope.hatchRequired);
    }

    $scope.updateHatchURL = function() {
        egCore.hatch.setLocalItem(
            'eg.hatch.url', $scope.hatchURL);
    }
}])

.controller('PrintConfigCtrl',
       ['$scope','egCore',
function($scope , egCore) {
    console.log('PrintConfigCtrl');

    $scope.actionPending = false;
    $scope.isTestView = false;

    $scope.setContext = function(ctx) { 
        $scope.context = ctx; 
        $scope.isTestView = false;
        $scope.actionPending = false;
    }
    $scope.setContext('default');

    $scope.getPrinterByAttr = function(attr, value) {
        var printer;
        angular.forEach($scope.printers, function(p) {
            if (p[attr] == value) printer = p;
        });
        return printer;
    }

    $scope.currentPrinter = function() {
        if ($scope.printConfig && $scope.printConfig[$scope.context]) {
            return $scope.getPrinterByAttr(
                'name', $scope.printConfig[$scope.context].printer
            );
        }
    }

    // fetch info on all remote printers
    egCore.hatch.getPrinters()
    .then(function(printers) { 
        $scope.printers = printers;
        $scope.defaultPrinter = 
            $scope.getPrinterByAttr('is-default', true);
    })
    .then(function() { return egCore.hatch.getPrintConfig() })
    .then(function(config) {
        $scope.printConfig = config;

        var pname = '';
        if ($scope.defaultPrinter) {
            pname = $scope.defaultPrinter.name;

        } else if ($scope.printers.length == 1) {
            // if the OS does not report a default printer, but only
            // one printer is available, treat it as the default.
            pname = $scope.printers[0].name;
        }

        // apply the default printer to every context which has
        // no printer configured.
        angular.forEach(
            ['default','receipt','label','mail','offline'],
            function(ctx) {
                if (!$scope.printConfig[ctx]) {
                    $scope.printConfig[ctx] = {
                        context : ctx,
                        printer : pname
                    }
                }
            }
        );
    });

    $scope.printerConfString = function() {
        if ($scope.printConfigError) return $scope.printConfigError;
        if (!$scope.printConfig) return;
        if (!$scope.printConfig[$scope.context]) return;
        return JSON.stringify(
            $scope.printConfig[$scope.context], undefined, 2);
    }

    $scope.resetConfig = function() {
        $scope.actionPending = true;
        $scope.printConfigError = null;
        $scope.printConfig[$scope.context] = {
            context : $scope.context
        }
        
        if ($scope.defaultPrinter) {
            $scope.printConfig[$scope.context].printer = 
                $scope.defaultPrinter.name;
        }

        egCore.hatch.setPrintConfig($scope.printConfig)
        .finally(function() {$scope.actionPending = false});
    }

    $scope.configurePrinter = function() {
        $scope.printConfigError = null;
        $scope.actionPending = true;
        egCore.hatch.configurePrinter(
            $scope.context,
            $scope.printConfig[$scope.context].printer
        )
        .then(
            function(config) {$scope.printConfig = config},
            function(error) {$scope.printConfigError = error}
        )
        .finally(function() {$scope.actionPending = false});
    }

    $scope.setPrinter = function(name) {
        $scope.printConfig[$scope.context].printer = name;
    }

    // for testing
    $scope.setContentType = function(type) { $scope.contentType = type }

    $scope.testPrint = function(withDialog) {
        if ($scope.contentType == 'text/plain') {
            egCore.print.print({
                context : $scope.context, 
                content_type : $scope.contentType, 
                content : $scope.textPrintContent,
                show_dialog : withDialog
            });
        } else {
            egCore.print.print({
                context : $scope.context,
                content_type : $scope.contentType, 
                content : $scope.htmlPrintContent, 
                scope : {
                    value1 : 'Value One', 
                    value2 : 'Value Two',
                    date_value : '2015-02-04T14:04:34-0400'
                },
                show_dialog : withDialog
            });
        }
    }

    $scope.setContentType('text/plain');

}])

.controller('PrintTemplatesCtrl',
       ['$scope','$q','egCore',
function($scope , $q , egCore) {

    $scope.print = {
        template_name : 'bills_current',
        template_output : ''
    };

    // print preview scope data
    // TODO: consider moving the template-specific bits directly
    // into the templates or storing template- specific script files
    // alongside the templates.
    // NOTE: A lot of this data can be shared across templates.
    var seed_user = {
        first_given_name : 'Slow',
        second_given_name : 'Joe',
        family_name : 'Jones',
        card : {
            barcode : '30393830393'
        }
    }
    var seed_addr = {
        street1 : '123 Apple Rd',
        street2 : 'Suite B',
        city : 'Anywhere',
        state : 'XX',
        country : 'US',
        post_code : '12345'
    }

    var seed_record = {
        title : 'Traveling Pants!!',
        author : 'Jane Jones',
        isbn : '1231312123'
    };

    var seed_copy = {
        barcode : '33434322323'
    }

    var one_hold = {
        behind_desk : 'f',
        phone_notify : '111-222-3333',
        sms_notify : '111-222-3333',
        email_notify : 'user@example.org',
        request_time : new Date().toISOString()
    }


    $scope.preview_scope = {
        //bills
        transactions : [
            {
                id : 1,
                xact_start : new Date().toISOString(),
                summary : {
                    xact_type : 'circulation',
                    last_billing_type : 'Overdue materials',
                    total_owed : 1.50,
                    last_payment_note : 'Test Note 1',
                    total_paid : 0.50,
                    balance_owed : 1.00
                }
            }, {
                id : 2,
                xact_start : new Date().toISOString(),
                summary : {
                    xact_type : 'circulation',
                    last_billing_type : 'Overdue materials',
                    total_owed : 2.50,
                    last_payment_note : 'Test Note 2',
                    total_paid : 0.50,
                    balance_owed : 2.00
                }
            }
        ],

        circulations : [
            {   
                due_date : new Date().toISOString(), 
                target_copy : seed_copy,
                title : seed_record.title
            },
        ],

        previous_balance : 8.45,
        payment_total : 2.00,
        payment_applied : 2.00,
        new_balance : 6.45,
        amount_voided : 0,
        change_given : 0,
        payment_type : 'cash_payment',
        payment_note : 'Here is a payment note',
        note : {
            create_date : new Date().toISOString(), 
            title : 'Test Note Title',
            usr : seed_user,
            value : 'This patron is super nice!'
        },

        transit : {
            dest : {
                name : 'Library X',
                shortname : 'LX',
                holds_address : seed_addr
            },
            target_copy : seed_copy
        },
        title : seed_record.title,
        author : seed_record.author,
        patron : egCore.idl.toHash(egCore.auth.user()),
        address : seed_addr,
        hold : one_hold,
        holds : [
            {hold : one_hold, title : 'Some Title 1', author : 'Some Author 1'},
            {hold : one_hold, title : 'Some Title 2', author : 'Some Author 2'},
            {hold : one_hold, title : 'Some Title 3', author : 'Some Author 3'}
        ]
    }

    $scope.preview_scope.payments = [
        {amount : 1.00, xact : $scope.preview_scope.transactions[0]}, 
        {amount : 1.00, xact : $scope.preview_scope.transactions[1]}
    ]
    $scope.preview_scope.payments[0].xact.title = 'Hali Bote Azikaban de tao fan';
    $scope.preview_scope.payments[0].xact.copy_barcode = '334343434';
    $scope.preview_scope.payments[1].xact.title = seed_record.title;
    $scope.preview_scope.payments[1].xact.copy_barcode = seed_copy.barcode;

    // today, staff, current_location, etc.
    egCore.print.fleshPrintScope($scope.preview_scope);

    $scope.template_changed = function() {
        $scope.print.load_failed = false;
        egCore.print.getPrintTemplate($scope.print.template_name)
        .then(
            function(html) { 
                $scope.print.template_content = html;
                console.log('set template content');
            },
            function() {
                $scope.print.template_content = '';
                $scope.print.load_failed = true;
            }
        );
    }

    $scope.save_locally = function() {
        egCore.print.storePrintTemplate(
            $scope.print.template_name,
            $scope.print.template_content
        );
    }

    $scope.template_changed(); // load the default
}])

// 
.directive('egPrintTemplateOutput', ['$compile',function($compile) {
    return function(scope, element, attrs) {
        scope.$watch(
            function(scope) {
                return scope.$eval(attrs.content);
            },
            function(value) {
                // create an isolate scope and copy the print context
                // data into the new scope.
                // TODO: see also print security concerns in egHatch
                var result = element.html(value);
                var context = scope.$eval(attrs.context);
                var print_scope = scope.$new(true);
                angular.forEach(context, function(val, key) {
                    print_scope[key] = val;
                })
                $compile(element.contents())(print_scope);
            }
        );
    };
}])

.controller('StoredPrefsCtrl',
       ['$scope','$q','egCore','egConfirmDialog',
function($scope , $q , egCore , egConfirmDialog) {
    console.log('StoredPrefsCtrl');

    $scope.setContext = function(ctx) {
        $scope.context = ctx;
    }
    $scope.setContext('local');

    // grab the edit perm
    $scope.userHasDeletePerm = false;
    egCore.perm.hasPermHere('ADMIN_WORKSTATION')
    .then(function(bool) { $scope.userHasDeletePerm = bool });

    // fetch the keys

    function refreshKeys() {
        $scope.keys = {local : [], remote : []};

        egCore.hatch.getRemoteKeys().then(
            function(keys) { $scope.keys.remote = keys.sort() })
    
        // local calls are non-async
        $scope.keys.local = egCore.hatch.getLocalKeys();
    }
    refreshKeys();

    $scope.selectKey = function(key) {
        $scope.currentKey = key;
        $scope.currentKeyContent = null;

        if ($scope.context == 'local') {
            $scope.currentKeyContent = egCore.hatch.getLocalItem(key);
        } else {
            egCore.hatch.getRemoteItem(key)
            .then(function(content) {
                $scope.currentKeyContent = content
            });
        }
    }

    $scope.getCurrentKeyContent = function() {
        return JSON.stringify($scope.currentKeyContent, null, 2);
    }

    $scope.removeKey = function(key) {
        egConfirmDialog.open(
            egCore.strings.PREFS_REMOVE_KEY_CONFIRM, '',
            {   deleteKey : key,
                ok : function() {
                    if ($scope.context == 'local') {
                        egCore.hatch.removeLocalItem(key);
                        refreshKeys();
                    } else {
                        egCore.hatch.removeItem(key)
                        .then(function() { refreshKeys() });
                    }
                },
                cancel : function() {} // user canceled, nothing to do
            }
        );
    }
}])
