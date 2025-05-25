import {Component, EventEmitter, Output, ViewChild} from '@angular/core';
import {switchMap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    selector: 'eg-cancel-reservation-dialog',
    template: `
  <eg-confirm-dialog #confirmCancelReservationDialog
    i18n-dialogTitle i18n-dialogBody
    dialogTitle="Confirm Cancelation"
    [dialogBodyTemplate]="confirmMessage">
  </eg-confirm-dialog>
  <ng-template #confirmMessage>
    <span i18n>
      Are you sure you want to cancel
      {reservations.length, plural, =1 {this reservation} other {these {{reservations.length}} reservations}}?
    </span>
  </ng-template>
  `
})

export class CancelReservationDialogComponent {

    constructor(
        private auth: AuthService,
        private net: NetService,
        private toast: ToastService
    ) {
    }

    reservations: number[];

    @ViewChild('confirmCancelReservationDialog', { static: true })
    private cancelReservationDialog: ConfirmDialogComponent;

    @Output() reservationCancelled = new EventEmitter();

    open(reservations: number[]) {
        this.reservations = reservations;
        this.cancelReservationDialog.open()
            .pipe(
                switchMap(() => this.net.request(
                    'open-ils.booking',
                    'open-ils.booking.reservations.cancel',
                    this.auth.token(), reservations))
            )
            .subscribe(
                (res) => {
                    if (res.textcode) {
                        this.toast.danger('Could not cancel reservation'); // TODO: needs i18n, pluralization
                    } else {
                        this.toast.success('Reservation successfully canceled'); // TODO: needs i18n, pluralization
                        this.reservationCancelled.emit();
                    }
                }
            );
    }

}

