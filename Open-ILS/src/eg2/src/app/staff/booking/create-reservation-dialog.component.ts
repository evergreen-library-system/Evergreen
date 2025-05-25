import {Component, Input, Output, OnInit, ViewChild, EventEmitter} from '@angular/core';
import {FormGroup, FormControl, Validators} from '@angular/forms';
import {Router} from '@angular/router';
import {Observable, of, switchMap, single, startWith, tap} from 'rxjs';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
import {FormatService} from '@eg/core/format.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {notBeforeMomentValidator} from '@eg/share/validators/not_before_moment_validator.directive';
import {PatronBarcodeValidator} from '@eg/share/validators/patron_barcode_validator.directive';
import {PatronSearchDialogComponent} from '@eg/staff/share/patron/search-dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import * as moment from 'moment-timezone';
import { datesInOrderValidator } from '@eg/share/validators/dates_in_order_validator.directive';

@Component({
    selector: 'eg-create-reservation-dialog',
    templateUrl: './create-reservation-dialog.component.html'
})

export class CreateReservationDialogComponent
    extends DialogComponent implements OnInit {

    @Input() targetResource: number;
    @Input() targetResourceBarcode: string;
    @Input() targetResourceType: ComboboxEntry;
    @Input() patronId: number;
    @Input() attributes: number[] = [];
    @Input() resources: IdlObject[] = [];
    @Output() reservationRequestCompleted: EventEmitter<boolean>;

    create: FormGroup;
    patron$: Observable<{first_given_name: string, second_given_name: string, family_name: string}>;
    pickupLibId: number;
    timezone: string = this.format.wsOrgTimezone;
    pickupLibraryUsesDifferentTz: boolean;

    public disableOrgs: () => number[];
    addBresv$: () => Observable<any>;
    @ViewChild('fail', { static: true }) fail: AlertDialogComponent;
    @ViewChild('patronSearch') patronSearch: PatronSearchDialogComponent;

    handlePickupLibChange: ($event: IdlObject) => void;

    constructor(
        private auth: AuthService,
        private format: FormatService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private router: Router,
        private modal: NgbModal,
        private pbv: PatronBarcodeValidator,
        private toast: ToastService
    ) {
        super(modal);
        this.reservationRequestCompleted = new EventEmitter<boolean>();
    }

    ngOnInit() {

        this.create = new FormGroup({
            'patronBarcode': new FormControl('',
                [Validators.required],
                [this.pbv.validate]
            ),
            'emailNotify': new FormControl(true),
            'startTime': new FormControl(null, notBeforeMomentValidator(moment().add('15', 'minutes'))),
            'endTime': new FormControl(),
            'resourceList': new FormControl(),
            'note': new FormControl(),
        }, [datesInOrderValidator(['startTime', 'endTime'])]
        );
        if (this.patronId) {
            this.pcrud.search('au', {id: this.patronId}, {
                flesh: 1,
                flesh_fields: {'au': ['card']}
            }).subscribe((usr) =>
                this.create.patchValue({patronBarcode: usr.card().barcode()})
            );
        }

        this.addBresv$ = () => {
            let selectedResourceId = this.targetResource ? [this.targetResource] : null;
            if (!selectedResourceId &&
                this.resourceListSelection !== null &&
                'any' !== this.resourceListSelection.id) {
                selectedResourceId = [this.resourceListSelection.id];
            }
            return this.net.request(
                'open-ils.booking',
                'open-ils.booking.reservations.create',
                this.auth.token(),
                this.patronBarcode.value.trim(),
                this.selectedTimes,
                this.pickupLibId,
                this.targetResourceType.id,
                selectedResourceId,
                this.attributes.filter(Boolean),
                this.emailNotify,
                this.bresvNote
            ).pipe(tap({
                next: (response) => {
                    if ('ilsevent' in response) {
                        console.warn(response);
                        this.fail.open();
                    } else {
                        this.toast.success('Reservation successfully created');
                        console.debug(response);
                        this.close();
                    }
                }, error: (response: unknown) => {
                    console.warn(response);
                    this.fail.open();
                }, complete: () => this.reservationRequestCompleted.emit(true)
            }));
        };

        this.handlePickupLibChange = ($event) => {
            this.pickupLibId = $event.id();
            this.org.settings('lib.timezone', this.pickupLibId).then((tz) => {
                this.timezone = tz['lib.timezone'] || this.format.wsOrgTimezone;
                this.pickupLibraryUsesDifferentTz = (tz['lib.timezone'] && (this.format.wsOrgTimezone !== tz['lib.timezone']));
            });
        };

        this.disableOrgs = () => this.org.filterList( { canHaveVolumes : false }, true);

        this.patron$ = this.patronBarcode.statusChanges.pipe(
            startWith({first_given_name: '', second_given_name: '', family_name: ''}),
            switchMap(() => {
                if ('VALID' === this.patronBarcode.status) {
                    return this.net.request(
                        'open-ils.actor',
                        'open-ils.actor.get_barcodes',
                        this.auth.token(),
                        this.auth.user().ws_ou(),
                        'actor', this.patronBarcode.value.trim()).pipe(
                        single(),
                        switchMap((result) => {
                            return this.pcrud.retrieve('au', result[0]['id']).pipe(
                                switchMap((au) => {
                                    return of({
                                        first_given_name: au.first_given_name(),
                                        second_given_name: au.second_given_name(),
                                        family_name: au.family_name()});
                                })
                            );
                        })
                    );
                } else {
                    return of({
                        first_given_name: '',
                        second_given_name: '',
                        family_name: ''
                    });
                }
            })
        );
    }

    setDefaultTimes(times: moment.Moment[], granularity: number) {
        this.create.patchValue({startTime: moment.min(times),
            endTime: moment.max(times).clone().add(granularity, 'minutes')
        });
    }

    openPatronReservations = (): void => {
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(),
            this.auth.user().ws_ou(),
            'actor', this.patronBarcode.value
        ).subscribe((patron) => this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_patron', patron[0]['id']]));
    };

    addBresvAndOpenPatronReservations = (): void => {
        this.addBresv$().subscribe({
            next: (response) => {
                if (!('ilsevent' in response)) {
                    this.openPatronReservations();
                }
            }
        });
    };

    searchPatrons() {
        this.patronSearch.open({size: 'xl'}).toPromise().then(
            patrons => {
                if (!patrons || patrons.length === 0) { return; }
                const user = patrons[0];
                this.create.patchValue({patronBarcode: user.card().barcode()});
            }
        );
    }

    get emailNotify() {
        return this.create.get('emailNotify').value;
    }

    get bresvNote() {
        return this.create.get('note').value;
    }

    get patronBarcode() {
        return this.create.get('patronBarcode');
    }

    get resourceListSelection() {
        return this.create.get('resourceList').value;
    }

    get selectedTimes() {
        return [this.create.get('startTime').value.toISOString(),
            this.create.get('endTime').value.toISOString()];
    }
}

