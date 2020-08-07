/**
 * Core Service - egEnv
 *
 * Manages startup data loading and data caching.  
 * All registered loaders run * simultaneously.  When all promises 
 * are resolved, the promise * returned by egEnv.load() is resolved.
 *
 * There are two main uses cases for egEnv:
 *
 * 1. When loading a variety of objects on page load, having them
 * loaded with egEnv ensures that the load will happen in parallel
 * and that it will complete before egStartup completes, which is 
 * generally before page controllers run.
 *
 * 2. When loading generic IDL data across different services,
 * having them all stash the data in egEnv means they each have
 * an agreed-upon cache mechanism.
 *
 * It's also a good place to stash other environmental tidbits...
 *
 * Generic and class-based loaders are supported.  
 *
 * To load a registred class, push the class hint onto 
 * egEnv.loadClasses.  
 *
 * // will cause all 'pgt' objects to be fetched
 * egEnv.loadClasses.push('pgt');
 *
 * To register a new class loader,attach a loader function to 
 * egEnv.classLoaders, keyed on the class hint, which returns a promise.
 *
 * egEnv.classLoaders.ccs = function() { 
 *    // loads copy status objects, returns promise
 * };
 *
 * Generic loaders go onto the egEnv.loaders array.  Each should
 * return a promise.
 *
 * egEnv.loaders.push(function() {
 *    return egNet.request(...)
 *    .then(function(stuff) { console.log('stuff!') 
 * });
 */

angular.module('egCoreMod')

// env fetcher
.factory('egEnv', 
       ['$q','$window','$injector','egAuth','egPCRUD','egIDL',
function($q,  $window , $injector , egAuth,  egPCRUD,  egIDL) { 

    var service = {
        // collection of custom loader functions
        loaders : [],

        // Add class hints to this list when offline does not need them and
        // if they cause "Maximum call stack size exceeded" console errors.
        // If offline does need a list that causes problems, a custom loader
        // will be necessary.
        // We'll start with authority-related classes causing problems in the
        // staff catalog.
        ignoreOffline : ['at','acs','abaafm','aba','acsbf','acsaf']
    };


    // <base href="<basePath>"/> from the current index page
    // Currently defaults to /eg/staff for all pages.
    // Use $location.path() to jump around within an app.
    // Use egEnv.basePath to create URLs to new apps.
    // NOTE: the dynamic version below derived from the DOM does not
    // work w/ unit tests.  Use hard-coded value instead for now.
    service.basePath = '/eg/staff/';
        //$window.document.getElementsByTagName('base')[0].getAttribute('href');

    /* returns a promise, loads all of the specified classes */
    service.load = function() {
        // always assume the user is logged in
        if (!egAuth.user()) return $q.when();

        var allPromises = [];
        var classes = this.loadClasses;
        console.debug('egEnv loading classes => ' + classes);

        angular.forEach(classes, function(cls) {
            allPromises.push(service.classLoaders[cls]());
        });
        angular.forEach(this.loaders, function(loader) {
            allPromises.push(loader());
        });

        return $q.all(allPromises).then(
            function() { console.debug('egEnv load complete') });
    };

    /** given a tree-shaped collection, captures the tree and
     *  flattens the tree for absorption.
     */
    service.absorbTree = function(tree, class_, noOffline) {
        if (service[class_] && service[class_].loaded) return;

        var list = [];
        function squash(node) {
            list.push(node);
            angular.forEach(node.children(), squash);
        }
        squash(tree);
        var blob = service.absorbList(list, class_, noOffline);
        blob.tree = tree;
    };

    var egLovefield; // we'll inject it manually

    /** caches the object list both as the list and an id => object map */
    service.absorbList = function(list, class_, noOffline) {
        if (service[class_] && service[class_].loaded) return service[class_];

        var blob;
        var pkey = egIDL.classes[class_].pkey;

        if (service[class_]) {
            // appending data to an existing class.  Useful for receiving 
            // class elements as-needed.  Avoid adding items which are 
            // already tracked in the list.
            blob = service[class_];
            angular.forEach(list, function(item) {
                if (!service[class_].map[item[pkey]()]) 
                    blob.list.push(item);
            });
        } else {
            blob = {list : list, map : {}};
        }

        if (!noOffline && service.ignoreOffline.indexOf(class_) < 0) {
            if (!egLovefield) {
                egLovefield = $injector.get('egLovefield');
            }
            //console.debug('About to cache a list of ' + class_ + ' objects...');
            egLovefield.isCacheGood(class_).then(
                function(good) {
                    if (!good) {
                        egLovefield.setListInOfflineCache(class_, blob.list); 
                    }
                },
                function() {} // Not Supported
            );
        }

        angular.forEach(list, function(item) {blob.map[item[pkey]()] = item});
        service[class_] = blob;
        service[class_].loaded = true;
        return blob;
    };

    /* 
     * list of classes to load on every page, regardless of whether
     * a page-specific list is provided.
     */
    service.loadClasses = ['aou'];

    // sort orgs at each level by shortname
    service.sort_aou = function(node) {
        node.children(node.children().sort(function(a, b) {
            return a.shortname() < b.shortname() ? -1 : 1;
        }));
        angular.forEach(node.children(), service.sort_aou);
    }

    /*
     * Default class loaders.  Only add classes directly to this file
     * that are loaded practically always.  All other app-specific
     * classes should be registerd from within the app.
     */
    service.classLoaders = {
        aou : function() {

            if (!egLovefield) {
                egLovefield = $injector.get('egLovefield');
            }

            return egLovefield.reconstituteTree('aou').then(function(offline) {
                if (offline) return $q.when();
                if (service.aou && service.aou.loaded) return $q.when();
    
                // EXPERIMENT: cache the org tree in session storage.
                // This means that if the org tree changes, users will have to
                // open the client in a new browser tab to clear the cached tree.
                var treeJSON = $window.sessionStorage.getItem('eg.env.aou.tree');
                if (treeJSON) {
                    console.debug('serving org tree from cache');
                    var tree = JSON2js(treeJSON);
                    service.absorbTree(tree, 'aou')
                    return $q.when(tree);
                }
    
                return egPCRUD.search('aou', {parent_ou : null}, 
                    {flesh : -1, flesh_fields : {aou : ['children', 'ou_type']}}
                ).then(
                    function(tree) {
                        service.sort_aou(tree);
                        $window.sessionStorage.setItem(
                            'eg.env.aou.tree', js2JSON(tree));
                        service.absorbTree(tree, 'aou');
                        return $q.when();
                    }
                );
            },
            function() {return $q.when()} // Not Supported, exit gracefully
            );
        },
    };

    return service;
}]);



