/**
 * Core Service - egNet
 *
 * Promise wrapper for OpenSRF network calls.
 * http://docs.angularjs.org/api/ng.$q
 *
 * promise.notify() is called with each streamed response.
 *
 * promise.resolve() is called when the request is complete 
 * and passes as its value the response received from the 
 * last call to onresponse().  If no calls to onresponse()
 * were made (i.e. no responses delivered) no value will
 * be passed to resolve(), hence any value seen by the client
 * will be 'undefined'.
 *
 * Example: Call with one response and no error checking:
 *
 * egNet.request(service, method, param1, param2).then(
 *    function(data) { 
 *      // data == undefined if no responses were received
 *      // data == null if last response was a null value
 *      console.log(data) 
 *    });
 *
 * Example: capture streaming responses, error checking
 *
 * egNet.request(service, method, param1, param2).then(
 *      function(data) { console.log('all done') },
 *      function(err)  { console.log('error: ' + err) },
 *      functoin(data) { console.log('received stream response ' + data) }
 *  );
 */

angular.module('egCoreMod')

.factory('egNet', 
       ['$q','$rootScope','egEvent', 
function($q,  $rootScope,  egEvent) {

    var net = {};

    // Simple container class for tracking a single request.
    function NetRequest(kwargs) {
        var self = this;
        angular.forEach(kwargs, function(val, key) { self[key] = val });
    }

    // Relay response object to the caller for typical/successful responses.  
    // Applies special handling to response events that require global
    // attention.
    net.handleResponse = function(request) {
        request.evt = egEvent.parse(request.last);

        if (request.evt) {

            if (request.evt.textcode == 'NO_SESSION') {
                $rootScope.$broadcast('egAuthExpired');
                request.deferred.reject();
                return;

            } else if (request.evt.textcode == 'PERM_FAILURE') {

                if (!net.handlePermFailure) {
                    // nothing we can do, pass the failure up to the caller.
                    console.debug("egNet has no handlePermFailure()");
                    request.deferred.notify(request.last);
                    return;
                }

                // handlePermFailure() starts a new series of promises.
                // Tell our in-progress promise to resolve, etc. along
                // with the new handlePermFailure promise.
                request.superseded = true;
                net.handlePermFailure(request).then(
                    request.deferred.resolve, 
                    request.deferred.reject, 
                    request.deferred.notify
                );
            }
        }

        request.deferred.notify(request.last);
    };

    net.request = function(service, method) {
        var params = Array.prototype.slice.call(arguments, 2);

        var request = new NetRequest({
            service    : service,
            method     : method,
            params     : params,
            deferred   : $q.defer(),
            superseded : false
        });

        console.debug('egNet ' + method);
        new OpenSRF.ClientSession(service).request({
            async  : true,
            method : request.method,
            params : request.params,
            oncomplete : function() {
                if (!request.superseded)
                    request.deferred.resolve(request.last);
            },
            onresponse : function(r) {
                request.last = r.recv().content();
                net.handleResponse(request);
            },
            onerror : function(msg) {
                // 'msg' currently tells us very little, so don't 
                // bother JSON-ifying it, since there is the off
                // chance that JSON-ification could fail, e.g if 
                // the object has circular refs.
                var note = request.method + 
                    ' (' + request.params + ')  failed.  See server logs.';
                console.error(note, msg);
                request.deferred.reject(note);
            },
            onmethoderror : function(req, statCode, statMsg) { 
                var msg = 'error calling method ' + 
                    request.method + ' : ' + statCode + ' : ' + statMsg;
                console.error(msg);
                request.deferred.reject(msg);
            }

        }).send();

        return request.deferred.promise;
    }

    // In addition to the service and method names, accepts a single array
    // as the collection of API call parameters.  This array will get 
    // expanded to individual arguments in the final server call.
    // This is useful when the server call expects each param to be
    // a top-level value, but the set of params is dynamic.
    net.requestWithParamList = function(service, method, params) {
        var args = [service, method].concat(params);
        return net.request.apply(net, args);
    }

    return net;
}]);
