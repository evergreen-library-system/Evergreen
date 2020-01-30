/**
 * Module for batching promises
 *
 * This service helps to reduce server load for repetitive OpenSRF
 * calls by dividing a large array of promises into batches. It
 * maintains the original order of the array when returning results.
 * 
 * Within each batch, calls are sent simultaneously. The batches
 * themselves are run sequentially.
 *
 * This represents a middle ground between running a ton of OpenSRF
 * calls sequentially -- which leads to a long wait for the user --
 * and running them simultaneously, which can result in some serious
 * wait times. 
 *
 * One use case is when you need to get several rows from pcrud,
 * but the order of results is important and can't be just passed
 * using orderBy.
 * 
 * You can just replace $q.all with egBatchPromises.all
 */

angular.module('egBatchPromisesMod', [])

.factory('egBatchPromises', ['$q', function($q) {

    var service = {};

    // Helper method to break an array into chunks of a specified size
    service.createChunks = function(array_to_be_chunked, chunk_size = 10) {
        var results = [];
    
        while (array_to_be_chunked.length) {
            results.push(array_to_be_chunked.splice(0, chunk_size));
        }
    
        return results;
    };

    // Helper method that adds a batch of simultaneous promises to a sequential
    // chain
    service.addBatchToChain = function(chain, batch) {
        return chain.then(() => $q.all(batch));
    }

    // Returns a chain of chunked promises
    service.all = function(array_of_promises, chunk_size = 10) {
        var chunked_array = this.createChunks(array_of_promises, chunk_size);
        return chunked_array.reduce(this.addBatchToChain, $q.when());
    };

    return service;
}]);

