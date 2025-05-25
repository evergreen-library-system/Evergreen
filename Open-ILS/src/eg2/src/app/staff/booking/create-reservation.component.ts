import { Component, OnInit, AfterViewInit, QueryList, ViewChildren, ViewChild, OnDestroy } from '@angular/core';
import {FormGroup, FormControl, ValidationErrors, ValidatorFn, FormArray} from '@angular/forms';
import {Router, ActivatedRoute} from '@angular/router';
import {iif, Observable, of, throwError, timer, Subscription, catchError, debounceTime,
    takeLast, mapTo, single, switchMap, tap} from 'rxjs';
import {NgbCalendar, NgbNav} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {FormatService} from '@eg/core/format.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridRowFlairEntry, GridCellTextGenerator} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CreateReservationDialogComponent} from './create-reservation-dialog.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {DateRange} from '@eg/share/daterange-select/daterange-select.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ScheduleGridService, ScheduleRow} from './schedule-grid.service';
import {NoTimezoneSetComponent} from './no-timezone-set.component';

import * as moment from 'moment-timezone';

const startOfDayIsBeforeEndOfDayValidator: ValidatorFn = (fg: FormGroup): ValidationErrors | null => {
    const start = fg.get('startOfDay').value;
    const end = fg.get('endOfDay').value;
    return start !== null && end !== null &&
        (start.hour <= end.hour) &&
        !((start.hour === end.hour) && (start.minute >= end.minute))
        ? null
        : { startOfDayNotBeforeEndOfDay: true };
};

@Component({
    templateUrl: './create-reservation.component.html',
    styles: ['#ideal-resource-barcode {min-width: 300px;}']
})
export class CreateReservationComponent implements OnInit, AfterViewInit, OnDestroy {

    criteria: FormGroup;

    attributes: IdlObject[] = [];
    multiday = false;
    resourceAvailabilityIcon: (row: ScheduleRow) => GridRowFlairEntry;
    cellTextGenerator: GridCellTextGenerator;

    patronId: number;
    resourceBarcode: string;
    resourceId: number;
    transferable: boolean;
    resourceOwner: number;
    subscriptions: Subscription[] = [];

    // eslint-disable-next-line no-magic-numbers
    defaultGranularity = 30;
    granularity: number = this.defaultGranularity;

    scheduleSource: GridDataSource = new GridDataSource();

    minuteStep: () => number;
    reservationTypes: {id: string, name: string}[];

    openTheDialog: (rows: IdlObject[]) => void;

    resources: IdlObject[] = [];

    setGranularity: () => void;
    changeGranularity: ($event: ComboboxEntry) => void;

    dateRange: DateRange;
    detailsTab = '';

    @ViewChild('createDialog', { static: true }) createDialog: CreateReservationDialogComponent;
    @ViewChild('details', { static: true }) details: NgbNav;
    @ViewChild('noTimezoneSetDialog', { static: true }) noTimezoneSetDialog: NoTimezoneSetComponent;
    @ViewChild('viewReservation', { static: true }) viewReservation: FmRecordEditorComponent;
    @ViewChildren('scheduleGrid') scheduleGrids: QueryList<GridComponent>;

    constructor(
        private auth: AuthService,
        private calendar: NgbCalendar,
        private format: FormatService,
        private net: NetService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private router: Router,
        private scheduleService: ScheduleGridService,
        private store: ServerStoreService,
        private toast: ToastService,
    ) {
    }

