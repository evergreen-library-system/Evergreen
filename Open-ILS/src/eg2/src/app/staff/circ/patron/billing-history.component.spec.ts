import { CurrencyPipe } from '@angular/common';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { By } from '@angular/platform-browser';
import { Router, ActivatedRoute } from '@angular/router';

import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';

import { BillingHistoryComponent } from './billing-history.component';
import { PatronContextService } from './patron.service';

import { AddBillingDialogComponent } from '@eg/staff/share/billing/billing-dialog.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { PrintService } from '@eg/share/print/print.service';
import { PatronService } from '@eg/staff/share/patron/patron.service';
import { GridFlatDataService } from '@eg/share/grid/grid-flat-data.service';
import { MockGridComponent } from 'test_data/mock-components';

import { of } from 'rxjs';

describe('BillingHistoryComponent', () => {
    let component: BillingHistoryComponent;
    let fixture: ComponentFixture<BillingHistoryComponent>;
    let initialTab = 'transactions';

    beforeEach(async () => {
        const stub = {} as any;
        await TestBed.configureTestingModule({
            imports: [BillingHistoryComponent],
            providers: [
                { provide: Router, useValue: stub },
                { provide: ActivatedRoute, useValue: { paramMap: of({ get: () => initialTab }) } },
                { provide: PrintService, useValue: stub },
                { provide: PatronService, useValue: stub },
                { provide: PatronContextService, useValue: stub },
                { provide: GridFlatDataService, useValue: stub },
            ]
        }).overrideComponent(BillingHistoryComponent, {
            add: {
                imports: [MockGridComponent, NgbNavModule, CurrencyPipe],
                schemas: [CUSTOM_ELEMENTS_SCHEMA]
            },
            remove: {
                imports: [StaffCommonModule, AddBillingDialogComponent]
            }
        }).compileComponents();

        fixture = TestBed.createComponent(BillingHistoryComponent);
        component = fixture.componentInstance;
    });

    // Columns LP2088314 reports as missing from the Transactions subtab.
    const RESTORED_XACT_COLUMN_PATHS = [
        'summary.last_billing_type',
        'summary.last_billing_note',
        'summary.last_billing_ts',
        'summary.last_payment_type',
        'summary.last_payment_note',
    ];

    // Columns LP2088314 reports as missing from the Payments subtab.
    const RESTORED_PAYMENT_COLUMN_PATHS = [
        'xact.summary.last_billing_note',
        'xact.summary.total_owed',
        'xact.summary.total_paid',
        'credit_card_payment.approval_code',
    ];

    const declaredColumnPaths = (): string[] =>
        fixture.debugElement
            .queryAll(By.css('eg-grid-column'))
            .map(col => col.nativeElement.getAttribute('path'))
            .filter(path => path !== null);

    const expectDateOutputBindings = () => {
        const selectors = fixture.debugElement
            .queryAll(By.css('eg-date-select'));

        expect(selectors.length).toBe(2);

        selectors.forEach(selector => {
            const listenerNames = selector.listeners.map(
                listener => listener.name
            );

            expect(listenerNames).toContain('onChangeAsDate');
            expect(listenerNames).not.toContain('onChangeAsIso');
        });
    };

    it('declares the restored Last Billing and Last Payment columns on the Transactions tab', () => {
        initialTab = 'transactions';
        fixture.detectChanges();

        const paths = declaredColumnPaths();
        RESTORED_XACT_COLUMN_PATHS.forEach(path => expect(paths).toContain(path));
    });

    it('declares the restored detail and Approval Code columns on the Payments tab', () => {
        initialTab = 'payments';
        fixture.detectChanges();

        const paths = declaredColumnPaths();
        RESTORED_PAYMENT_COLUMN_PATHS.forEach(path => expect(paths).toContain(path));
    });

    it('binds transaction date selectors to the Date output', () => {
        initialTab = 'transactions';
        fixture.detectChanges();
        expectDateOutputBindings();
    });

    it('binds payment date selectors to the Date output', () => {
        initialTab = 'payments';
        fixture.detectChanges();
        expectDateOutputBindings();
    });

    it('reloads the transactions grid when the start date changes', () => {
        const xactsGrid = jasmine.createSpyObj('GridComponent', ['reload']);
        component['xactsGrid'] = xactsGrid;
        const date = new Date(2026, 6, 1);
        component.dateChange('xactsStart', date);
        expect(component.xactsStart).toEqual('2026-07-01');
        expect(xactsGrid.reload).toHaveBeenCalled();
    });

    it('reloads the transactions grid when the end date changes', () => {
        const xactsGrid = jasmine.createSpyObj('GridComponent', ['reload']);
        component['xactsGrid'] = xactsGrid;
        const date = new Date(2026, 6, 1);
        component.dateChange('xactsEnd', date);
        expect(component.xactsEnd).toEqual('2026-07-02');
        expect(xactsGrid.reload).toHaveBeenCalled();
    });
});