import { Component } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FocusOnViewInitDirective } from './focus-on-view-init.directive';

@Component({
    template: '<input egFocusOnViewInit>',
    imports: [FocusOnViewInitDirective],
    standalone: true
})
export class TestComponent {}

describe('FocusOnViewInitDirective', () => {
    let fixture: ComponentFixture<TestComponent>;
    let input: HTMLInputElement;

    beforeEach(() => {
        TestBed.configureTestingModule({ imports: [TestComponent] });
        fixture = TestBed.createComponent(TestComponent);
        input = fixture.nativeElement.querySelector('input');
    });

    it('should focus an input with the directive applied', () => {
        const spy = spyOn(input, 'focus');
        fixture.detectChanges();
        expect(spy).toHaveBeenCalled();
    });
});
