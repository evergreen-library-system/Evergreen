import { TestBed } from '@angular/core/testing';
import { SckoService } from './scko.service';
import { MockGenerators } from 'test_data/mock_generators';
import { MockDueDatePipe } from 'test_data/mock-pipes';
import { SckoCheckoutComponent } from './checkout.component';

const checkoutData = {
    circ: MockGenerators.idlObject({
        target_copy: MockGenerators.idlObject({
            call_number: MockGenerators.idlObject({record: MockGenerators.idlObject({id: '123'})}),
            barcode: '333333333'
        }),
        parent_circ: null,
        renewal_remaining: 1
    }),
    ctx: {}
};

function getPrintButton(domElement: HTMLElement): HTMLButtonElement {
    const buttons: HTMLButtonElement[] = Array.from(domElement.querySelectorAll('button'));
    return buttons.find(button => button.textContent === 'Print List');
}

describe('SckoCheckoutComponent', () => {
    it('greys out the Print List button if there is nothing to print', () => {
        TestBed.configureTestingModule({providers: [
            {provide: SckoService, useValue: MockGenerators.selfCheckService({sessionCheckouts: []})}
        ]});
        TestBed.overrideComponent(SckoCheckoutComponent, {set: {imports: [MockDueDatePipe]}});
        const fixture = TestBed.createComponent(SckoCheckoutComponent);
        fixture.detectChanges();

        const printButton = getPrintButton(fixture.nativeElement);
        expect(printButton.disabled).toBeTrue();
    });

    it('enables the Print List button if there is something to print', () => {
        TestBed.configureTestingModule({providers: [
            {provide: SckoService, useValue: MockGenerators.selfCheckService({sessionCheckouts: [checkoutData]})}
        ]});
        TestBed.overrideComponent(SckoCheckoutComponent, {set: {imports: [MockDueDatePipe]}});
        const fixture = TestBed.createComponent(SckoCheckoutComponent);
        fixture.detectChanges();

        const printButton = getPrintButton(fixture.nativeElement);
        expect(printButton.disabled).toBeFalse();
    });
});
