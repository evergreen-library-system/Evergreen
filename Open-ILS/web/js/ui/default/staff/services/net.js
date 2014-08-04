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

    // raises the egAuthExpired event on NO_SESSION
    net.checkResponse = function(resp) {
        var content = resp.content();
        if (!content) return null;
        var evt = egEvent.parse(content);
        if (evt && evt.textcode == 'NO_SESSION') {
            $rootScope.$broadcast('egAuthExpired') 
        } else {
            return content;
        }
    };

    net.request = function(service, method) {
        var last;
        var deferred = $q.defer();
        var params = Array.prototype.slice.call(arguments, 2);
        console.debug('egNet ' + method);
        new OpenSRF.ClientSession(service).request({
            async  : true,
            method : method,
            params : params,
            oncomplete : function() {
                deferred.resolve(last);
            },
            onresponse : function(r) {
                last = net.checkResponse(r.recv());
                deferred.notify(last);
            },
            onerror : function(msg) {
                // 'msg' currently tells us very little, so don't 
                // bother JSON-ifying it, since there is the off
                // chance that JSON-ification could fail, e.g if 
                // the object has circular refs.
                console.error(method + 
                    ' (' + params + ')  failed.  See server logs.');
                deferred.reject(msg);
            },
            onmethoderror : function(req, statCode, statMsg) { 
                console.error('error calling method ' + 
                method + ' : ' + statCode + ' : ' + statMsg);
            }

        }).send();

        return deferred.promise;
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
