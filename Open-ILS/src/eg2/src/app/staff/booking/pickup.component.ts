import {Component, OnInit, ViewChild, OnDestroy} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Subscription, of, single, filter, switchMap, debounceTime, tap} from 'rxjs';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {ReservationsGridComponent} from './reservations-grid.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {FormControl, FormGroup, Validators} from '@angular/forms';
import {PatronBarcodeValidator} from '@eg/share/validators/patron_barcode_validator.directive';


@Component({
    templateUrl: './pickup.component.html'
})

export class PickupComponent implements OnInit, OnDestroy {
    patronId: number;
    findPatron: FormGroup;
    subscriptions: Subscription[] = [];
    onlyShowCaptured = true;

    @ViewChild('readyGrid', { static: false }) readyGrid: ReservationsGridComponent;
    @ViewChild('pickedUpGrid', { static: false }) pickedUpGrid: ReservationsGridComponent;

    noSelectedRows: (rows: IdlObject[]) => boolean;
    handleShowCapturedChange: () => void;
    retrievePatron: () => void;

    constructor(
        private pcrud: PcrudService,
        private patron: PatronService,
        private pbv: PatronBarcodeValidator,
        private route: ActivatedRoute,
        private router: Router,
        private store: ServerStoreService,
        private toast: ToastService
    ) {
    }


    ngOnInit() {
        this.findPatron = new FormGroup({
            'patronBarcode': new FormControl(null,
                [Validators.required],
                [this.pbv.validate])
        });

        this.route.paramMap.pipe(
            filter((params: ParamMap) => params.has('patron_id')),
            switchMap((params: ParamMap) => {
                this.patronId = +params.get('patron_id');
                return this.pcrud.search('au', {
                    'id': this.patronId,
                }, {
                    limit: 1,
                    flesh: 1,
                    flesh_fields: {'au': ['card']}});
            })
        ).subscribe(
            (response) => {
                this.findPatron.patchValue({patronBarcode: response.card().barcode()}, {emitEvent: false});
                this.readyGrid.reloadGrid();
                this.pickedUpGrid.reloadGrid();
            }
        );

        const debouncing = 1500;
        this.subscriptions.push(
            this.patronBarcode.valueChanges.pipe(
                debounceTime(debouncing),
                switchMap((val) => {
                    if ('INVALID' === this.patronBarcode.status) {
                        this.toast.danger('No patron found with this barcode');
                        return of();
                    } else {
                        return this.patron.bcSearch(val).pipe(
                            single(),
                            tap((resp) => { this.router.navigate(['/staff', 'booking', 'pickup', 'by_patron', resp[0].id]); })
                        );
                    }
                })
            )
                .subscribe());


        this.store.getItem('eg.booking.pickup.ready.only_show_captured').then(onlyCaptured => {
            // eslint-disable-next-line eqeqeq
            if (onlyCaptured != null) { this.onlyShowCaptured = onlyCaptured; }
        });
        this.handleShowCapturedChange = () => {
            this.onlyShowCaptured = !this.onlyShowCaptured;
            this.readyGrid.reloadGrid();
            this.store.setItem('eg.booking.pickup.ready.only_show_captured', this.onlyShowCaptured);
        };


    }
    get patronBarcode() {
        return this.findPatron.get('patronBarcode');
    }

    ngOnDestroy(): void {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

}
