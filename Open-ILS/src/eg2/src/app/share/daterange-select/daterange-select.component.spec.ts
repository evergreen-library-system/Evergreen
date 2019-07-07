import {ComponentFixture, TestBed} from '@angular/core/testing';
import {Component, DebugElement, Input, TemplateRef} from '@angular/core';
import {By} from '@angular/platform-browser';
import {DateRange, DateRangeSelectComponent} from './daterange-select.component';
import {ReactiveFormsModule} from '@angular/forms';
import {NgbDate} from '@ng-bootstrap/ng-bootstrap';

@Component({
    // tslint:disable-next-line:component-selector
    selector: 'ngb-datepicker',
    template: ''
})
class EgMockDateSelectComponent {
    @Input() displayMonths: number;
    @Input() dayTemplate: TemplateRef<any>;
    @Input() outsideDays: string;
    @Input() markDisabled:
        (date: NgbDate, current: { year: number; month: number; }) => boolean =
        (date: NgbDate, current: { year: number; month: number; }) => false
}

describe('Component: DateRangeSelect', () => {
    let component: DateRangeSelectComponent;
    let fixture: ComponentFixture<DateRangeSelectComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            declarations: [
                DateRangeSelectComponent,
                EgMockDateSelectComponent,
        ]});

        fixture = TestBed.createComponent(DateRangeSelectComponent);
        component = fixture.componentInstance;
        component.ngOnInit();
    });


    it('creates a range when the user clicks two dates, with the earlier date clicked first', () => {
        component.onDateSelection(new NgbDate(2004, 6, 4));
        component.onDateSelection(new NgbDate(2005, 7, 27));
        expect(component.selectedRange.toDate).toBeTruthy();
    });

    it('creates a range with a null value when the user clicks two dates, with the later date clicked first', () => {
        component.onDateSelection(new NgbDate(2011, 1, 27));
        component.onDateSelection(new NgbDate(2006, 11, 16));
        expect(component.selectedRange.toDate).toBeNull();
    });

});
