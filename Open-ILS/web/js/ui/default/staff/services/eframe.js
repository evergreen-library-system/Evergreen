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
            handlers : '=',

            // called after onload of each new iframe page
            onchange : '=',
        },

        templateUrl : './share/t_eframe',

        controller : 
                   ['$scope','$window','$location','$q','$timeout','egCore',
            function($scope , $window , $location , $q , $timeout , egCore) {

            // Set the iframe height to just under the window height.
            // leave room for the navbar, padding, margins, etc.
            $scope.height = $window.outerHeight - 300;

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
            $window.egEmbedFrameLoader = function(iframe) {

                var page = iframe.contentWindow.location.href;
                console.debug('egEmbedFrameLoader(): ' + page);

                // reload ifram page w/o reloading the entire UI
                $scope.reload = function() {
                    iframe.contentWindow.location.replace(
                        iframe.contentWindow.location);
                }

                // tell the iframe'd window its inside the staff client
                iframe.contentWindow.IAMXUL = true;

                // also tell it it's inside the browser client, which 
                // may be needed in a few special cases.
                iframe.contentWindow.IAMBROWSER /* hear me roar */ = true; 

                // XUL has a dump() function which is occasinally called 
                // from embedded browsers.
                iframe.contentWindow.dump = function(msg) {
                    console.debug('egEmbedFrame:dump(): ' + msg);
                }

                // define a few commonly used stock xulG handlers. 
                
                iframe.contentWindow.xulG = {
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

                            // copied more or less directly from XUL menu.js
                            var settings = {};
                            for(var i = 0; i < user.settings().length; i++) {
                                settings[user.settings()[i].name()] = 
                                    JSON2js(user.settings()[i].value());
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
                                "settings" : settings, 
                                "user_email" : user.email(), 
                                "patron_name" : patron_name
                            });
                        });

                        return deferred.promise;
                    }
                }

                if ($scope.handlers) {
                    $scope.handlers.reload = $scope.reload;
                    angular.forEach($scope.handlers, function(val, key) {
                        iframe.contentWindow.xulG[key] = val;
                    });
                }

                if ($scope.onchange) $scope.onchange(page);
            }
        }]
    }
})


