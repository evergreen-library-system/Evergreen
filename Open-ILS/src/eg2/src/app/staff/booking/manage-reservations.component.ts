import {Component, OnInit, ViewChild, OnDestroy} from '@angular/core';
import {FormGroup, FormControl} from '@angular/forms';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Subscription, of, debounceTime, single, tap, switchMap} from 'rxjs';
import {NgbNav} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ReservationsGridComponent} from './reservations-grid.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {PatronBarcodeValidator} from '@eg/share/validators/patron_barcode_validator.directive';
import {BookingResourceBarcodeValidator} from './booking_resource_validator.directive';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';

@Component({
    selector: 'eg-manage-reservations',
    templateUrl: './manage-reservations.component.html',
})
export class ManageReservationsComponent implements OnInit, OnDestroy {

    patronId: number;
    resourceId: number;
    subscriptions: Subscription[] = [];
    filters: FormGroup;
    startingTab: 'patron' | 'resource' | 'type' = 'patron';
    startingPickupOrgs: OrgFamily = {primaryOrgId: this.auth.user().ws_ou(), includeDescendants: true};

    @ViewChild('filterTabs', { static: true }) filterTabs: NgbNav;
    @ViewChild('reservationsGrid', { static: true }) reservationsGrid: ReservationsGridComponent;

    removeFilters: () => void;

    constructor(
        private route: ActivatedRoute,
        private router: Router,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private store: ServerStoreService,
        private toast: ToastService,
        private patronValidator: PatronBarcodeValidator,
        private resourceValidator: BookingResourceBarcodeValidator
    ) {
        this.store.getItem('eg.booking.manage.selected_org_family').then((pickupLibs) => {
            if (pickupLibs) {
                this.startingPickupOrgs = pickupLibs;
            }
        });
    }

    ngOnInit() {
        this.filters = new FormGroup({
            'pickupLibraries': new FormControl(this.startingPickupOrgs),
            'patronBarcode': new FormControl('', [], [this.patronValidator.validate]),
            'resourceBarcode': new FormControl('', [], [this.resourceValidator.validate]),
            'resourceType': new FormControl(null),
        });

        const debouncing = 300;

        this.subscriptions.push(
            this.pickupLibraries.valueChanges.pipe(
            ).subscribe(() => this.reservationsGrid.reloadGrid()));

        this.subscriptions.push(
            this.patronBarcode.statusChanges.pipe(
                debounceTime(debouncing),
                switchMap((status) => {
                    if ('VALID' === status) {
                        return this.net.request(
                            'open-ils.actor',
                            'open-ils.actor.get_barcodes',
                            this.auth.token(), this.auth.user().ws_ou(),
                            'actor', this.patronBarcode.value.trim()).pipe(
                            single(),
                            tap((response) =>
                                this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_patron', response[0].id])
                            ));
                    } else {
                        this.toast.danger('No patron found with this barcode');
                        return of();
                    }
                })
            ).subscribe());

        this.subscriptions.push(
            this.resourceBarcode.statusChanges.pipe(
                debounceTime(debouncing),
                tap((status) => {
                    if ('VALID' === status) {
                        if (this.resourceBarcode.value) {
                            this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_resource', this.resourceBarcode.value]);
                        } else {
                            this.removeFilters();
                        }
                    }
                }
                )).subscribe());

        this.subscriptions.push(
            this.resourceType.valueChanges.pipe(
                tap((value) => {
                    if (value) {
                        this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_resource_type', value.id]);
                    } else {
                        this.removeFilters();
                    }
                }
                )).subscribe());

        this.subscriptions.push(
            this.pickupLibraries.valueChanges.pipe(
                tap((value) =>  this.store.setItem('eg.booking.manage.selected_org_family', value))
            ).subscribe());

        this.removeFilters = () => {
            this.router.navigate(['/staff', 'booking', 'manage_reservations']);
        };


        this.route.paramMap.pipe(
            switchMap((params: ParamMap) => {
                this.patronId = params.has('patron_id') ? +params.get('patron_id') : null;
                this.filters.patchValue({resourceBarcode: params.get('resource_barcode')}, {emitEvent: false});
                this.filters.patchValue({resourceType: {id: +params.get('resource_type_id')}}, {emitEvent: false});

                if (this.patronId) {
                    return this.pcrud.search('au', {
                        'id': this.patronId,
                    }, {
                        limit: 1,
                        flesh: 1,
                        flesh_fields: {'au': ['card']}
                    }).pipe(tap(
                        { next: (resp) => {
                            this.filters.patchValue({patronBarcode: resp.card().barcode()});
                        }, error: (err: unknown) => { console.debug(err); } }
                    ));
                } else if (this.resourceBarcode.value) {
                    this.startingTab = 'resource';
                    return this.pcrud.search('brsrc',
                        {'barcode' : this.resourceBarcode.value}, {'limit': 1}).pipe(
                        tap({ next: (res) => {
                            this.resourceId = res.id();
                        }, error: (err: unknown) => {
                            this.resourceId = -1;
                            this.toast.danger('No resource found with this barcode');
                        } }));
                } else if (this.resourceType.value) {
                    this.startingTab = 'type';
                    return of(null);
                } else {
                    return of(null);
                }

            })).subscribe();
    }

    get pickupLibraries() {
        return this.filters.get('pickupLibraries');
    }
    get patronBarcode() {
        return this.filters.get('patronBarcode');
    }
    get resourceBarcode() {
        return this.filters.get('resourceBarcode');
    }
    get resourceType() {
        return this.filters.get('resourceType');
    }
    get pickupLibrariesForGrid() {
        return this.pickupLibraries.value ?
            this.pickupLibraries.value.orgIds :
            [this.auth.user().ws_ou()];
    }
    get resourceTypeForGrid() {
        return this.resourceType.value ? this.resourceType.value.id : null;
    }

    ngOnDestroy(): void {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

}

