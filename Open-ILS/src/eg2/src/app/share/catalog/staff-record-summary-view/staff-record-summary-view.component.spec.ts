import { ComponentFixture, TestBed } from '@angular/core/testing';
import { StaffRecordSummaryViewComponent } from './staff-record-summary-view.component';
import { BibFieldService } from '../bib-field.service';
import { of } from 'rxjs';
import { BibRecordSummary } from '../bib-record.service';
import { MockGenerators } from 'test_data/mock_generators';
import { provideRouter } from '@angular/router';

describe('StaffRecordSummaryViewComponent', () => {
    let component: StaffRecordSummaryViewComponent;
    let fixture: ComponentFixture<StaffRecordSummaryViewComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ StaffRecordSummaryViewComponent ],
            providers: [
                provideRouter([]),
                {provide: BibFieldService, useValue: {displayFields: of(), fieldLabels: of({})}}
            ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(StaffRecordSummaryViewComponent);
        component = fixture.componentInstance;
        component.summary = new BibRecordSummary(MockGenerators.idlObject({id: 30}), 10);
        fixture.detectChanges();
    });

    it('should display the requested field from the supplied summary', () => {
        component.summary.staffViewDisplayEntries = [[{
            content_type: 'field',
            value: ['Mars (Planet)'],
            query_field: 'subject|geographic'
        }]];
        fixture.detectChanges();
        console.log(fixture.nativeElement);

        expect(fixture.nativeElement.textContent).toContain('Mars (Planet)');
    });


    it('displays nothing if there is no value', () => {
        component.summary.staffViewDisplayEntries = [[{content_type: 'field'}]];
        fixture.detectChanges();

        expect(fixture.nativeElement.textContent.trim()).toEqual('');
    });

    it('shows a link if the field is a search field', () => {
        component.summary.staffViewDisplayEntries = [[{
            content_type: 'field',
            value: ['Mars (Planet)'],
            query_field: 'subject|geographic',
            display_as_link: true
        }]];
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('a').getAttribute('href'))
            .toEqual('/staff/catalog/search?query=subject%7Cgeographic:Mars%20(Planet)');
    });
});
