import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HoldCountDisplayComponent } from './hold-count-display.component';
import { BibRecordSummary } from '../bib-record.service';
import { MockGenerators } from 'test_data/mock_generators';

describe('HoldCountDisplayComponent', () => {
    let component: HoldCountDisplayComponent;
    let fixture: ComponentFixture<HoldCountDisplayComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [ HoldCountDisplayComponent ]
        });

        const summary = new BibRecordSummary(MockGenerators.idlObject({id: 333_333}), 12);
        summary.holdCount = 13;

        fixture = TestBed.createComponent(HoldCountDisplayComponent);
        fixture.componentRef.setInput('summary', summary);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('should display the hold counts from the supplied summary', () => {
        expect(fixture.nativeElement.textContent).toContain('13 hold requests');
    });
});
