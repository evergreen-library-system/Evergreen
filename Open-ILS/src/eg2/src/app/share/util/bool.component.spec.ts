import { async, ComponentFixture, TestBed } from '@angular/core/testing';
import { BoolDisplayComponent } from './bool.component';
import { Component } from '@angular/core';
import { ViewChild } from '@angular/core';

describe('BoolDisplayComponent', () => {
    @Component({
        selector: `eg-host-component`,
        template: `<eg-bool></eg-bool>`
    })
    class TestHostComponent {
        @ViewChild(BoolDisplayComponent, {static: false})
        public boolDisplayComponent: BoolDisplayComponent;
    }

    let hostComponent: TestHostComponent;
    let fixture: ComponentFixture<TestHostComponent>;

    beforeEach(async(() => {
        TestBed.configureTestingModule({
        declarations: [ BoolDisplayComponent, TestHostComponent ],
        })
        .compileComponents();
    }));

    beforeEach(() => {
        fixture = TestBed.createComponent(TestHostComponent);
        hostComponent = fixture.componentInstance;
        fixture.detectChanges();
    });

    it('recognizes Javascript true', async() => {
        hostComponent.boolDisplayComponent.value = true;
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('Yes');
    });
    it('recognizes Javascript false', async() => {
        hostComponent.boolDisplayComponent.value = false;
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('No');
    });
    it('recognizes string "t"', async() => {
        hostComponent.boolDisplayComponent.value = 't';
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('Yes');
    });
    it('recognizes string "f"', async() => {
        hostComponent.boolDisplayComponent.value = 'f';
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('No');
    });
    it('recognizes ternary nul', async() => {
        hostComponent.boolDisplayComponent.value = null;
        hostComponent.boolDisplayComponent.ternary = true;
        fixture.detectChanges();
        expect(fixture.nativeElement.querySelector('span').innerText).toEqual('Unset');
    });

});