    ngOnInit() {
        if (!(this.format.wsOrgTimezone)) {
            this.noTimezoneSetDialog.open();
        }

        const initialRangeLength = 10;
        const defaultRange = {
            fromDate: this.calendar.getToday(),
            toDate: this.calendar.getNext(
                this.calendar.getToday(), 'd', initialRangeLength)
        };

        this.route.paramMap.pipe(
            tap(params => {
                this.patronId = +params.get('patron_id');
                this.resourceBarcode = params.get('resource_barcode');
            }),
            switchMap(params => iif(() => params.has('resource_barcode'),
                this.handleBarcodeFromUrl$(params.get('resource_barcode')),
                of(params)
            ))
        ).subscribe({
            error() {
                console.warn('could not find a resource with this barcode');
            }
        });

        this.reservationTypes = [
            {id: 'single', name: 'Single day reservation'},
            {id: 'multi', name: 'Multiple day reservation'},
        ];

        const waitToLoadResource = 800;
        this.criteria = new FormGroup({
            'resourceBarcode': new FormControl(this.resourceBarcode ? this.resourceBarcode : '',
                [], (rb) =>
                    timer(waitToLoadResource).pipe(switchMap(() =>
                        this.pcrud.search('brsrc',
                            {'barcode' : rb.value},
                            {'limit': 1})),
                    single(),
                    mapTo(null),
                    catchError(() => of({ resourceBarcode: 'No resource found with that barcode' }))
                    )),
            'resourceType': new FormControl(),
            'startOfDay': new FormControl({hour: 9, minute: 0, second: 0}),
            'endOfDay': new FormControl({hour: 17, minute: 0, second: 0}),
            'idealDate': new FormControl(new Date()),
            'idealDateRange': new FormControl(defaultRange),
            'reservationType': new FormControl(),
            'owningLibrary': new FormControl({primaryOrgId: this.auth.user().ws_ou(), includeDescendants: true}),
            'selectedAttributes': new FormArray([]),
        }, [ startOfDayIsBeforeEndOfDayValidator
        ]);

        const debouncing = 1500;
        this.criteria.get('resourceBarcode').valueChanges
            .pipe(debounceTime(debouncing))
            .subscribe((barcode) => {
                this.resources = [];
                if ('INVALID' === this.criteria.get('resourceBarcode').status) {
                    this.toast.danger('No resource found with this barcode');
                } else {
                    this.router.navigate(['/staff', 'booking', 'create_reservation', 'for_resource', barcode]);
                }
            });

        this.subscriptions.push(
            this.resourceType.valueChanges.pipe(
                switchMap((value) => {
                    this.resourceBarcode = null;
                    this.resources = [];
                    this.resourceId = null;
                    this.attributes = [];
                    // TODO: when we upgrade to Angular 8, this can
                    // be simplified to this.selectedAttributes.clear();
                    while (this.selectedAttributes.length) {
                        this.selectedAttributes.removeAt(0);
                    }
                    if (value.id) {
                        return this.pcrud.search('bra', {resource_type : value.id}, {
                            order_by: 'name ASC',
                            flesh: 1,
                            flesh_fields: {'bra' : ['valid_values']}
                        }).pipe(
                            tap((attribute) => {
                                this.attributes.push(attribute);
                                this.selectedAttributes.push(new FormControl());
                            })
                        );
                    } else {
                        return of();
                    }
                })
            ).subscribe(() => this.fetchData()));

        this.criteria.get('reservationType').valueChanges.subscribe((val) => {
            this.multiday = ('multi' === val.id);
            this.store.setItem('eg.booking.create.multiday', this.multiday);
        });

        this.subscriptions.push(
            this.owningLibraryFamily.valueChanges
                .subscribe(() => this.resources = []));

        this.subscriptions.push(
            this.criteria.valueChanges
                .subscribe(() => this.fetchData()));

        this.store.getItem('eg.booking.create.multiday').then(multiday => {
            if (multiday) { this.multiday = multiday; }
            this.criteria.patchValue({reservationType:
                this.multiday ? this.reservationTypes[1] : this.reservationTypes[0]
            }, {emitEvent: false});
        });

        const minutesInADay = 1440;

        this.setGranularity = () => {
            if (this.multiday) { // multiday reservations always use day granularity
                this.granularity = minutesInADay;
            } else {
                this.store.getItem('eg.booking.create.granularity').then(granularity => {
                    if (granularity) {
                        this.granularity = granularity;
                    } else {
                        this.granularity = this.defaultGranularity;
                    }
                });
            }
        };

        this.criteria.get('idealDate').valueChanges
            .pipe(switchMap((date) => this.scheduleService.hoursOfOperation(date)))
            .subscribe({
                next: (hours) => this.criteria.patchValue(hours, {emitEvent: false}),
                error: () => {},
                complete: () => this.fetchData()
            });

        this.changeGranularity = ($event) => {
            this.granularity = $event.id;
            this.store.setItem('eg.booking.create.granularity', $event.id)
                .then(() => this.fetchData());
        };

        const minutesInAnHour = 60;

        this.minuteStep = () => {
            return (this.granularity < minutesInAnHour) ? this.granularity : this.defaultGranularity;
        };

        this.resourceAvailabilityIcon = (row: ScheduleRow) => {
            return this.scheduleService.resourceAvailabilityIcon(row,  this.resources.length);
        };
    }

    ngAfterViewInit() {
        this.fetchData();

        this.openTheDialog = (rows: IdlObject[]) => {
            if (rows && rows.length) {
                this.createDialog.setDefaultTimes(rows.map((row) => row['time'].clone()), this.granularity);
            }
            this.subscriptions.push(
                this.createDialog.open({size: 'lg'})
                    .subscribe(() => this.fetchData())
            );
        };
    }

