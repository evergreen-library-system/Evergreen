'use strict';

describe('egDate', function(){
    beforeEach(module('egCoreMod'));

    beforeEach(function () {
        jasmine.addMatchers({

            // "2 days" may be 47, 48, or 49 hours depending on the 
            // proximity to and direction of a time change event.
            // This does not take leap seconds into account.
            toBe2DaysOfSeconds: function () {
                return {
                    compare : function(actual) {
                        var hours_47 = 169200;
                        var hours_48 = 172800;
                        var hours_49 = 176400;

                        var passed = (
                            actual == hours_47 || 
                            actual == hours_48 || 
                            actual == hours_49
                        );

                        return {
                            pass: passed,
                            message: "Expected " + actual + " to be " + 
                                hours_47 + ", " + hours_48 + ", or " + hours_49
                        };
                    }
                };
            }
        });
    });

    it('should parse a simple interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('2 days')).toBe2DaysOfSeconds();
    }));

    it('should parse a combined interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('1 min 2 seconds')).toBe(62);
    }));

    it('should parse a time interval', inject(function(egDate) {
        expect(egDate.intervalToSeconds('02:00:23')).toBe(7223);
    }));

});
