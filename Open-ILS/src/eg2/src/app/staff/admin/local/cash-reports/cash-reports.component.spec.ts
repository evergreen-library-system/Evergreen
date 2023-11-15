/* eslint-disable no-unused-expressions */
import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { OrgService } from '@eg/core/org.service';
import { CashReportsComponent } from './cash-reports.component';
import { DateSelectComponent } from '@eg/share/date-select/date-select.component';
import { CUSTOM_ELEMENTS_SCHEMA } from '@angular/core';
import { NgbDatepickerModule, NgbNavModule } from '@ng-bootstrap/ng-bootstrap';
import { of } from 'rxjs';
import { FormsModule } from '@angular/forms';
import { DatesInOrderValidatorDirective } from '@eg/share/validators/dates_in_order_validator.directive';

const mockIdlObject = {a: null,
    classname: null,
    _isfieldmapper: null,
    id: () => {null;},
    ws_ou: () => {null;}};
const mockNet = jasmine.createSpyObj<NetService>(['request']);
mockNet.request.and.returnValue(of());
const mockOrg = jasmine.createSpyObj<OrgService>(['get', 'filterList']);
const mockAuth = jasmine.createSpyObj<AuthService>(['user', 'token']);
mockAuth.user.and.returnValue(mockIdlObject);

describe('CashReportsComponent', () => {
    it('alerts the user if end date is before start date', async () => {
        await TestBed.configureTestingModule({
            declarations: [
                CashReportsComponent,
                DateSelectComponent,
                DatesInOrderValidatorDirective
            ],
            providers: [
                {provide: IdlService, useValue: {}},
                {provide: NetService, useValue: mockNet},
                {provide: OrgService, useValue: mockOrg},
                {provide: AuthService, useValue: mockAuth}
            ],
            imports: [
                NgbNavModule,
                NgbDatepickerModule,
                FormsModule
            ],
            schemas: [CUSTOM_ELEMENTS_SCHEMA]
        }).compileComponents();

        const fixture = TestBed.createComponent(CashReportsComponent);
        const component = fixture.componentInstance;
        const element = fixture.nativeElement;
        component.selectedOrg = mockIdlObject;
        fixture.detectChanges();

        element.querySelector('#start-date').value = '2022-01-01';
        element.querySelector('#end-date').value = '2021-01-01';
        component.criteria.form.setErrors({datesOutOfOrder: true});
        component.criteria.form.markAsDirty();
        fixture.detectChanges();
        expect(element.querySelector('#dateOutOfOrderAlert').innerText).toContain('Start date must be before end date');
    });
});
