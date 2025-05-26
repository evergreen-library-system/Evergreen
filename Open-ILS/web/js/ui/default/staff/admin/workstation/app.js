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
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
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

    $routeProvider.when('/admin/workstation/tests', {
        templateUrl: './admin/workstation/t_tests',
        controller: 'testsCtrl',
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
        return egCore.hatch.getWorkstations()
        .then(function(all) { return all || [] });
    }

    service.get_default = function() {
        return egCore.hatch.getDefaultWorkstation();
    }

    service.set_default = function(name) {
        return egCore.hatch.setDefaultWorkstation(name);
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
            return egCore.hatch.setWorkstations(all)
            .then(function() { return new_ws });
        });
    }

    // Remove all traces of the workstation locally.
    // This does not remove the WS from the server.
    service.remove_workstation = function(name) {
        console.debug('Removing workstation: ' + name);

        return egCore.hatch.getWorkstations()

        // remove from list of all workstations
        .then(function(all) {
            if (!all) all = [];
            var keep = all.filter(function(ws) {return ws.name != name});
            return egCore.hatch.setWorkstations(keep);

        }).then(function() { 

            return service.get_default()

        }).then(function(def) {
            if (def == name) {
                console.debug('Removing default workstation: ' + name);
                return egCore.hatch.removeDefaultWorkstation();
            }
        });
    }

    return service;
}])


