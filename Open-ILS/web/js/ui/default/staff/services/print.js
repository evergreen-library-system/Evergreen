/**
 * egPrint : manage print templates, process templates, print content
 *
 */
angular.module('egCoreMod')

.factory('egPrint',
       ['$q','$window','$timeout','$http','egHatch','egAuth','egIDL','egOrg','egEnv',
function($q , $window , $timeout , $http , egHatch , egAuth , egIDL , egOrg , egEnv) {

    var service = {
        include_settings : [
            'circ.staff_client.receipt.alert_text',
            'circ.staff_client.receipt.event_text',
            'circ.staff_client.receipt.footer_text',
            'circ.staff_client.receipt.header_text',
            'circ.staff_client.receipt.notice_text',
            'lib.info_url',
            'lib.my_account_url'
        ]
    };

    service.template_base_path = 'share/print_templates/t_';

    /*
     * context  : 'default', 'receipt','label', etc. 
     * scope    : data loaded into the template environment
     * template : template name (e.g. 'checkout', 'transit_slip'
     * content  : content to print.  If 'template' is set, content is
     *            derived from the template.
     * content_type : 'text/html', 'text/plain', 'text/csv'
     * show_dialog  : boolean, if true, print dialog is shown.  This setting
     *                only affects remote printers, since browser printers
     *                do not allow such control
     */
    service.print = function(args) {
        if (!args) return $q.when();

        if (args.template) {
            // fetch the template, then proceed to printing

            return service.getPrintTemplate(args.template)
            .then(function(content) {
                args.content = content;
                if (!args.content_type) args.content_type = 'text/html';
                service.getPrintTemplateContext(args.template)
                .then(function(context) {
                    args.context = context;
                    return service.print_content(args);
                });
            });

        } 

        return service.print_content(args);
    }

    // add commonly used attributes to the print scope
    service.fleshPrintScope = function(scope) {
        if (!scope) scope = {};
        scope.today = new Date().toISOString();

        if (!lf.isOffline) {
            scope.staff = egIDL.toHash(egAuth.user());
            scope.current_location = 
                egIDL.toHash(egOrg.get(egAuth.user().ws_ou()));
        }

        return service.fetch_includes(scope);
    }

    // Retrieve org settings for receipt includes and add them
    // to the print scope under scope.includes.<name>
    service.fetch_includes = function(scope) {
        // org settings for the workstation org are cached
        // within egOrg.  No need to cache them locally.
        return egOrg.settings(service.include_settings).then(

            function(settings) {
                scope.includes = {};
                angular.forEach(settings, function(val, key) {
                    // strip the settings prefix so you just have
                    // e.g. scope.includes.alert_text
                    scope.includes[key.split(/\./).pop()] = val;
                });
            }
        );
    }

    service.last_print = {};

    // Template has been fetched (or no template needed) 
    // Process the template and send the result off to the printer.
    service.print_content = function(args) {

        if (args.context === 'no-print') {
            console.debug('Skipping print request with No-Print context');
            return $q.when();
        }

        return service.fleshPrintScope(args.scope)
        .then(function() { return egHatch.usePrinting(); })
        .then(function(useHatch) {
            if (!useHatch) { return false; }
            return egHatch.getPrintConfig(args.context || 'default') 
            .then(function(config) {
                // Avoid using Hatch if the print context calls
                // for native browser printing.
                return config.printer != 'hatch_browser_printing';
            });
        })
        .then(function(useHatch) {
            var promise = useHatch ?
                service.print_via_hatch(args) :
                service.print_via_browser(args);

            return promise['finally'](
                function() { service.clear_print_content() });
        });
    }

    service.print_via_hatch = function(args) {
        var promise;

        if (args.content_type == 'text/html') {
            promise = service.ingest_print_content(
                args.content_type, args.content, args.scope
            ).then(function(html) {
                // For good measure, wrap the compiled HTML in container tags.
                return "<html><body>" + html + "</body></html>";
            });
        } else {
            // text content requires no compilation for remote printing.
            promise = $q.when(args.content);
        }

        return promise.then(function(content) {
            service.last_print.content = content;
            service.last_print.context = args.context || 'default';
            service.last_print.content_type = args.content_type;
            service.last_print.show_dialog = args.show_dialog;

            egHatch.setLocalItem('eg.print.last_printed', service.last_print);

            return service._remotePrint();
        });
    }

    service._remotePrint = function () {
        return egHatch.remotePrint(
            service.last_print.context,
            service.last_print.content_type,
            service.last_print.content, 
            service.last_print.show_dialog
        );
    }

    service.print_via_browser = function(args) {
        var type = args.content_type;
        var content = args.content;
        var printScope = args.scope;

        if (type == 'text/csv' || type == 'text/plain') {
            // preserve newlines, spaces, etc.
            content = '<pre>' + content + '</pre>';
        }

        // Fetch the print CSS required for in-browser printing.
        return $http.get(egEnv.basePath + 'css/print.css')
        .then(function(response) {

            // Add the bare CSS to the content
            return '<style type="text/css" media="print">' +
                  response.data +
                  '</style>' +
                  content;

        }).then(function(content) {

            // Ingest the content into the page DOM.
            return service.ingest_print_content(type, content, printScope);

        }).then(function(html) { 

            // Note browser ignores print context
            service.last_print.content = html;
            service.last_print.content_type = type;
            egHatch.setLocalItem('eg.print.last_printed', service.last_print);

            $window.print();
        });
    }

    service.reprintLast = function () {
        var last = egHatch.getLocalItem('eg.print.last_printed');
        if (!last || !last.content) { return $q.reject(); }

        service.last_print = last;

        return egHatch.usePrinting().then(function(useHatch) {

            if (useHatch) {
                return service._remotePrint();
            } else {
                return service.ingest_print_content(
                    null, null, null, service.last_print.content)
                .then(function() { $window.print(); });
            }

        }).finally(function() { service.clear_print_content(); });
    }

    // loads an HTML print template by name from the server
    // If no template is available in local/hatch storage, 
    // fetch the template as an HTML file from the server.
    service.getPrintTemplate = function(name) {
        var deferred = $q.defer();

        egHatch.getItem('eg.print.template.' + name)
        .then(function(html) {

            if (html) {
                // we have a locally stored template
                deferred.resolve(html);
                return;
            }

            var path = service.template_base_path + name;
            console.debug('fetching template ' + path);

            $http.get(path).then(
                function(data) { deferred.resolve(data.data) },
                function() {
                    console.error('unable to locate print template: ' + name);
                    deferred.reject();
                }
            );
        });

        return deferred.promise;
    }

    service.storePrintTemplate = function(name, html) {
        return egHatch.setItem('eg.print.template.' + name, html);
    }

    service.removePrintTemplate = function(name) {
        return egHatch.removeItem('eg.print.template.' + name);
    }

    service.getPrintTemplateContext = function(name) {
        var deferred = $q.defer();

        egHatch.getItem('eg.print.template_context.' + name)
        .then(
            function(context) { deferred.resolve(context); },
            function()        { deferred.resolve('default'); }
        );

        return deferred.promise;
    }
    service.storePrintTemplateContext = function(name, context) {
        return egHatch.setItem('eg.print.template_context.' + name, context);
    }
    service.removePrintTemplateContext = function(name) {
        return egHatch.removeItem('eg.print.template_context.' + name);
    }

    return service;
}])


