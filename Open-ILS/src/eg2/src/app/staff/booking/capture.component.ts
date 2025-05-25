import {Component, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {FormGroup, FormControl} from '@angular/forms';
import {of, Subscription, debounceTime, switchMap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {BookingResourceBarcodeValidator} from './booking_resource_validator.directive';
import {ReservationActionsService} from './reservation-actions.service';
import {ReservationsGridComponent} from './reservations-grid.component';

@Component({
    templateUrl: './capture.component.html'
})

export class CaptureComponent implements OnInit, OnDestroy {

    findResource: FormGroup;
    subscriptions: Subscription[] = [];

    @ViewChild('capturedTodayGrid', { static: false }) capturedTodayGrid: ReservationsGridComponent;
    @ViewChild('noResourceString', { static: true }) noResourceString: StringComponent;
    @ViewChild('captureSuccessString', { static: true }) captureSuccessString: StringComponent;
    @ViewChild('captureFailureString', { static: true }) captureFailureString: StringComponent;

    constructor(
        private auth: AuthService,
        private net: NetService,
        private resourceValidator: BookingResourceBarcodeValidator,
        private toast: ToastService,
        private actions: ReservationActionsService
    ) {
    }

    ngOnInit() {
        this.findResource = new FormGroup({
            'resourceBarcode': new FormControl(null, [], this.resourceValidator.validate)
        });

        const debouncing = 1500;
        this.subscriptions.push(
            this.resourceBarcode.valueChanges.pipe(
                debounceTime(debouncing),
                switchMap((val) => {
                    if ('INVALID' === this.resourceBarcode.status) {
                        this.noResourceString.current()
                            .then(str => this.toast.danger(str));
                        return of();
                    } else {
                        return this.net.request( 'open-ils.booking',
                            'open-ils.booking.resources.capture_for_reservation',
                            this.auth.token(), this.resourceBarcode.value )
                            .pipe(switchMap((result: any) => {
                                if (result && result.ilsevent !== undefined) {
                                    if (result.payload && result.payload.captured > 0) {
                                        this.captureSuccessString.current()
                                            .then(str => this.toast.success(str));
                                        this.actions.printCaptureSlip(result.payload);
                                        this.capturedTodayGrid.reloadGrid();
                                    } else {
                                        this.captureFailureString.current()
                                            .then(str => this.toast.danger(str));
                                    }
                                } else {
                                    this.captureFailureString.current()
                                        .then(str => this.toast.danger(str));
                                }
                                return of();
                            }));
                    }
                })
            )
                .subscribe());

    }

    get resourceBarcode() {
        return this.findResource.get('resourceBarcode');
    }


    ngOnDestroy(): void {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

}
