'use strict';

describe('egStrings', function(){
    beforeEach(module('egCoreMod'));

    it('should interpolate values', inject(function(egStrings) {

        egStrings.FOO = 'Hello, {{planet}}';

        expect(egStrings.$replace(egStrings.FOO, {planet : 'Earth'}))
       .toBe('Hello, Earth');
    }));

});
