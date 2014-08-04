'use strict';

describe('egEvent', function(){
    beforeEach(module('egCoreMod'));

    var evt = {                                                                           
        ilsevent: "12345",                                                         
        pid: "12345",                                                             
        desc: "Test Event Description",
        payload: {test : 'xyz'},                                                             
        textcode: "TEST_EVENT",
        servertime: "Wed Nov 6 16:05:50 2013"                                     
    };

    it('should parse an event object', inject(function(egEvent) {
        expect(egEvent.parse(evt)).not.toBe(null);
    }));

    it('should not parse a non-event', inject(function(egEvent) {
        expect(egEvent.parse({})).toBe(null);
    }));

    it('should not parse a non-event', inject(function(egEvent) {
        expect(egEvent.parse({abc : '123'})).toBe(null);
    }));

    it('should not parse a non-event', inject(function(egEvent) {
        expect(egEvent.parse([])).toBe(null);
    }));

    it('should not parse a non-event', inject(function(egEvent) {
        expect(egEvent.parse('STRING')).toBe(null);
    }));

    it('should not parse a non-event', inject(function(egEvent) {
        expect(egEvent.parse(true)).toBe(null);
    }));

    it('should stringify an event', inject(function(egEvent) {
        expect(egEvent.parse(evt).toString()).toBe(
            'Event: 12345:TEST_EVENT -> Test Event Description')
    }));

});
