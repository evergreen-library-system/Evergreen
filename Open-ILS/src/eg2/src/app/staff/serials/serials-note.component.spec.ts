import { ComponentFixture, TestBed } from '@angular/core/testing';

import { SerialsNoteComponent } from './serials-note.component';
import { MockGenerators } from 'test_data/mock_generators';

describe('SerialsNoteComponent', () => {
    let component: SerialsNoteComponent;
    let fixture: ComponentFixture<SerialsNoteComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            imports: [ SerialsNoteComponent ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(SerialsNoteComponent);
        component = fixture.componentInstance;
        component.note = MockGenerators.idlObject({title: 'Don\'t barcode me', value: 'uncheck the barcode checkbox please', alert: 'f'});
        fixture.detectChanges();
    });

    it('displays the note title', () => {
        expect(fixture.nativeElement.innerText).toContain('Don\'t barcode me');
    });
});
