import {NgModule} from '@angular/core';
import {ReactiveFormsModule} from '@angular/forms';
import {StaffCommonModule} from '@eg/staff/common.module';
import {BookingRoutingModule} from './routing.module';
import {CancelReservationDialogComponent} from './cancel-reservation-dialog.component';
import {CreateReservationComponent} from './create-reservation.component';
import {CreateReservationDialogComponent} from './create-reservation-dialog.component';
import {ManageReservationsComponent} from './manage-reservations.component';
import {ReservationsGridComponent} from './reservations-grid.component';
import {PickupComponent} from './pickup.component';
import {PullListComponent} from './pull-list.component';
import {ReturnComponent} from './return.component';
import {NoTimezoneSetComponent} from './no-timezone-set.component';
import {PatronService} from '@eg/staff/share/patron.service';
import {BookingResourceBarcodeValidatorDirective} from './booking_resource_validator.directive';


@NgModule({
    imports: [
        StaffCommonModule,
        BookingRoutingModule,
        ReactiveFormsModule,
    ],
    providers: [PatronService],
    declarations: [
        CancelReservationDialogComponent,
        CreateReservationComponent,
        CreateReservationDialogComponent,
        ManageReservationsComponent,
        NoTimezoneSetComponent,
        PickupComponent,
        PullListComponent,
        ReservationsGridComponent,
        ReturnComponent,
        BookingResourceBarcodeValidatorDirective
    ],
    exports: [
        BookingResourceBarcodeValidatorDirective
    ]
})
export class BookingModule { }