/**
 * Container for inserting print data into the browser page.
 * On insert, $window.print() is called to print the data.
 * The div housing eg-print-container must apply the correct
 * print media CSS to ensure this content (and not the rest
 * of the page) is printed.
 *
 * NOTE: There should only ever be 1 egPrintContainer instance per page.
 * egPrintContainer attaches functions to the egPrint service with
 * closures around the egPrintContainer instance's $scope (including its
 * DOM element). Having multiple egPrintContainers could result in chaos.
 */

.directive('egPrintContainer', ['$compile', function($compile) {
    return {
        restrict : 'AE',
        scope : {}, // isolate our scope
        link : function(scope, element, attrs) {
            scope.elm = element;
        },
        controller : 
                   ['$scope','$q','$window','$timeout','egHatch','egPrint','egEnv', 'ngToast',
            function($scope , $q , $window , $timeout , egHatch , egPrint , egEnv, ngToast) {

                egPrint.clear_print_content = function() {
                    $scope.elm.html('');
                    $compile($scope.elm.contents())($scope.$new(true));
                }

                // Insert the printable content into the DOM.
                // For remote printing, this lets us exract the compiled HTML
                // from the DOM.
                // For local printing, this lets us print directly from the
                // DOM with print CSS.
                // Returns a promise reolved with the compiled HTML as a string.
                //
                // If a pre-compiled HTML string is provided, it's inserted
                // as-is into the DOM for browser printing without any 
                // additional interpolation.  This is useful for reprinting,
                // previously compiled content.
                egPrint.ingest_print_content = 
                    function(type, content, printScope, compiledHtml) {

                    if (compiledHtml) {
                        $scope.elm.html(compiledHtml);
                        return $q.when(compiledHtml);
                    }
                        
                    $scope.elm.html(content);

                    var sub_scope = $scope.$new(true);
                    angular.forEach(printScope, function(val, key) {
                        sub_scope[key] = val;
                    })

                    var resp = $compile($scope.elm.contents())(sub_scope);


                    var deferred = $q.defer();
                    var imgPromises = [];

                    // First we wait for the $digest complete
                    $timeout(function(){

                        // We can't resolve yet because images that load after being compiled may not be loaded
                        // So we find everything that is going to be printed
                        var printedNodes = document.querySelectorAll("#print-div *");      
                        angular.forEach(printedNodes, function(node){
                            // Keep track of all the images that haven't been loaded yet
                            if (node.nodeName && node.nodeName == "IMG" && !node.complete){
                                // And whether each image is done loading
                                var imgPromise = $q.defer();
                                imgPromises.push(imgPromise.promise);
                                node.onload = (function() {
                                    imgPromise.resolve();
                                });
                                node.onerror = function(event) {
                                    imgPromise.reject("Error loading image in print template");
                                }
                            }
                        });

                        var imageLoadingDeadline = $q.defer();
                        var timeoutDuration = 5000;
                        $timeout(function(){
                            imageLoadingDeadline.reject("Image in print template failed to load within " + (timeoutDuration / 1000) + " second(s).")
                        }, timeoutDuration);

                        // And once all of them are finished loading,
                        // resolve with the compiled HTML from our print container
                        $q.race([$q.all(imgPromises), imageLoadingDeadline.promise]).catch(function (error) {
                            deferred.resolve($scope.elm.html());
                            ngToast.danger(error);
                        }).then(function(){
                            deferred.resolve($scope.elm.html());
                        });
                        

                    });

                    return deferred.promise;
                }
            }
        ]
    }
}])

