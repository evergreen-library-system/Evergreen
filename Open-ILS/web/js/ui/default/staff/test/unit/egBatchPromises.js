'use strict';

describe('egBatchPromises', function(){
    beforeEach(module('egBatchPromisesMod'));

    it('should chunk an array properly', inject(function(egBatchPromises) {
        var original_array = [1, 2, 3, 4, 5, 6, 7, 8];
        var expected_array = [[1, 2, 3], [4, 5, 6], [7, 8]];
        expect(egBatchPromises.createChunks(original_array, 3)).toEqual(expected_array);
    }));

    it('should add a batch to a promise chain properly', inject(function(egBatchPromises, $q, $rootScope, $timeout) {
        var resolved_value;
        var promise_that_shares_its_value = function (value) {
            return $q.when(value)
                .then((val) => {resolved_value = val});
        };

        var promise = promise_that_shares_its_value(1);
        var batch_to_add = [
            promise_that_shares_its_value(2),
            promise_that_shares_its_value(3),
            promise_that_shares_its_value(4),
        ];

        var chain = egBatchPromises.addBatchToChain(promise, batch_to_add);        

        chain.then();
        $rootScope.$apply();
        expect(resolved_value).toEqual(4);
    }));

});
