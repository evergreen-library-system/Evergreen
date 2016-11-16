/**
 * egPrint : manage print templates, process templates, print content
 *
 */
angular.module('egCoreMod')

.factory('egPrint',
       ['$q','$window','$timeout','$http','egHatch','egAuth','egIDL','egOrg','egEnv',
function($q , $window , $timeout , $http , egHatch , egAuth , egIDL , egOrg , egEnv) {

    var service = {};

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
                if (!args.content_type) args.content_type = 'html';
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
        scope.staff = egIDL.toHash(egAuth.user());
        scope.current_location = 
            egIDL.toHash(egOrg.get(egAuth.user().ws_ou()));
    }

    // Template has been fetched (or no template needed) 
    // Process the template and send the result off to the printer.
    service.print_content = function(args) {
        service.fleshPrintScope(args.scope);

        var promise;
        if (args.content_type == 'text/html') {

            // all HTML content is assumed to require compilation, 
            // regardless of the print destination
            promise = service.ingest_print_content(
                args.content_type, args.content, args.scope);

        } else {
            // text content does not require compilation for remote printing
            promise = $q.when(args.content);
        }

        var context = args.context || 'default';

        return promise.then(function(html) {

            return egHatch.remotePrint(context,
                args.content_type, html, args.show_dialog)['catch'](

                function(msg) {
                    // remote print not available; 

                    if (egHatch.hatchRequired()) {
                        console.error("Unable to print data; "
                         + "hatchRequired=true, but hatch is not connected");
                         return $q.reject();
                    }

                    if (args.content_type != 'text/html') {
                        // text content does require compilation 
                        // (absorption) for browser printing
                        return service.ingest_print_content(
                            args.content_type, args.content, args.scope
                        ).then(function() { $window.print(); service.clear_print_content(); });
                    } else {
                        // HTML content is already ingested and accessible
                        // within the page to the printer.  
                        $window.print();
                        service.clear_print_content();
                    }
                }
            );
        });
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

            $http.get(path)
            .success(function(data) { deferred.resolve(data) })
            .error(function() {
                console.error('unable to locate print template: ' + name);
                deferred.reject();
            });
        });

        return deferred.promise;
    }

    service.storePrintTemplate = function(name, html) {
        return egHatch.setItem('eg.print.template.' + name, html);
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

    return service;
}])


/**
 * Container for inserting print data into the browser page.
 * On insert, $window.print() is called to print the data.
 * The div housing eg-print-container must apply the correct
 * print media CSS to ensure this content (and not the rest
 * of the page) is printed.
 */

// FIXME: only apply print CSS when print commands are issued via the 
// print container, otherwise using the browser's native print page 
// option will always result in empty pages.  Move the print CSS
// out of the standalone CSS file and put it into a template file
// for this directive.
.directive('egPrintContainer', ['$compile', '$http', function($compile, $http) {
    return {
        restrict : 'AE',
        scope : {}, // isolate our scope
        link : function(scope, element, attrs) {
            scope.elm = element;
        },
        controller : 
                   ['$scope','$q','$window','$timeout','egHatch','egPrint','egEnv',
            function($scope , $q , $window , $timeout , egHatch , egPrint , egEnv) {

                egPrint.clear_print_content = function() {
                    $scope.elm.html('');
                    $compile($scope.elm.contents())($scope.$new(true));
                }

                egPrint.ingest_print_content = function(type, content, printScope) {

                    if (type == 'text/csv' || type == 'text/plain') {
                        // preserve newlines, spaces, etc.
                        content = '<pre>' + content + '</pre>';
                    }

                    return $http.get(egEnv.basePath + 'css/print.css').then(
                        function(response) {
                            content = '<style type="text/css" media="print">' +
                                      response.data +
                                      '</style>' +
                                      content;
                            return finish_ingest_print_content(type, content, printScope);
                        },
                        function() {
                            return finish_ingest_print_content(type, content, printScope);
                        }
                    );

                }

                function finish_ingest_print_content(type, content, printScope) {
                    $scope.elm.html(content);

                    var sub_scope = $scope.$new(true);
                    angular.forEach(printScope, function(val, key) {
                        sub_scope[key] = val;
                    })

                    var resp = $compile($scope.elm.contents())(sub_scope);

                    var deferred = $q.defer();
                    $timeout(function(){
                        // give the $digest a chance to complete then
                        // resolve with the compiled HTML from our
                        // print container

                        deferred.resolve(
                            resp.contents()[0].parentNode.innerHTML
                        );
                    });

                    return deferred.promise;
                }
            }
        ]
    }
}])

