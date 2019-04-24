import {EventService} from './event.service';

describe('EventService', () => {
    let service: EventService;
    beforeEach(() => {
        service = new EventService();
    });

    const evt = {
        ilsevent: '12345',
        pid: '12345',
        desc: 'Test Event Description',
        payload: {test : 'xyz'},
        textcode: 'TEST_EVENT',
        servertime: 'Wed Nov 6 16:05:50 2013'
    };

    it('should parse an event object', () => {
        expect(service.parse(evt)).not.toBe(null);
    });

    it('should not parse a non-event', () => {
        expect(service.parse({})).toBe(null);
    });

    it('should not parse a non-event', () => {
        expect(service.parse({abc : '123'})).toBe(null);
    });

    it('should not parse a non-event', () => {
        expect(service.parse([])).toBe(null);
    });

    it('should not parse a non-event', () => {
        expect(service.parse('STRING')).toBe(null);
    });

    it('should not parse a non-event', () => {
        expect(service.parse(true)).toBe(null);
    });

    it('should stringify an event', () => {
        expect(service.parse(evt).toString()).toBe(
            'Event: 12345:TEST_EVENT -> Test Event Description');
    });

});
