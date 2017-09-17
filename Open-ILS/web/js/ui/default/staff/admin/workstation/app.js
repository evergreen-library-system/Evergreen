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

    $routeProvider.when('/admin/workstation/workstations', {
        templateUrl: './admin/workstation/t_workstations',
        controller: 'WSRegCtrl',
        resolve : resolver
    });

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

    $routeProvider.when('/admin/workstation/hatch', {
        templateUrl: './admin/workstation/t_hatch',
        controller: 'HatchCtrl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/workstation/t_splash',
        controller : 'SplashCtrl',
        resolve : resolver
    });
}])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.factory('workstationSvc',
       ['$q','$timeout','$location','egCore','egConfirmDialog',
function($q , $timeout , $location , egCore , egConfirmDialog) {
    
    var service = {};

    service.get_all = function() {
        return egCore.hatch.getItem('eg.workstation.all')
        .then(function(all) { return all || [] });
    }

    service.get_default = function() {
        return egCore.hatch.getItem('eg.workstation.default');
    }

    service.set_default = function(name) {
        return egCore.hatch.setItem('eg.workstation.default', name);
    }

    service.register_workstation = function(base_name, name, org_id) {
        return service.register_ws_api(base_name, name, org_id)
        .then(function(ws_id) {
            return service.track_new_ws(ws_id, name, org_id);
        });
    };

    service.register_ws_api = 
        function(base_name, name, org_id, override, deferred) {
        if (!deferred) deferred = $q.defer();

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
                                service.register_ws_api(
                                    base_name, name, org_id, true, deferred)
                            },
                            cancel : function() {
                                deferred.reject();
                            }
                        }
                    );

                } else {
                    alert(evt.toString());
                    deferred.reject();
                }
            } else if (resp) {
                console.log('Resolving register promise with: ' + resp);
                deferred.resolve(resp);
            }
        });

        return deferred.promise;
    }

    service.track_new_ws = function(ws_id, ws_name, owning_lib) {
        console.log('Tracking newly created WS with ID ' + ws_id);
        var new_ws = {id : ws_id, name : ws_name, owning_lib : owning_lib};

        return service.get_all()
        .then(function(all) {
            all.push(new_ws);
            return egCore.hatch.setItem('eg.workstation.all', all)
            .then(function() { return new_ws });
        });
    }

    // Remove all traces of the workstation locally.
    // This does not remove the WS from the server.
    service.remove_workstation = function(name) {
        console.debug('Removing workstation: ' + name);

        return egCore.hatch.getItem('eg.workstation.all')

        // remove from list of all workstations
        .then(function(all) {
            if (!all) all = [];
            var keep = all.filter(function(ws) {return ws.name != name});
            return egCore.hatch.setItem('eg.workstation.all', keep)

        }).then(function() { 

            return service.get_default()

        }).then(function(def) {
            if (def == name) {
                console.debug('Removing default workstation: ' + name);
                return egCore.hatch.removeItem('eg.workstation.default');
            }
        });
    }

    return service;
}])


.controller('SplashCtrl',
       ['$scope','$window','$location','egCore','egConfirmDialog',
function($scope , $window , $location , egCore , egConfirmDialog) {

    egCore.hatch.getItem('eg.audio.disable').then(function(val) {
        $scope.disable_sound = val;
    });

    egCore.hatch.getItem('eg.search.search_lib').then(function(val) {
        $scope.search_lib = egCore.org.get(val);
    });
    $scope.handle_search_lib_changed = function(org) {
        egCore.hatch.setItem('eg.search.search_lib', org.id());
    };

    egCore.hatch.getItem('eg.search.pref_lib').then(function(val) {
        $scope.pref_lib = egCore.org.get(val);
    });
    $scope.handle_pref_lib_changed = function(org) {
        egCore.hatch.setItem('eg.search.pref_lib', org.id());
    };

    $scope.adv_pane = 'advanced'; // default value if not explicitly set
    egCore.hatch.getItem('eg.search.adv_pane').then(function(val) {
        $scope.adv_pane = val;
    });
    $scope.$watch('adv_pane', function(newVal, oldVal) {
        if (typeof newVal != 'undefined' && newVal != oldVal) {
            egCore.hatch.setItem('eg.search.adv_pane', newVal);
        }
    });

    $scope.apply_sound = function() {
        if ($scope.disable_sound) {
            egCore.hatch.setItem('eg.audio.disable', true);
        } else {
            egCore.hatch.removeItem('eg.audio.disable');
        }
    }

    $scope.test_audio = function(sound) {
        egCore.audio.play(sound);
    }

}])

