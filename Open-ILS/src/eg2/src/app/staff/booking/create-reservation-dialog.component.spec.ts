import { FormatService } from '@eg/core/format.service';
import { CreateReservationDialogComponent } from './create-reservation-dialog.component';
import { AlertDialogComponent } from '@eg/share/dialog/alert.component';
import { PatronBarcodeValidator } from '@eg/share/validators/patron_barcode_validator.directive';
import { NetService } from '@eg/core/net.service';
import { of } from 'rxjs';
import { AuthService } from '@eg/core/auth.service';
import * as moment from 'moment';

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
        component = new CreateReservationDialogComponent(mockAuth, mockFormat,
            mockNet, null, null, null, null, mockPbv, null);
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
