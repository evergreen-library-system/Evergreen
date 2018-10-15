angular.module('egCoreMod')

/*
 * Iframe container for (mostly legacy) embedded interfaces
 */
.directive('egEmbedFrame', function() {
    return {
        restrict : 'AE',
        replace : true,
        scope : {
            // URL to load in the embed iframe
            url : '=',

            // optional hash of functions which augment or override 
            // the stock xulG functions defined below.
            handlers : '=?',
            frame : '=?',

            // called after onload of each new iframe page
            onchange : '=?',

            // called after egFrameEmbedLoader, during link phase
            afterload : '@',

            // for tweaking height
            saveSpace : '@',
            minHeight : '=?',

            // to display button for displaying embedded page
            // in a new tab
            allowEscape : '=?'
        },

        templateUrl : './share/t_eframe',

        link: function (scope, element, attrs) {
            scope.autoresize = 'autoresize' in attrs;
            scope.showIframe = true;
            // well, I *might* embed XUL; in any event, this gives a way
            // for things like Dojo widgets to detect whether they are
            // running in an eframe before the frame load has finished.
            window.IEMBEDXUL = true;
            element.find('iframe').on(
                'load',
                function() {
                    scope.egEmbedFrameLoader(this);
                    if (scope.afterload) this.contentWindow[scope.afterload]();
                }
            );
        },

        controller : 
                   ['$scope','$window','$location','$q','$timeout','egCore',
            function($scope , $window , $location , $q , $timeout , egCore) {

            $scope.save_space = $scope.saveSpace ? $scope.saveSpace : 300;
            // Set the initial iframe height to just under the window height.
            // leave room for the navbar, padding, margins, etc.
            $scope.height = $window.outerHeight - $scope.save_space;
            if ($scope.minHeight && $scope.height < $scope.minHeight) {
                $scope.height = $scope.minHeight;
            }

            // browser client doesn't use cookies, so we don't load the
            // (at the time of writing, quite limited) angular.cookies
            // module.  We could load something, but this seems to work
            // well enough for setting the auth cookie (at least, until 
            // it doesn't).
            //
            // note: document.cookie is smart enough to leave unreferenced
            // cookies alone, so contrary to how this might look, it's not 
            // deleting other cookies (anoncache, etc.)
            
            // delete any existing ses cookie
            $window.document.cookie = "ses=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT";
            // push our authtoken in
            $window.document.cookie = 'ses=' + egCore.auth.token() + '; path=/; secure'

            // $location has functions for modifying paths and search,
            // but they all assume you are staying within the angular
            // app, which we are not.  Build the URLs by hand.
            function open_tab(path) {
                var url = 'https://' + $window.location.hostname + 
                    egCore.env.basePath + path;
                console.debug('egEmbedFrame opening tab ' + url);
                $window.open(url, '_blank').focus();
            }

            // define our own xulG functions to be inserted into the
            // iframe.  NOTE: window-level functions are bad.  Though
            // there is probably a way, I was unable to correctly wire
            // up the iframe onload handler within the controller or link
            // funcs.  In any event, the code below is meant as a stop-gap
            // for porting dojo, etc. apps to angular apps and should
            // eventually go away.
            // NOTE: catalog integration is not a stop-gap

            $scope.egEmbedFrameLoader = function(iframe) {

                $scope.frame = {dom:iframe};
                $scope.iframe = iframe;

                if ($scope.autoresize) {
                    iFrameResize({}, $scope.iframe);
                } else {
                    // Reset the iframe height to the final content height.
                    if ($scope.height < $scope.iframe.contentWindow.document.body.scrollHeight)
                        $scope.height = $scope.iframe.contentWindow.document.body.scrollHeight;
                }

                var page = $scope.iframe.contentWindow.location.href;
                console.debug('egEmbedFrameLoader(): ' + page);

                if (page.match(/eg\/staff\/loading$/)) { // loading page

                    // If we have a startup-time URL, apply it now.
                    if ($scope.url) {
                        console.debug('Applying initial URL: ' + $scope.url);
                        iframe.contentWindow.location.href = $scope.url;
                    }

                    // Watch for future URL changes
                    $scope.$watch('url', function(newVal, oldVal) {
                        if (newVal && newVal != oldVal) {
                            iframe.contentWindow.location.href = newVal;
                        }
                    });

                    // Nothing more is needed until the iframe is
                    // loaded once more with a real URL.
                    return;
                }

                // reload ifram page w/o reloading the entire UI
                $scope.reload = function() {
                    $scope.iframe.contentWindow.location.replace(
                        $scope.iframe.contentWindow.location);
                }

                $scope.style = function() {
                    return 'height:' + $scope.height + 'px';
                }

                // tell the iframe'd window its inside the staff client
                $scope.iframe.contentWindow.IAMXUL = true;

                // also tell it it's inside the browser client, which 
                // may be needed in a few special cases.
                $scope.iframe.contentWindow.IAMBROWSER /* hear me roar */ = true; 

                // XUL has a dump() function which is occasinally called 
                // from embedded browsers.
                $scope.iframe.contentWindow.dump = function(msg) {
                    console.debug('egEmbedFrame:dump(): ' + msg);
                }

                // Adjust the height again if the iframe loads the openils.Util Dojo module
                $timeout(function () {
                    if ($scope.autoresize) return; // let iframe-resizer handle it
                    if ($scope.iframe.contentWindow.openils && $scope.iframe.contentWindow.openils.Util) {

                        // HACK! for patron reg page
                        var e = $scope.iframe.contentWindow.document.getElementById('myForm');
                        var extra = 50;
                        
                        // HACK! for vandelay
                        if (!e) {
                            e = $scope.iframe.contentWindow.document.getElementById('vl-body-wrapper');
                            extra = 10000;
                        }

                        if (!e) {
                            e = $scope.iframe.contentWindow.document.body;
                            extra = 0;
                        }

                        if ($scope.height < e.scrollHeight + extra) {
                            $scope.iframe.contentWindow.openils.Util.addOnLoad( function() {
                                var old_height = $scope.height;
                                $scope.height = e.scrollHeight + extra;
                                $scope.$apply();
                            });
                        }
                    }
                });

                // define a few commonly used stock xulG handlers. 
                
                $scope.iframe.contentWindow.xulG = {
                    // patron search
                    spawn_search : function(search) {
                        open_tab('/circ/patron/search?search=' 
                            + encodeURIComponent(js2JSON(search)));
                    },

                    // edit an existing user
                    spawn_editor : function(info) {
                        if (info.usr) {
                            open_tab('/circ/patron/register/edit/' + info.usr);
                        
                        } else if (info.clone) {
                            // FIXME: The save-and-clone operation in the
                            // patron editor results in this action.  
                            // For some reason, this specific function results
                            // in a new browser window opening instead of a 
                            // browser tab.  Possibly this is caused by the 
                            // fact that the action occurs as a result of a
                            // button click instead of an href.  *shrug*.
                            // It's obnoxious.
                            open_tab('/circ/patron/register/clone/' + info.clone);
                        } 
                    },

                    // open a user account
                    new_patron_tab : function(tab_info, usr_info) {
                        open_tab('/circ/patron/' + usr_info.id + '/checkout');
                    },

                    get_barcode_and_settings_async : function(barcode, only_settings) {
                        if (!barcode) return $q.reject();
                        var deferred = $q.defer();

                        var barcode_promise = $q.when(barcode);
                        if (!only_settings) {

                            // first verify / locate the barcode
                            barcode_promise = egCore.net.request(
                                'open-ils.actor',
                                'open-ils.actor.get_barcodes',
                                egCore.auth.token(), 
                                egCore.auth.user().ws_ou(), 'actor', barcode
                            ).then(function(resp) {

                                if (!resp || egCore.evt.parse(resp) || !resp.length) {
                                    console.error('user not found: ' + barcode);
                                    deferred.reject();
                                    return null;
                                } 

                                resp = resp[0];
                                return barcode = resp.barcode;
                            });
                        }

                        barcode_promise.then(function(barcode) {
                            if (!barcode) return;

                            return egCore.net.request(
                                'open-ils.actor',
                                'open-ils.actor.user.fleshed.retrieve_by_barcode',
                                egCore.auth.token(), barcode);

                        }).then(function(user) {
                            if (!user) return null;

                            if (e = egCore.evt.parse(user)) {
                                console.error('user fetch failed : ' + e.toString());
                                deferred.reject();
                                return null;
                            }

                            egCore.org.settings(['circ.staff_placed_holds_fallback_to_ws_ou'])
                                .then(function(auth_usr_aous){

                                    // copied more or less directly from XUL menu.js
                                    var settings = {};
                                    for(var i = 0; i < user.settings().length; i++) {
                                        settings[user.settings()[i].name()] = 
                                            JSON2js(user.settings()[i].value());
                                    }

                                    // find applicable YAOUSes for staff-placed holds
                                    var requestor = egCore.auth.user();
                                    var pickup_lib = user.home_ou(); // default to home ou
                                    if (requestor.id() !== user.id()){
                                        // this is a staff-placed hold, optionally default to ws ou
                                        if (auth_usr_aous['circ.staff_placed_holds_fallback_to_ws_ou']){
                                            pickup_lib = requestor.ws_ou();
                                        }
                                    }

                                    if(!settings['opac.default_phone'] && user.day_phone()) 
                                        settings['opac.default_phone'] = user.day_phone();
                                    if(!settings['opac.hold_notify'] && settings['opac.hold_notify'] !== '') 
                                        settings['opac.hold_notify'] = 'email:phone';

                                    // Taken from patron/util.js format_name
                                    // FIXME: I18n
                                    var patron_name = 
                                        ( user.prefix() ? user.prefix() + ' ' : '') +
                                        user.family_name() + ', ' +
                                        user.first_given_name() + ' ' +
                                        ( user.second_given_name() ? user.second_given_name() + ' ' : '' ) +
                                        ( user.suffix() ? user.suffix() : '');

                                    deferred.resolve({
                                        "barcode": barcode, 
                                        "pickup_lib": pickup_lib,
                                        "settings" : settings, 
                                        "user_email" : user.email(), 
                                        "patron_name" : patron_name
                                    });
                                });
                        });

                        return deferred.promise;
                    }
                }

                if ($scope.handlers) {
                    $scope.handlers.reload = $scope.reload;
                    angular.forEach($scope.handlers, function(val, key) {
                        console.log('eframe applying xulG handlers: ' + key);
                        $scope.iframe.contentWindow.xulG[key] = val;
                    });
                }

                if ($scope.onchange) $scope.onchange(page);
            }

            // open a new tab with the embedded URL
            $scope.escapeEmbed = function() {
                $scope.showIframe = false;
                $window.open($scope.iframe.contentWindow.location, '_blank').focus();
            }
            $scope.restoreEmbed = function() {
                $scope.showIframe = true;
                $scope.reload();
            }
        }]
    }
})


