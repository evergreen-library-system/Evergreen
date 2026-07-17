import { ComponentFixture, TestBed } from '@angular/core/testing';
import {FastAddItem, FastAddSelectorComponent} from './fast-add-selector.component';
import { Maybe, None, Some } from '@eg/share/maybe';

describe('FastAddSelectorComponent', () => {
    let fixture: ComponentFixture<FastAddSelectorComponent>;
    beforeEach(() => {
        fixture = TestBed.createComponent(FastAddSelectorComponent);
        fixture.detectChanges();
    });
    it('has an unchecked checkbox by default', () => {
        const checkbox = fixture.nativeElement.querySelector('input[type=checkbox]');
        expect(checkbox.checked).toBeFalse();
    });
    it('does not have barcode or call number by default', () => {
        expect(fixture.nativeElement.querySelector('input[aria-label=Barcode]')).toBeFalsy();
        expect(fixture.nativeElement.querySelector('input[aria-label="Call Number"]')).toBeFalsy();
    });
    it('shows barcode and call number when checkbox is checked', () => {
        const checkbox = fixture.nativeElement.querySelector('input[type=checkbox]');

        checkbox.click();
        fixture.detectChanges();

        expect(fixture.nativeElement.querySelector('input[aria-label=Barcode]')).toBeTruthy();
        expect(fixture.nativeElement.querySelector('input[aria-label="Call Number"]')).toBeTruthy();
    });
    it('emits a signal', async () => {
        let currentIntent: Maybe<FastAddItem>;
        fixture.componentInstance.fastAddItemChange.subscribe(intent => {
            currentIntent = intent;
        });

        fixture.nativeElement.querySelector('input[type=checkbox]').click();
        fixture.detectChanges();
        fixture.nativeElement.querySelector('input[aria-label=Barcode]').value = '333333';
        fixture.nativeElement.querySelector('input[aria-label="Call Number"]').value = 'ABC 123';
        fixture.nativeElement.querySelector('input[aria-label=Barcode]').dispatchEvent(new Event('input'));
        fixture.nativeElement.querySelector('input[aria-label="Call Number"]').dispatchEvent(new Event('input'));

        await fixture.whenStable();
        expect(currentIntent).toEqual(new Some<FastAddItem>({label: 'ABC 123', barcode: '333333', fast_add: true}));


        // Clear the required Call number field
        fixture.nativeElement.querySelector('input[aria-label="Call Number"]').value = '';
        fixture.nativeElement.querySelector('input[aria-label="Call Number"]').dispatchEvent(new Event('input'));

        await fixture.whenStable();
        expect(currentIntent).toEqual(new None<FastAddItem>());
    });
});
