import { DateUtil } from './date';

describe('DateUtil', () => {
    describe('getOpenSrfTzOffsetString()', () => {
        it('returns a string with the +/- and 4 digit offset', () => {
            // Pretend that we are in Honolulu time (GMT-10:00)
            // getTimezoneOffset confusingly returns positive numbers for
            // timezones that are behind UTC
            const newfoundlandOffsetInMinutes = 10 * 60;
            spyOn(Date.prototype, 'getTimezoneOffset').and.returnValue(newfoundlandOffsetInMinutes);

            expect(DateUtil.getOpenSrfTzOffsetString()).toEqual('-1000');
        });

        it('handles Newfoundland time', () => {
            // Pretend that we are in Newfoundland time (GMT-2:30)
            const newfoundlandOffsetInMinutes = (2 * 60) + 30;
            spyOn(Date.prototype, 'getTimezoneOffset').and.returnValue(newfoundlandOffsetInMinutes);

            expect(DateUtil.getOpenSrfTzOffsetString()).toEqual('-0230');
        });

        it('handles timezones ahead of UTC', () => {
            // Pretend that we are in Europe/Helsinki time (GMT+2:00)
            const newfoundlandOffsetInMinutes = (-2 * 60);
            spyOn(Date.prototype, 'getTimezoneOffset').and.returnValue(newfoundlandOffsetInMinutes);

            expect(DateUtil.getOpenSrfTzOffsetString()).toEqual('+0200');
        });
    });
});
