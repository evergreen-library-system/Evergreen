import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FieldDisplayComponent } from './field-display.component';
import { RecordDisplayEntry } from '../bib-record.service';

describe('FieldDisplayComponent', () => {
    let component: FieldDisplayComponent;
    let fixture: ComponentFixture<FieldDisplayComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ FieldDisplayComponent ]
        }).compileComponents();

        fixture = TestBed.createComponent(FieldDisplayComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('can limit number of values', () => {
        component.field = {
            content_type: 'field',
            label: 'Cats',
            value_limit: 2,
            value: ['Tabby', 'Big Fluffy Cat', 'Grey Cat']
        };
        fixture.detectChanges();
        expect(component).toBeTruthy();
        expect(fixture.nativeElement.textContent).toContain('Tabby');
        expect(fixture.nativeElement.textContent).toContain('Big Fluffy Cat');
        expect(fixture.nativeElement.textContent).not.toContain('Grey Cat');
    });
});
