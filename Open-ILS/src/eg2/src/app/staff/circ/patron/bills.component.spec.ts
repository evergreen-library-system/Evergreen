import { CurrencyPipe } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { Router } from '@angular/router';

import { BillsComponent } from './bills.component';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AddBillingDialogComponent } from '@eg/staff/share/billing/billing-dialog.component';
import { CreditCardDialogComponent } from '@eg/staff/share/billing/credit-card-dialog.component';

import { OrgService } from '@eg/core/org.service';
import { ServerStoreService } from '@eg/core/server-store.service';

import { AudioService } from '@eg/share/util/audio.service';
import { ToastService } from '@eg/share/toast/toast.service';
import { EventService } from '@eg/core/event.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { PrintService } from '@eg/share/print/print.service';
import { BillingService } from '@eg/staff/share/billing/billing.service';
import { GridFlatDataService } from '@eg/share/grid/grid-flat-data.service';
import { WorkLogService } from '@eg/staff/share/worklog/worklog.service';
import { PatronService } from '@eg/staff/share/patron/patron.service';
import { PatronContextService } from './patron.service';

describe('BillsComponent', () => {
    let component: BillsComponent;
    let serverStoreSpy: jasmine.SpyObj<ServerStoreService>;

    beforeEach(async () => {
        const stub = {} as any;
        serverStoreSpy = jasmine.createSpyObj('ServerStoreService', ['getItemBatch']);
        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({}));

        await TestBed.configureTestingModule({
            imports: [BillsComponent],
            providers: [
                { provide: Router, useValue: stub },
                { provide: AudioService, useValue: stub },
                { provide: ToastService, useValue: stub },
                { provide: EventService, useValue: stub },
                { provide: NetService, useValue: stub },
                { provide: PcrudService, useValue: stub },
                { provide: AuthService, useValue: stub },
                { provide: IdlService, useValue: stub },
                { provide: PrintService, useValue: stub },
                { provide: ServerStoreService, useValue: serverStoreSpy },
                { provide: BillingService, useValue: stub },
                { provide: GridFlatDataService, useValue: stub },
                { provide: WorkLogService, useValue: stub },
                { provide: PatronService, useValue: stub },
                { provide: PatronContextService, useValue: stub }
            ]
        }).overrideComponent(BillsComponent, {
            add: {
                imports: [CurrencyPipe], 
                schemas: [CUSTOM_ELEMENTS_SCHEMA] },
            remove: { imports: [StaffCommonModule, AddBillingDialogComponent, CreditCardDialogComponent] }
        }).compileComponents();

        component = TestBed.createComponent(BillsComponent).componentInstance;
    });

    it('disables patron credit when the setting is on', async () => {
        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({ 'circ.disable_patron_credit': true }));
        await component.loadSettings();
        expect(component.disablePatronCredit).toBeTrue();
    });

    it('uncheckBillsAndFocusSelectAll matches the library setting', async () => {
        serverStoreSpy.getItemBatch.and.returnValue(
            Promise.resolve({ 'ui.circ.billing.uncheck_bills_and_unfocus_payment_box': true }));
        await component.loadSettings();
        expect(component.uncheckBillsAndFocusSelectAll).toBeTrue();

        serverStoreSpy.getItemBatch.and.returnValue(
            Promise.resolve({ 'ui.circ.billing.uncheck_bills_and_unfocus_payment_box': false }));
        await component.loadSettings();
        expect(component.uncheckBillsAndFocusSelectAll).toBeFalse();

        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({}));
        await component.loadSettings();
        expect(component.uncheckBillsAndFocusSelectAll).toBeFalse();
    });

    it('does not focus any control while settings load', async () => {
        spyOn(component, 'focusPayAmount');
        spyOn(component, 'focusSelectAllBills');
        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({}));
        await component.loadSettings();
        expect(component.focusPayAmount).not.toHaveBeenCalled();
        expect(component.focusSelectAllBills).not.toHaveBeenCalled();
    });

    it('focuses the payment box on every bills tab activation when the setting is off', async () => {
        spyOn(component, 'focusPayAmount');
        spyOn(component, 'focusSelectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = false;

        await component.focusDefaultControlOnTabActivation();
        await component.focusDefaultControlOnTabActivation();

        expect(component.focusPayAmount).toHaveBeenCalledTimes(2);
        expect(component.focusSelectAllBills).not.toHaveBeenCalled();
    });

    it('focuses Select All on bills tab activation when the setting is on', async () => {
        spyOn(component, 'focusPayAmount');
        spyOn(component, 'focusSelectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = true;

        await component.focusDefaultControlOnTabActivation();

        expect(component.focusPayAmount).not.toHaveBeenCalled();
        expect(component.focusSelectAllBills).toHaveBeenCalled();
    });

    it('focuses the payment box on initial grid load when the setting is off', async () => {
        spyOn(component, 'focusPayAmount');
        spyOn(component, 'focusSelectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = false;

        await component.focusDefaultControlOnLoad();

        expect(component.focusPayAmount).toHaveBeenCalled();
        expect(component.focusSelectAllBills).not.toHaveBeenCalled();
    });

    it('focuses Select All on initial grid load when the setting is on', async () => {
        spyOn(component, 'focusPayAmount');
        spyOn(component, 'focusSelectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = true;

        await component.focusDefaultControlOnLoad();

        expect(component.focusPayAmount).not.toHaveBeenCalled();
        expect(component.focusSelectAllBills).toHaveBeenCalled();
    });

    it('focuses the payment box on initial grid load only once', async () => {
        spyOn(component, 'focusPayAmount');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = false;

        await component.focusDefaultControlOnLoad();
        await component.focusDefaultControlOnLoad();

        expect(component.focusPayAmount).toHaveBeenCalledTimes(1);
    });

    it('selects all bills on load when the setting is off or unset', async () => {
        spyOn(component, 'selectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = false;

        await component.selectAllBillsOnLoad();

        expect(component.selectAllBills).toHaveBeenCalled();
    });

    it('does not select bills on load when the setting is on', async () => {
        spyOn(component, 'selectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = true;

        await component.selectAllBillsOnLoad();

        expect(component.selectAllBills).not.toHaveBeenCalled();
    });

    it('selects bills on load only once', async () => {
        spyOn(component, 'selectAllBills');
        component.settingsReady = Promise.resolve();
        component.uncheckBillsAndFocusSelectAll = false;

        await component.selectAllBillsOnLoad();
        await component.selectAllBillsOnLoad();   // a later grid reload

        expect(component.selectAllBills).toHaveBeenCalledTimes(1);
    });

    it('enables patron credit when the setting is off or unset', async () => {
        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({ 'circ.disable_patron_credit': false }));
        await component.loadSettings();
        expect(component.disablePatronCredit).toBeFalse();
        serverStoreSpy.getItemBatch.and.returnValue(Promise.resolve({}));
        await component.loadSettings();
        expect(component.disablePatronCredit).toBeFalse();
    });
});