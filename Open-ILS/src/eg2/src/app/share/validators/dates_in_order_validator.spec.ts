import { AbstractControl } from '@angular/forms';
import { datesInOrderValidator } from './dates_in_order_validator.directive';

describe('datesInOrderValidator', () => {
    const mockForm = jasmine.createSpyObj<AbstractControl>(['get']);
    const mockEarlierDateInput = jasmine.createSpyObj<AbstractControl>('AbstractControl', [], {value: '2020-10-12'});
    const mockLaterDateInput = jasmine.createSpyObj<AbstractControl>('AbstractControl', [], {value: '2030-01-01'});
    it('returns null if two fields are in order', () => {
        mockForm.get.and.returnValues(mockEarlierDateInput, mockLaterDateInput);
        expect(datesInOrderValidator(['startDate', 'endDate'])(mockForm)).toEqual(null);
    });
    it('returns an object if fields are out of order', () => {
        mockForm.get.and.returnValues(mockLaterDateInput, mockEarlierDateInput);
        expect(datesInOrderValidator(['startDate', 'endDate'])(mockForm)).toEqual({ datesOutOfOrder: 'Dates should be in order' });
    });
});
