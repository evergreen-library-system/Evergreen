import { ComponentFixture, TestBed } from '@angular/core/testing';
import { SelectComponent } from './select.component';

describe('SelectComponent', () => {
    let component: SelectComponent;
    let fixture: ComponentFixture<SelectComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            imports: [SelectComponent]
        });

        fixture = TestBed.createComponent(SelectComponent);
        fixture.componentRef.setInput('domId', 'my-id');
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });

    it('has a select', () => {
        expect(fixture.nativeElement.querySelector('select')).toBeTruthy();
    });

    it('can specify an id', () => {
        expect(fixture.nativeElement.querySelector('#my-id')).toBeTruthy();
    });

    it('can create the provided options', () => {
        fixture.componentRef.setInput('options', [{value: 'dog', label: 'Fido'}, {value: 'cat', label: 'Bonkers'}]);
        fixture.detectChanges();

        const options = fixture.nativeElement.querySelectorAll('option');
        expect(options[0].label).toEqual('Fido');
        expect(options[0].value).toEqual('dog');
        expect(options[1].label).toEqual('Bonkers');
        expect(options[1].value).toEqual('cat');
    });

    it('can writeValue()', () => {
        fixture.componentRef.setInput('options', [{value: 'dog', label: 'Fido'}, {value: 'cat', label: 'Bonkers'}]);
        fixture.detectChanges();
        component.writeValue('cat');
        fixture.detectChanges();

        const selected = fixture.nativeElement.querySelector('select').value;
        expect(selected).toEqual('cat');
    });

    it('can be disabled', () => {
        component.setDisabledState(true);
        fixture.detectChanges();

        expect(fixture.nativeElement.querySelector('select').disabled).toBeTruthy();
    });
});
