import moment from 'moment';
import { DateTimeSelectComponent } from './datetime-select.component';
import { TestBed } from '@angular/core/testing';
import { FormatService } from '@eg/core/format.service';
import { DatetimeValidator } from '../validators/datetime_validator.directive';
import { NgControl } from '@angular/forms';


describe('DateTimeSelectComponent', () => {
    let component: DateTimeSelectComponent;
    beforeEach(() => {
        const mockFormatService = jasmine.createSpyObj('FormatService', ['transform', 'momentizeIsoString']);
        mockFormatService.momentizeIsoString.and.returnValue(moment('2020-12-11T01:30:05.606Z').tz('America/Vancouver'));
        const mockDateTimeValidator = jasmine.createSpyObj('DateTimeValidator', ['']);
        const mockNgControl = jasmine.createSpyObj('ngControl', ['']);
        TestBed.configureTestingModule({providers: [
            {provide: FormatService, useValue: mockFormatService},
            {provide: DatetimeValidator, useValue: mockDateTimeValidator},
            {provide: NgControl, useValue: mockNgControl}
        ]});
        component = TestBed.createComponent(DateTimeSelectComponent).componentInstance;

    });

    it('accepts an initialIso input and converts it to the correct timezone', () => {
        component.initialIso = '2020-12-11T01:30:05.606Z';
        component.timezone = 'America/Vancouver';
        component.ngOnInit();
        expect(component.date.value).toEqual({year: 2020, month: 12, day: 10});
        expect(component.time.value).toEqual({hour: 17, minute: 30, second: 0});
    });

});
