'use strict';

describe('egDate', function(){
    beforeEach(module('egCoreMod'));

    it('should parse a simple interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('2 days')).toBe(172800);
    }));

    it('should parse a combined interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('1 min 2 seconds')).toBe(62);
    }));

    it('should parse a time interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('02:00:23')).toBe(7223);
    }));

});