.controller('PrintConfigCtrl',
       ['$scope','egCore',
function($scope , egCore) {

    $scope.printConfig = {};
    $scope.setContext = function(ctx) { 
        $scope.context = ctx; 
        $scope.isTestView = false;
    }
    $scope.setContext('default');

    $scope.setContentType = function(type) { $scope.contentType = type }
    $scope.setContentType('text/plain');

    $scope.useHatchPrinting = function() {
        return egCore.hatch.usePrinting();
    }

    $scope.hatchIsOpen = function() {
        return egCore.hatch.hatchAvailable;
    }

    $scope.getPrinterByAttr = function(attr, value) {
        var printer;
        angular.forEach($scope.printers, function(p) {
            if (p[attr] == value) printer = p;
        });
        return printer;
    }

    $scope.resetPrinterSettings = function(context) {
        $scope.printConfig[context] = {
            context : context,
            printer : $scope.defaultPrinter ? $scope.defaultPrinter.name : null,
            autoMargins : true, 
            allPages : true,
            pageRanges : []
        };
    }

    $scope.savePrinterSettings = function(context) {
        return egCore.hatch.setPrintConfig(
            context, $scope.printConfig[context]);
    }

    $scope.printerConfString = function() {
        if ($scope.printConfigError) return $scope.printConfigError;
        if (!$scope.printConfig) return;
        if (!$scope.printConfig[$scope.context]) return;
        return JSON.stringify(
            $scope.printConfig[$scope.context], undefined, 2);
    }

    function loadPrinterOptions(name) {
        egCore.hatch.getPrinterOptions(name).then(
            function(options) {$scope.printerOptions = options});
    }

    $scope.setPrinter = function(name) {
        $scope.printConfig[$scope.context].printer = name;
        loadPrinterOptions(name);
    }

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

    // Load startup data....
    // Don't bother talking to Hatch if it's not there.
    if (!egCore.hatch.hatchAvailable) return;

    // fetch info on all remote printers
    egCore.hatch.getPrinters()
    .then(function(printers) { 
        $scope.printers = printers;

        var def = $scope.getPrinterByAttr('is-default', true);
        if (!def && printers.length) def = printers[0];

        if (def) {
            $scope.defaultPrinter = def;
            loadPrinterOptions(def.name);
        }
    }).then(function() {
        angular.forEach(
            ['default','receipt','label','mail','offline'],
            function(ctx) {
                egCore.hatch.getPrintConfig(ctx).then(function(conf) {
                    if (conf) {
                        $scope.printConfig[ctx] = conf;
                    } else {
                        $scope.resetPrinterSettings(ctx);
                    }
                });
            }
        );
    });

}])

