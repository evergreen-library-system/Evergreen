import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FormatsAndEditionsDisplayComponent } from './formats-and-editions-display.component';
import { BibRecordSummary } from '../bib-record.service';
import { MockGenerators } from 'test_data/mock_generators';
import { CatalogService } from '../catalog.service';

const mockCatService = jasmine.createSpyObj<CatalogService>(['iconFormatLabel']);
mockCatService.iconFormatLabel.and.returnValue('Large Print Book');

describe('FormatsAndEditionsDisplayComponent', () => {
    let component: FormatsAndEditionsDisplayComponent;
    let fixture: ComponentFixture<FormatsAndEditionsDisplayComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ FormatsAndEditionsDisplayComponent ],
            providers: [
                {provide: CatalogService, useValue: mockCatService}
            ]
        }).compileComponents();

        fixture = TestBed.createComponent(FormatsAndEditionsDisplayComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('displays format links', () => {
        component.summary = new BibRecordSummary(MockGenerators.idlObject({id: 333_333}), 12);
        component.summary.staffViewMetabibAttributes = {
            'icon_format': {
                'lpbook': {
                    'label': 'Large Print Book',
                    'count': 1
                },
                'book': {
                    'label': 'Book',
                    'count': 2
                }
            }
        };
        component.summary.staffViewMetabibRecords = [333_333, 555_555];
        fixture.detectChanges();

        expect(fixture.nativeElement.textContent).toContain('Large Print Book');
    });
});
