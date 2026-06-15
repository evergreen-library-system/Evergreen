import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { DueDateDialogComponent } from './due-date-dialog.component';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { MockGenerators } from 'test_data/mock_generators';

describe('DueDateDialogComponent', () => {
    const iso1 = '2026-01-01T12:00:00Z';
    const iso2 = '2026-02-01T12:00:00Z';
    const circWithDueDate = (due_date: string) =>
        MockGenerators.idlObject({ due_date });

    const modal = jasmine.createSpyObj<NgbModal>(['open']);
    let component: DueDateDialogComponent;
    let fixture: ComponentFixture<DueDateDialogComponent>;

    beforeEach(() => {
        TestBed.configureTestingModule({
            providers: [{ provide: NgbModal, useValue: modal }]
        });

        fixture = TestBed.createComponent(DueDateDialogComponent);
        component = fixture.componentInstance;
    });

    describe('open', () => {
        it('should floor nowTime to minutes for picker compatibility', () => {
            component.open();
            const now = new Date(component['nowTime']);

            expect(now.getSeconds()).toBe(0);
            expect(now.getMilliseconds()).toBe(0);
        });
        it('should set dueDateIso to circ due date when editing one circ', () => {
            component.isRenewal = false;
            component.circs = [circWithDueDate(iso1)];
            component.open();

            expect(component['dueDateIso']).toEqual(iso1);
        });
        it('should not set dueDateIso to first circ due date when editing multiple circs', () => {
            component.isRenewal = false;
            component.circs = [circWithDueDate(iso1), circWithDueDate(iso2)];
            component.open();

            expect(component['dueDateIso']).not.toEqual(iso1);
        });
        it('should not set dueDateIso to first circ due date when renewing', () => {
            component.isRenewal = true;
            component.circs = [circWithDueDate(iso1)];
            component.open();

            expect(component['dueDateIso']).not.toEqual(iso1);
        });
    });

    describe('dueDateChange', () => {
        it('should set dueDateIso to param when not renewing', () => {
            component.isRenewal = false;
            component.open();
            component['dueDateChange'](iso1);

            expect(component['dueDateIso']).toEqual(iso1);
        });
        it('should set dueDateIso to param when renewing with a non-past date', () => {
            component.isRenewal = true;
            component.open();
            const iso = new Date().toISOString();
            component['dueDateChange'](iso);

            expect(component['dueDateIso']).toEqual(iso);
        });
        it('should set dueDateIso to null when renewing with a past date', () => {
            component.isRenewal = true;
            component.open();
            component['dueDateChange'](iso1);

            expect(component['dueDateIso']).toBeNull();
        });
    });
});
