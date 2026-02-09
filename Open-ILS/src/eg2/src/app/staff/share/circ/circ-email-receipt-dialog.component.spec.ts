import { ComponentFixture, TestBed, waitForAsync } from '@angular/core/testing';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { CircEmailReceiptDialogComponent } from './circ-email-receipt-dialog.component';
import { EmailReceiptData, EmailReceiptType } from './circ.service';
import { MockGenerators } from 'test_data/mock_generators';

describe('CircEmailReceiptDialogComponent', () => {
    const modal = jasmine.createSpyObj<NgbModal>(['open']);
    let component: CircEmailReceiptDialogComponent;
    let fixture: ComponentFixture<CircEmailReceiptDialogComponent>;

    const createOption = (
        id: number, first_given_name: string, family_name: string,
        circIds: number[] = [1], disabled = false,
        type: EmailReceiptType = 'checkin'
    ): EmailReceiptData => ({
        patron: MockGenerators.idlObject(
            { id, first_given_name, family_name }, 'au'
        ),
        circIds, disabled, type
    });

    beforeEach(waitForAsync(() => {
        TestBed.configureTestingModule({
            providers: [{ provide: NgbModal, useValue: modal }],
        }).compileComponents();
    }));

    beforeEach(() => {
        fixture = TestBed.createComponent(CircEmailReceiptDialogComponent);
        component = fixture.componentInstance;
    });

    describe('preventEnterOnSubmit', () => {
        it('should prevent default on enter on non-button elements', () => {
            const event = {
                key: 'Enter',
                target: { tagName: 'INPUT' } as HTMLElement,
                preventDefault: jasmine.createSpy('preventDefault')
            } as Partial<KeyboardEvent>;
            component.preventEnterOnSubmit(event as KeyboardEvent);
            expect(event.preventDefault).toHaveBeenCalled();
        });

        it('should not prevent default on enter on a button', () => {
            const event = {
                key: 'Enter',
                target: { tagName: 'BUTTON' } as HTMLElement,
                preventDefault: jasmine.createSpy('preventDefault')
            } as Partial<KeyboardEvent>;
            component.preventEnterOnSubmit(event as KeyboardEvent);
            expect(event.preventDefault).not.toHaveBeenCalled();
        });
    });

    describe('ok', () => {
        it('should close with the selected option', () => {
            const option1 = createOption(71, 'Leon', 'Anderson');
            const option2 = createOption(201, 'Gene', 'Adams');
            component.options = [option1, option2];
            component.selected = { patronId: 201 };
            spyOn(component, 'close');
            component.ok();
            expect(component.close).toHaveBeenCalledWith(option2);
        });

        it('should not close when no patron is selected', () => {
            component.options = [createOption(71, 'Leon', 'Anderson')];
            spyOn(component, 'close');
            component.ok();
            expect(component.close).not.toHaveBeenCalled();
        });
    });
});
