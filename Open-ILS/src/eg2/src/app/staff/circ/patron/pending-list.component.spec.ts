import { ComponentFixture, TestBed } from '@angular/core/testing';
import { PendingListComponent } from './pending-list.component';
import { PendingListService, PendingPatron } from './pending-list.service';
import { CUSTOM_ELEMENTS_SCHEMA, EventEmitter } from '@angular/core';
import { MockGenerators } from 'test_data/mock_generators';
import { GridComponent } from '@eg/share/grid/grid.component';
import { ConfirmDialogComponent } from '@eg/share/dialog/confirm.component';
import { of } from 'rxjs';
import { GridContext } from '@eg/share/grid/grid';
import { BroadcastService } from '@eg/share/util/broadcast.service';
import { StaffCommonModule } from '@eg/staff/common.module';

describe('PendingListComponent', () => {
    const DEFAULT_ORG_ID = 1;
    const mockPatron = () => (
        { user: MockGenerators.idlObject({ usrname: 'test' }) } as PendingPatron
    );

    let component: PendingListComponent;
    let fixture: ComponentFixture<PendingListComponent>;

    const mockEmitter = new EventEmitter<any>();
    let mockBroadcast: jasmine.SpyObj<BroadcastService>;
    let mockPending: jasmine.SpyObj<PendingListService>;

    let mockGrid: jasmine.SpyObj<GridComponent>;
    let mockConfirm: jasmine.SpyObj<ConfirmDialogComponent>;

    beforeEach(async () => {
        mockBroadcast = jasmine.createSpyObj<BroadcastService>(['listen']);
        mockBroadcast.listen.and.returnValue(mockEmitter);
        mockPending = jasmine.createSpyObj<PendingListService>([
            'defaultContextOrg', 'getPendingPatrons',
            'deletePendingPatrons', 'loadPendingPatron'
        ]);
        mockPending.defaultContextOrg.and.returnValue(DEFAULT_ORG_ID);
        mockPending.deletePendingPatrons.and.returnValue(of(['1']));

        mockGrid = jasmine.createSpyObj<GridComponent>(['reload']);
        mockGrid.context = { rowSelector: { isEmpty: () => true } } as GridContext;
        mockConfirm = jasmine.createSpyObj<ConfirmDialogComponent>(['open']);

        await TestBed.configureTestingModule({
            imports: [PendingListComponent],
            schemas: [CUSTOM_ELEMENTS_SCHEMA],
            providers: [
                { provide: BroadcastService, useValue: mockBroadcast },
                { provide: PendingListService, useValue: mockPending }
            ]
        }).overrideComponent(PendingListComponent, {
            add: { schemas: [CUSTOM_ELEMENTS_SCHEMA] },
            remove: { imports: [StaffCommonModule] }
        }).compileComponents();

        fixture = TestBed.createComponent(PendingListComponent);
        component = fixture.componentInstance;
        component.grid = mockGrid;
        component.confirmDeleteDialog = mockConfirm;
    });

    it('should initialize contextOrg from service', () => {
        expect(component.contextOrg).toBe(DEFAULT_ORG_ID);
    });

    it('should reload grid on broadcast event', () => {
        mockEmitter.emit({ usr: { home_ou: DEFAULT_ORG_ID } });
        expect(mockGrid.reload).toHaveBeenCalled();
    });

    describe('deletePendingPatrons()', () => {
        const patrons = [mockPatron()];

        it('shouldn\'t call delete service method if not confirmed', () => {
            mockConfirm.open.and.returnValue(of(false));
            component.deletePendingPatrons(patrons);
            expect(mockPending.deletePendingPatrons).not.toHaveBeenCalled();
        });
        it('should call delete service method after confirmation', () => {
            mockConfirm.open.and.returnValue(of(true));
            component.deletePendingPatrons(patrons);
            expect(mockPending.deletePendingPatrons).toHaveBeenCalledWith(patrons);
        });
        it('should reload grid on success', () => {
            mockConfirm.open.and.returnValue(of(true));
            component.deletePendingPatrons(patrons);
            expect(mockGrid.reload).toHaveBeenCalled();
        });
    });

    describe('loadPendingPatron()', () => {
        it('should call service to load patron', () => {
            const patron = mockPatron();
            component.loadPendingPatron([patron]);
            expect(mockPending.loadPendingPatron).toHaveBeenCalledWith(patron);
        });
    });

    describe('pendingOrgChanged()', () => {
        const org = MockGenerators.idlObject({ id: 2 });

        it('should update contextOrg', () => {
            component.pendingOrgChanged(org);
            expect(component.contextOrg).toBe(2);
        });
        it('should reload grid', () => {
            component.pendingOrgChanged(org);
            expect(mockGrid.reload).toHaveBeenCalled();
        });
    });
});
