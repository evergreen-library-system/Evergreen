import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CredentialInputComponent } from './credential-input.component';

describe('CredentialInputComponent', () => {
    let component: CredentialInputComponent;
    let fixture: ComponentFixture<CredentialInputComponent>;

    beforeEach(async () => {
        await TestBed.configureTestingModule({
            declarations: [ CredentialInputComponent ]
        })
            .compileComponents();

        fixture = TestBed.createComponent(CredentialInputComponent);
        component = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('should create', () => {
        expect(component).toBeTruthy();
    });
    it('uses the domId input as the input id', () => {
        component.domId = 'my-id-is-nice';
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('input').id).toEqual('my-id-is-nice');
    });
    it('starts out with the credential invisible', () => {
        expect(fixture.nativeElement.querySelector('input').getAttribute('type')).toEqual('password');
        expect(fixture.nativeElement.querySelector('input').getAttribute('aria-description')).toEqual('Your password is not visible.');
        expect(fixture.nativeElement.querySelector('button').getAttribute('title')).toEqual('Show Password');
        expect(fixture.nativeElement.querySelector('button').getAttribute('aria-label')).toEqual('Show Password');
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('visibility_off');
    });
    it('can toggle the visibility on', () => {
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('input').getAttribute('type')).toEqual('text');
        expect(fixture.nativeElement.querySelector('input').getAttribute('aria-description')).toEqual('Your password is visible!');
        expect(fixture.nativeElement.querySelector('button').getAttribute('title')).toEqual('Hide Password');
        expect(fixture.nativeElement.querySelector('button').getAttribute('aria-label')).toEqual('Hide Password');
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('visibility');
    });
    it('toggling the visibility sets focus back to the input', () => {
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();
        const input = fixture.nativeElement.querySelector('input');
        const focusElement = fixture.nativeElement.querySelector(':focus');
        expect(focusElement).toBe(input);
    });
    it('can toggle the visibility off again', () => {
        fixture.nativeElement.querySelector('button').click();
        fixture.nativeElement.querySelector('button').click();
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('input').getAttribute('type')).toEqual('password');
        expect(fixture.nativeElement.querySelector('input').getAttribute('aria-description')).toEqual('Your password is not visible.');
        expect(fixture.nativeElement.querySelector('button').getAttribute('title')).toEqual('Show Password');
        expect(fixture.nativeElement.querySelector('button').getAttribute('aria-label')).toEqual('Show Password');
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('visibility_off');
    });
});