    fetchData = (): void => {
        this.setGranularity();
        this.scheduleSource.data = [];
        let resources$ = this.scheduleService.fetchRelevantResources(
            this.resourceType.value ? this.resourceType.value.id : null,
            this.owningLibraries,
            this.flattenedSelectedAttributes
        );
        if (this.resourceId) {
            resources$ = of(this.resources[0]);
        } else {
            this.resources = [];
        }

        resources$.pipe(
            tap((resource) =>  {
                this.resources.push(resource);
                this.resources.sort((a, b) =>
                    (a.barcode() > b.barcode()) ? 1 : ((b.barcode() > a.barcode()) ? -1 : 0));
            }),
            takeLast(1),
            switchMap(() => {
                let range = {startTime: moment(), endTime: moment()};

                if (this.multiday) {
                    range = this.scheduleService.momentizeDateRange(
                        this.idealDateRange,
                        this.format.wsOrgTimezone
                    );
                } else {
                    range = this.scheduleService.momentizeDay(
                        this.idealDate,
                        this.userStartOfDay,
                        this.userEndOfDay,
                        this.format.wsOrgTimezone
                    );
                }
                this.scheduleSource.data = this.scheduleService.createBasicSchedule(
                    range, this.granularity);
                return this.scheduleService.fetchReservations(range, this.resources.map(r => r.id()));
            })
        ).subscribe({ next: (reservation) => {
            this.scheduleSource.data = this.scheduleService.addReservationToSchedule(
                reservation,
                this.scheduleSource.data,
                this.granularity,
                this.format.wsOrgTimezone
            );
        }, error: (err: unknown) => {
        }, complete: () => {
            this.cellTextGenerator = {
                'Time': row => {
                    return this.multiday ? row['time'].format('LT') :
                        this.format.transform({value: row['time'], datatype: 'timestamp', datePlusTime: true});
                }
            };
            this.resources.forEach(resource => {
                this.cellTextGenerator[resource.barcode()] = row =>  {
                    return row.patrons[resource.barcode()] ?
                        row.patrons[resource.barcode()].map(reservation => reservation['patronLabel']).join(', ') : '';
                };
            });
        } });
    };
    // TODO: make this into cross-field validation, and don't fetch data if true
    /* eslint-disable eqeqeq */
    invalidMultidaySettings(): boolean {
        return (this.multiday && (!this.idealDateRange ||
            (null == this.idealDateRange.fromDate) ||
            (null == this.idealDateRange.toDate)));
    }
    /* eslint-enable eqeqeq */

    handleBarcodeFromUrl$(barcode: string): Observable<any> {
        return this.findResourceByBarcode$(barcode)
            .pipe(
                catchError(() => this.handleBrsrcError$(barcode)),
                tap((resource) => {
                    if (resource) {
                        this.resourceId = resource.id();
                        this.criteria.patchValue({
                            resourceType: {id: resource.type()}},
                        {emitEvent: false});
                        this.resources = [resource];
                        this.details.select('select-resource');
                        this.fetchData();
                    }
                })
            );
    }

    findResourceByBarcode$(barcode: string): Observable<IdlObject> {
        return this.pcrud.search('brsrc',
            {'barcode' : barcode}, {'limit': 1})
            .pipe(single());
    }

    handleBrsrcError$(barcode: string): Observable<any> {
        return this.tryToMakeThisBookable$(barcode)
            .pipe(switchMap(() => this.findResourceByBarcode$(barcode)),
                catchError(() => {
                    this.toast.danger('No resource found with this barcode');
                    this.resourceId = -1;
                    return throwError('could not find or create a resource');
                }));
    }

    tryToMakeThisBookable$(barcode: string): Observable<any> {
        return this.pcrud.search('acp',
            {'barcode' : barcode}, {'limit': 1})
            .pipe(single(),
                switchMap((item) =>
                    this.net.request( 'open-ils.booking',
                        'open-ils.booking.resources.create_from_copies',
                        this.auth.token(), [item.id()])
                ),
                catchError(() => {
                    this.toast.danger('Cannot make this barcode bookable');
                    return throwError('Tried and failed to make that barcode bookable');
                }),
                tap((response) => {
                    this.toast.info('Made this barcode bookable');
                    this.resourceId = response['brsrc'][0][0];
                }));
    }

    addDays = (days: number): void => {
        const result = new Date(this.idealDate);
        result.setDate(result.getDate() + days);
        this.criteria.patchValue({idealDate: result});
    };

    openReservationViewer = (id: number): void => {
        this.viewReservation.mode = 'view';
        this.viewReservation.recordId = id;
        this.viewReservation.open({ size: 'lg' });
    };

    get resourceType() {
        return this.criteria.get('resourceType');
    }
    get userStartOfDay() {
        return this.criteria.get('startOfDay').value;
    }
    get userEndOfDay() {
        return this.criteria.get('endOfDay').value;
    }
    get idealDate() {
        return this.criteria.get('idealDate').value;
    }
    get idealDateRange() {
        return this.criteria.get('idealDateRange').value;
    }
    get owningLibraryFamily() {
        return this.criteria.get('owningLibrary');
    }
    get owningLibraries() {
        if (this.criteria.get('owningLibrary').value.orgIds) {
            return this.criteria.get('owningLibrary').value.orgIds;
        } else {
            return [this.criteria.get('owningLibrary').value.primaryOrgId];
        }
    }
    get selectedAttributes() {
        return <FormArray>this.criteria.get('selectedAttributes');
    }
    get flattenedSelectedAttributes(): number[] {
        return this.selectedAttributes.value.filter(Boolean).map((entry) => entry.id);
    }
    ngOnDestroy(): void {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

}