.controller('SplashCtrl',
       ['$scope','$window','$location','egCore','egConfirmDialog', 'egLinkTargetService',
function($scope , $window , $location , egCore , egConfirmDialog, egLinkTargetService) {

    egCore.hatch.getItem('eg.audio.disable').then(function(val) {
        $scope.disable_sound = val;
    });

    egCore.hatch.getItem('eg.orgselect.show_combined_names').then(function(val) {
        $scope.orgselect_combo_names = val;
    });

    egCore.hatch.getItem('ui.staff.grid.density').then(function(val) {
        $scope.grid_density = val;
    });

    egLinkTargetService.newTabsDisabled().then(function(val) {
        $scope.disable_links_newtabs = val;
    });

    $scope.apply_sound = function() {
        if ($scope.disable_sound) {
            egCore.hatch.setItem('eg.audio.disable', true);
        } else {
            egCore.hatch.removeItem('eg.audio.disable');
        }
    }

    $scope.apply_orgselect_combob_names = function() {
        if ($scope.orgselect_combo_names) {
            egCore.hatch.setItem('eg.orgselect.show_combined_names', true);
        } else {
            egCore.hatch.removeItem('eg.orgselect.show_combined_names');
        }
    }

    $scope.apply_grid_density = function() {
        if ($scope.grid_density && ($scope.grid_density === 'compact' || $scope.grid_density === 'wide' )) {
            egCore.hatch.setItem('ui.staff.grid.density', $scope.grid_density);
        } else {
            egCore.hatch.removeItem('ui.staff.grid.density');
        }
        console.log("New density: ", $scope.grid_density);
    }

    $scope.apply_disable_links_newtabs = function() {
        if ($scope.disable_links_newtabs) {
            egLinkTargetService.disableNewTabs();
        } else {
            egLinkTargetService.enableNewTabs();
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

    var hatchPrinting = false;
    egCore.hatch.usePrinting().then(function(answer) {
        hatchPrinting = answer;
    });

    $scope.useHatchPrinting = function() {
        return hatchPrinting;
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
        if (name == 'hatch_file_writer' || name == 'hatch_browser_printing') {
            $scope.printerOptions = {};
        } else {
            egCore.hatch.getPrinterOptions(name).then(
                function(options) {$scope.printerOptions = options});
        }
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

    $scope.useFileWriter = function() {
        return (
            $scope.printConfig[$scope.context] &&
            $scope.printConfig[$scope.context].printer == 'hatch_file_writer'
        );
    }

    $scope.useBrowserPrinting = function() {
        return (
            $scope.printConfig[$scope.context] &&
            $scope.printConfig[$scope.context].printer == 'hatch_browser_printing'
        );
    }


    // Load startup data....
    // Don't bother talking to Hatch if it's not there.
    if (!egCore.hatch.hatchAvailable) return;

    // fetch info on all remote printers
    egCore.hatch.getPrinters()
    .then(function(printers) { 
        $scope.printers = printers;

        printers.push({
            // We need a static name for saving configs.
            // Human-friendly label is set in the template.
            name: 'hatch_file_writer' 
        });

        printers.push({name: 'hatch_browser_printing'});

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
        prefix : 'Mr',
        first_given_name : 'Joseph',
        second_given_name : 'Martin',
        family_name : 'Jones',
        suffix : 'III',
        pref_first_given_name : 'Martin',
        pref_second_given_name : 'Joe',
        pref_family_name : 'Smith',
        card : {
            barcode : '30393830393'
        },
        money_summary : {
            balance_owed : 4, // This is currently how these values are returned to the client
            total_billed : '5.00',
            total_paid : '1.00'
        },
        expire_date : '2020-12-31',
        alias : 'Joey J.',
        has_email : true,
        has_phone : false,
        dob : '1980-01-01T00:00:00-8:00',
        juvenile : 'f',
        usrname : '30393830393',
        day_phone : '111-222-3333',
        evening_phone : '222-333-1111',
        other_phone : '333-111-2222',
        email : 'user@example.com',
        home_ou : {name: function() {return 'BR1'}},
        profile : {name: function() {return 'Patrons'}},
        net_access_level : {name: function() {return 'Filtered'}},
        active : 't',
        barred : 'f',
        master_account : 'f',
        claims_returned_count : '0',
        claims_never_checked_out_count : '0',
        ident_type: {name: function() {return 'Drivers License'}},
        ident_value: '11332445',
        ident_type2: {name: function() {return 'Other'}},
        ident_value2 : '55442211',
        addresses : [],
        stat_cat_entries : [
            {
                stat_cat : {'name' : 'Favorite Donut'},
                'stat_cat_entry' : 'Maple'
            }, {
                stat_cat : {'name' : 'Favorite Book'},
                'stat_cat_entry' : 'Beasts Made of Night'
            }
        ],
        surveys : [
            {
                survey : {
                    'id' : function() {return '1'},
                    'description' : function() {return 'Voter Registration'},
                },
                responses : [
                    {
                        'answer_date' : function() {return '2020-12-31'},
                        question : function() {return {'question' : function() {return 'Would you like to register to vote today?'}}},
                        answer : function() {return {'answer' : function() {return 'Already registered'}}}
                    }
                ]
            }
        ]
    }

    var seed_addr = {
        address_type : 'MAILING',
        street1 : '123 Apple Rd',
        street2 : 'Suite B',
        city : 'Anywhere',
        county : 'Great County',
        state : 'XX',
        country : 'US',
        post_code : '12345',
        valid : 't',
        within_city_limits: 't'
    }

    seed_user.addresses.push(seed_addr);

    var seed_record = {
        title : 'Traveling Pants!!',
        author : 'Jane Jones',
        isbn : '1231312123'
    };

    var seed_copy = {
        barcode : '33434322323',
        status : {
            name : 'In transit'
            },
        call_number : {
            label : '636.8 JON',
            record : {
                simple_record : {
                    'title' : 'Test Title'
                }
            },
            owning_lib : {
                name : 'Ankers Memorial Library',
                shortname : 'Ankers'
            }
        },
        circ_modifier : {
		name : 'Book'
                },
        location : {
            name : 'General Collection'
        },
        status : {
            name : 'In Transit'
        },
        // flattened versions for item status template
        // TODO - make this go away
        'call_number.label' : '636.8 JON',
        'call_number.record.simple_record.title' : 'Test Title',
        'location.name' : 'General Collection',
        'call_number.owning_lib.name' : 'Ankers Memorial Library',
        'call_number.owning_lib.shortname' : 'Ankers',
        'location.name' : 'General Collection'
    }

    var one_hold = {
        behind_desk : 'f',
        phone_notify : '111-222-3333',
        sms_notify : '111-222-3333',
        email_notify : 'user@example.org',
        request_time : new Date().toISOString(),
        hold_type : 'T',
        shelf_expire_time : new Date().toISOString()
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
                xact_finish : new Date().toISOString(),
                call_number : {
                    label : "spindler",
                    prefix : "biography",
                    suffix : "Closed Stacks",
                    owning_lib : {
                        name : "Mineola Public Library",
                        shortname : "Mineola"
                    }
                },
                summary : {
                    xact_type : 'circulation',
                    last_billing_type : 'Overdue materials',
                    total_owed : 1.50,
                    last_payment_note : 'Test Note 1',
                    last_payment_type : 'cash_payment',
                    last_payment_ts : new Date().toISOString(),
                    total_paid : 0.50,
                    balance_owed : 1.00
                }
            }, {
                id : 2,
                xact_start : new Date().toISOString(),
                xact_finish : new Date().toISOString(),
		call_number : {
 			label : "796.6 WEI",
		        prefix : "",
		        suffix : "REF",
		        owning_lib : {
			   name : "Rogers Reading Room",
                           shortname : "Rogers"
                                     }
                               },
                summary : {
                    xact_type : 'circulation',
                    last_billing_type : 'Overdue materials',
                    total_owed : 2.50,
                    last_payment_note : 'Test Note 2',
                    last_payment_type : 'credit_payment',
                    last_payment_ts : new Date().toISOString(),
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
                    duration : '7 days',
                    renewal_remaining : 2
                },
                copy : seed_copy,
                title : seed_record.title,
                author : seed_record.author,
                call_number : seed_copy.call_number
            }
        ],

        patron_money : {
            balance_owed : 5.01,
            total_owed : 10.12,
            total_paid : 5.11
        },

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
        approval_code : 'CH1234567',
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
        dest_courier_code : 'ABC 123',
        dest_address : seed_addr,
        source_address : seed_addr,
		source_location : egCore.idl.toHash(egCore.org.get(egCore.auth.user().ws_ou())),
        hold : one_hold,
        holds : [
            {
                hold : one_hold, title : 'Some Title 1', author : 'Some Author 1',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane',
                status_string : 'Ready for Pickup'
            },
            {
                hold : one_hold, title : 'Some Title 2', author : 'Some Author 2',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane',
                status_string : 'Ready for Pickup'
            },
            {
                hold : one_hold, title : 'Some Title 3', author : 'Some Author 3',
                volume : { label : '646.4 SOM' }, copy : seed_copy,
                part : { label : 'v. 1' },
                patron_barcode : 'S52802662',
                patron_alias : 'XYZ', patron_last : 'Smith', patron_first : 'Jane',
                status_string : 'Canceled'
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
        $scope.keys = {local : [], remote : [], server_workstation: []};

        if (egCore.hatch.hatchAvailable) {
            egCore.hatch.getRemoteKeys().then(
                function(keys) { $scope.keys.remote = keys.sort() })
        }
    
        // local calls are non-async
        $scope.keys.local = egCore.hatch.getLocalKeys();

        egCore.hatch.getServerKeys(null, {workstation_only: true}).then(
            function(keys) {$scope.keys.server_workstation = keys});
    }
    refreshKeys();

    $scope.selectKey = function(key) {
        $scope.currentKey = key;
        $scope.currentKeyContent = null;

        if ($scope.context == 'local') {
            $scope.currentKeyContent = egCore.hatch.getLocalItem(key);
        } else if ($scope.context == 'remote') {
            egCore.hatch.getRemoteItem(key)
            .then(function(content) {
                $scope.currentKeyContent = content
            });
        } else if ($scope.context == 'server_workstation') {
            egCore.hatch.getServerItem(key).then(function(content) {
                $scope.currentKeyContent = content;
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
                    } else if ($scope.context == 'remote') {
                        // Honor requests to remove items from Hatch even
                        // when Hatch is configured for data storage.
                        egCore.hatch.removeRemoteItem(key)
                        .then(function() { refreshKeys() });
                    } else if ($scope.context == 'server_workstation') {
                        egCore.hatch.removeServerItem(key)
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

    egCore.hatch.hostname().then(function(name) {
        $scope.newWSName = name || '';
    });

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

/*
 * Home of the Latency tester
 * */
.controller('testsCtrl', ['$scope', '$location', 'egCore', function($scope, $location, egCore) {
    $scope.hostname = $location.host();

    $scope.tests = [];
    $scope.clearTestData = function(){
        $scope.tests = [];
        numPings = 0;
    }

    $scope.isTesting = false;
    $scope.avrg = 0; // avrg latency
    $scope.canCopyCommand = document.queryCommandSupported('copy');
    var numPings = 0;
    // initially fetch first 10 (gets a decent average)

    function calcAverage(){

        if ($scope.tests.length == 0) return 0;

        if ($scope.tests.length == 1) return $scope.tests[0].l;

        var sum = 0;
        angular.forEach($scope.tests, function(t){
            sum += t.l;
        });

        return sum / $scope.tests.length;
    }

    function ping(){
        $scope.isTesting = true;
        var t = Date.now();
        return egCore.net.request(
            "open-ils.pcrud", "opensrf.system.echo", "ping"
        ).then(function(resp){
            var t2 = Date.now();
            var latency = t2 - t;
            $scope.tests.push({t: new Date(t), l: latency});
            console.log("Start: " + t + " and end: " + t2);
            console.log("Latency: " + latency);
            console.log(resp);
        }).then(function(){
            $scope.avrg = calcAverage();
            numPings++;
            $scope.isTesting = false;
        });
    }

    $scope.testLatency = function(){

        if (numPings >= 10){
            ping(); // just ping once after the initial ten
        } else {
            ping()
                .then($scope.testLatency)
                .then(function(){
                    if (numPings == 9){
                        $scope.tests.shift(); // toss first result
                        $scope.avrg = calcAverage();
                    }
                });
        }
    }

    $scope.copyTests = function(){

        var lNode = document.querySelector('#pingData');
        var r = document.createRange();
        r.selectNode(lNode);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(r);
        document.execCommand('copy');
    }

}])


