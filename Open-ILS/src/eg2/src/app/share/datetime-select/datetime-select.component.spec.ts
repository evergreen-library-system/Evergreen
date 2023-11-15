import * as moment from 'moment';
import { DateTimeSelectComponent } from './datetime-select.component';


describe('DateTimeSelectComponent', () => {
    const mockFormatService = jasmine.createSpyObj('FormatService', ['transform', 'momentizeIsoString']);
    mockFormatService.momentizeIsoString.and.returnValue(moment('2020-12-11T01:30:05.606Z').tz('America/Vancouver'));
    const mockDateTimeValidator = jasmine.createSpyObj('DateTimeValidator', ['']);
    const mockNgControl = jasmine.createSpyObj('ngControl', ['']);
    const component = new DateTimeSelectComponent(mockFormatService, mockDateTimeValidator, mockNgControl);

    it('accepts an initialIso input and converts it to the correct timezone', () => {
        component.initialIso = '2020-12-11T01:30:05.606Z';
        component.timezone = 'America/Vancouver';
        component.ngOnInit();
        expect(component.date.value).toEqual({year: 2020, month: 12, day: 10});
        expect(component.time.value).toEqual({hour: 17, minute: 30, second: 0});
    });

});
