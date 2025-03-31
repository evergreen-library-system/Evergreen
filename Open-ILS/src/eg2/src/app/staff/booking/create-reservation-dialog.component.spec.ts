import { FormatService } from '@eg/core/format.service';
import { CreateReservationDialogComponent } from './create-reservation-dialog.component';
import { AlertDialogComponent } from '@eg/share/dialog/alert.component';
import { PatronBarcodeValidator } from '@eg/share/validators/patron_barcode_validator.directive';
import { NetService } from '@eg/core/net.service';
import { of } from 'rxjs';
import { AuthService } from '@eg/core/auth.service';
import * as moment from 'moment';
import { TestBed } from '@angular/core/testing';
import { OrgService } from '@eg/core/org.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { Router } from '@angular/router';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';
import { ToastService } from '@eg/share/toast/toast.service';
import { NO_ERRORS_SCHEMA } from '@angular/core';

let component: CreateReservationDialogComponent;

describe('CreateReservationDialogComponent', () => {
    it('when it receives an event, it opens a failure dialog', done => {
        const mockFormat = jasmine.createSpyObj<FormatService>([], {wsOrgTimezone: 'America/Los_Angeles'});
        const mockPbv = jasmine.createSpyObj<PatronBarcodeValidator>(['validate']);
        const mockAuth = jasmine.createSpyObj<AuthService>(['token']);
        const mockNet = jasmine.createSpyObj<NetService>(['request']);
        mockNet.request.and.returnValue(of({
            'pid': 10241,
            'servertime': 'Sun Oct 15 06:05:50 2023',
            // eslint-disable-next-line max-len
            'stacktrace': '/usr/local/share/perl/5.30.0/OpenILS/Application/Booking.pm:213 /usr/local/share/perl/5.30.0/OpenSRF/Application.pm:628 /usr/share/perl5/Error.pm:465',
            'ilsevent': '',
            'textcode': 'RESOURCE_IN_USE',
            'desc': 'Resource is in use at this time'
        }));
        TestBed.configureTestingModule({
            providers: [
                {provide: AuthService, useValue: mockAuth},
                {provide: FormatService, useValue: mockFormat},
                {provide: NetService, useValue: mockNet},
                {provide: OrgService, useValue: null},
                {provide: PcrudService, useValue: null},
                {provide: Router, useValue: null},
                {provide: NgbModal, useValue: null},
                {provide: PatronBarcodeValidator, useValue: mockPbv},
                {provide: ToastService, useValue: null}
            ],
            schemas: [NO_ERRORS_SCHEMA],
        }).compileComponents();
        component = TestBed.createComponent(CreateReservationDialogComponent).componentInstance;
        component.ngOnInit();
        component.setDefaultTimes([moment()], 15);
        component.targetResourceType = {id: 10, label: 'Friendly penguin'};
        component.fail = jasmine.createSpyObj<AlertDialogComponent>(['open']);
        component.addBresv$().subscribe({
            complete: () => {
                expect(component.fail.open).toHaveBeenCalled();
                done();
            }
        });
    });
});