.controller('PrintTemplatesCtrl',
       ['$scope','$q','egCore','ngToast',
function($scope , $q , egCore , ngToast) {

    $scope.print = {
        template_name : 'bills_current',
        template_output : '',
        template_context : 'default'
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
        barcode : '33434322323',
        call_number : {
            label : '636.8 JON',
            record : {
                simple_record : {
                    'title' : 'Test Title'
                }
            }
        },
        location : {
            name : 'General Collection'
        },
        // flattened versions for item status template
        // TODO - make this go away
        'call_number.label' : '636.8 JON',
        'call_number.record.simple_record.title' : 'Test Title',
        'location.name' : 'General Colleciton'
    }

    var one_hold = {
        behind_desk : 'f',
        phone_notify : '111-222-3333',
        sms_notify : '111-222-3333',
        email_notify : 'user@example.org',
        request_time : new Date().toISOString(),
        hold_type : 'T'
    }

    var seed_transit = {
        source : {
            name : 'Library Y',
            shortname : 'LY',
            holds_address : seed_addr
        },
        dest : {
            name : 'Library X',
            shortname : 'LX',
            holds_address : seed_addr
        },
        source_send_time : new Date().toISOString(),
        target_copy : seed_copy
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
                    last_payment_type : 'cash_payment',
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
                    last_payment_type : 'credit_payment',
                    total_paid : 0.50,
                    balance_owed : 2.00
                }
            }
        ],

        copy : seed_copy,
        copies : [ seed_copy ],

        checkins : [
            {
                due_date : new Date().toISOString(),
                circ_lib : 1,
                duration : '7 days',
                target_copy : seed_copy,
                copy_barcode : seed_copy.barcode,
                call_number : seed_copy.call_number,
                title : seed_record.title
            },
        ],

        circulations : [
            {
                circ : {
                    due_date : new Date().toISOString(),
                    circ_lib : 1,
                    duration : '7 days'
                },
                copy : seed_copy,
                title : seed_record.title,
                author : seed_record.author
            },
        ],

        in_house_uses : [
            {
                num_uses : 3,
                copy : seed_copy,
                title : seed_record.title
            }
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

        transit : seed_transit,
        transits : [ seed_transit ],
        title : seed_record.title,
        author : seed_record.author,
        patron : seed_user,
        address : seed_addr,
        dest_location : egCore.idl.toHash(egCore.org.get(egCore.auth.user().ws_ou())),
        dest_address : seed_addr,
        hold : one_hold,
        holds : [
            {
                hold : one_hold, title : 'Some Title 1', author : 'Some Author 1',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane'
            },
            {
                hold : one_hold, title : 'Some Title 2', author : 'Some Author 2',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane'
            },
            {
                hold : one_hold, title : 'Some Title 3', author : 'Some Author 3',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane'
            }
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
        egCore.print.getPrintTemplateContext($scope.print.template_name)
        .then(function(template_context) {
            $scope.print.template_context = template_context;
        });
    }

    $scope.reset_to_default = function() {
        egCore.print.removePrintTemplate(
            $scope.print.template_name
        );
        egCore.print.removePrintTemplateContext(
            $scope.print.template_name
        );
        $scope.template_changed();
    }

    $scope.save_locally = function() {
        egCore.print.storePrintTemplate(
            $scope.print.template_name,
            $scope.print.template_content
        );
        egCore.print.storePrintTemplateContext(
            $scope.print.template_name,
            $scope.print.template_context
        );
    }

    $scope.exportable_templates = function() {
        var templates = {};
        var contexts = {};
        var deferred = $q.defer();
        var promises = [];
        egCore.hatch.getKeys('eg.print.template').then(function(keys) {
            angular.forEach(keys, function(key) {
                if (key.match(/^eg\.print\.template\./)) {
                    promises.push(egCore.hatch.getItem(key).then(function(value) {
                        templates[key.replace('eg.print.template.', '')] = value;
                    }));
                } else {
                    promises.push(egCore.hatch.getItem(key).then(function(value) {
                        contexts[key.replace('eg.print.template_context.', '')] = value;
                    }));
                }
            });
            $q.all(promises).then(function() {
                if (Object.keys(templates).length) {
                    deferred.resolve({
                        templates: templates,
                        contexts: contexts
                    });
                } else {
                    ngToast.warning(egCore.strings.PRINT_TEMPLATES_FAIL_EXPORT);
                    deferred.reject();
                }
            });
        });
        return deferred.promise;
    }

    $scope.imported_print_templates = { data : '' };
    $scope.$watch('imported_print_templates.data', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            try {
                var data = JSON.parse(newVal);
                angular.forEach(data.templates, function(template_content, template_name) {
                    egCore.print.storePrintTemplate(template_name, template_content);
                });
                angular.forEach(data.contexts, function(template_context, template_name) {
                    egCore.print.storePrintTemplateContext(template_name, template_context);
                });
                $scope.template_changed(); // refresh
                ngToast.create(egCore.strings.PRINT_TEMPLATES_SUCCESS_IMPORT);
            } catch (E) {
                ngToast.warning(egCore.strings.PRINT_TEMPLATES_FAIL_IMPORT);
            }
        }
    });

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

        if (egCore.hatch.hatchAvailable) {
            egCore.hatch.getRemoteKeys().then(
                function(keys) { $scope.keys.remote = keys.sort() })
        }
    
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

.controller('WSRegCtrl',
       ['$scope','$q','$window','$location','egCore','egAlertDialog','workstationSvc',
function($scope , $q , $window , $location , egCore , egAlertDialog , workstationSvc) {

    var all_workstations = [];
    var reg_perm_orgs = [];

    $scope.page_loaded = false;
    $scope.contextOrg = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.wsOrgChanged = function(org) { $scope.contextOrg = org; }

    console.log('set context org to ' + $scope.contextOrg);

    // fetch workstation reg perms
    egCore.perm.hasPermAt('REGISTER_WORKSTATION', true)
    .then(function(orgList) { 
        reg_perm_orgs = orgList;

        // hide orgs in the context org selector where this login
        // does not have the reg_ws perm or the org can't have users
        $scope.wsOrgHidden = function(id) {
            return reg_perm_orgs.indexOf(id) == -1
                || $scope.cant_have_users(id);
        }

    // fetch the locally stored workstation data
    }).then(function() {
        return workstationSvc.get_all()
        
    }).then(function(all) {
        all_workstations = all || [];
        $scope.workstations = 
            all_workstations.map(function(w) { return w.name });
        return workstationSvc.get_default()

    // fetch the default workstation
    }).then(function(def) { 
        $scope.defaultWS = def;
        $scope.activeWS = $scope.selectedWS = egCore.auth.workstation() || def;

    // Handle any URL commands.
    }).then(function() {
        var remove = $location.search().remove;
         if (remove) {
            console.log('Removing WS via URL request: ' + remove);
            return $scope.remove_ws(remove).then(
                function() { $scope.page_loaded = true; });
        }
        $scope.page_loaded = true;
    });

    $scope.get_ws_label = function(ws) {
        return ws == $scope.defaultWS ? 
            egCore.strings.$replace(egCore.strings.DEFAULT_WS_LABEL, {ws:ws}) : ws;
    }

    $scope.set_default_ws = function(name) {
        delete $scope.removing_ws;
        $scope.defaultWS = name;
        workstationSvc.set_default(name);
    }

    $scope.cant_have_users = 
        function (id) { return !egCore.org.CanHaveUsers(id); };
    $scope.cant_have_volumes = 
        function (id) { return !egCore.org.CanHaveVolumes(id); };

    // Log out and return to login page with selected WS 
    $scope.use_now = function() {
        egCore.auth.logout();
        $window.location.href = $location
            .path('/login')
            .search({ws : $scope.selectedWS})
            .absUrl();
    }

    $scope.can_delete_ws = function(name) {
        var ws = all_workstations.filter(
            function(ws) { return ws.name == name })[0];
        return ws && reg_perm_orgs.indexOf(ws.owning_lib) != -1;
    }

    $scope.remove_ws = function(remove_me) {
        $scope.removing_ws = remove_me;

        // Perm is used to disable Remove button in UI, but have to check
        // again here in case we're removing a WS based on URL params.
        if (!$scope.can_delete_ws(remove_me)) return $q.when();

        $scope.is_removing = true;
        return workstationSvc.remove_workstation(remove_me)
        .then(function() {

            all_workstations = all_workstations.filter(
                function(ws) { return ws.name != remove_me });

            $scope.workstations = $scope.workstations.filter(
                function(ws) { return ws != remove_me });

            if ($scope.selectedWS == remove_me) 
                $scope.selectedWS = $scope.workstations[0];

            if ($scope.defaultWS == remove_me) 
                $scope.defaultWS = '';

            $scope.is_removing = false;
        });
    }

    $scope.register_ws = function() {
        delete $scope.removing_ws;

        var full_name = 
            $scope.contextOrg.shortname() + '-' + $scope.newWSName;

        if ($scope.workstations.indexOf(full_name) > -1) {
            // avoid duplicate local registrations
            return egAlertDialog.open(egCore.strings.WS_USED);
        }

        $scope.is_registering = true;
        workstationSvc.register_workstation(
            $scope.newWSName, full_name,
            $scope.contextOrg.id()

        ).then(function(new_ws) {
            $scope.workstations.push(new_ws.name);
            all_workstations.push(new_ws);  
            $scope.is_registering = false;

            if (!$scope.selectedWS) {
                $scope.selectedWS = new_ws.name;
            }
            if (!$scope.defaultWS) {
                return $scope.set_default_ws(new_ws.name);
            }
            $scope.newWSName = '';
        }, function(err) {
            $scope.is_registering = false;
        });
    }
}])

.controller('HatchCtrl',
       ['$scope','egCore','ngToast',
function($scope , egCore , ngToast) {
    var hatch = egCore.hatch;  // convenience

    $scope.hatch_available = hatch.hatchAvailable;
    $scope.hatch_printing = hatch.usePrinting();
    $scope.hatch_settings = hatch.useSettings();
    $scope.hatch_offline  = hatch.useOffline();

    // Apply Hatch settings as changes occur in the UI.
    
    $scope.$watch('hatch_printing', function(newval) {
        if (typeof newval != 'boolean') return;
        hatch.setLocalItem('eg.hatch.enable.printing', newval);
    });

    $scope.$watch('hatch_settings', function(newval) {
        if (typeof newval != 'boolean') return;
        hatch.setLocalItem('eg.hatch.enable.settings', newval);
    });

    $scope.$watch('hatch_offline', function(newval) {
        if (typeof newval != 'boolean') return;
        hatch.setLocalItem('eg.hatch.enable.offline', newval);
    });

    $scope.copy_to_hatch = function() {
        hatch.copySettingsToHatch().then(
            function() {
                ngToast.create(egCore.strings.HATCH_SETTINGS_MIGRATION_SUCCESS)},
            function() {
                ngToast.warning(egCore.strings.HATCH_SETTINGS_MIGRATION_FAILURE)}
        );
    }

    $scope.copy_to_local = function() {
        hatch.copySettingsToLocal().then(
            function() {
                ngToast.create(egCore.strings.HATCH_SETTINGS_MIGRATION_SUCCESS)},
            function() {
                ngToast.warning(egCore.strings.HATCH_SETTINGS_MIGRATION_FAILURE)}
        );
    }

}])


