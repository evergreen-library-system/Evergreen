import {Component, EventEmitter, Input, Output, OnChanges, OnInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Observable, from, of, tap, switchMap, mergeMap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {FormatService} from '@eg/core/format.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {NoTimezoneSetComponent} from './no-timezone-set.component';
import {ReservationActionsService} from './reservation-actions.service';
import {CancelReservationDialogComponent} from './cancel-reservation-dialog.component';

import * as moment from 'moment-timezone';

// A filterable grid of reservations used in various booking interfaces

@Component({
    selector: 'eg-reservations-grid',
    templateUrl: './reservations-grid.component.html',
})
export class ReservationsGridComponent implements OnChanges, OnInit {

    @Input() patron: number;
    @Input() resourceBarcode: string;
    @Input() resourceType: number;
    @Input() pickupLibIds: number[];
    @Input() status: 'capturedToday' | 'pickupReady' | 'pickedUp' | 'returnReady' | 'returnedToday';
    @Input() persistSuffix: string;
    @Input() onlyCaptured = false;

    @Output() pickedUpResource = new EventEmitter<IdlObject>();
    @Output() returnedResource = new EventEmitter<IdlObject>();

    gridSource: GridDataSource;
    patronBarcode: string;
    numRowsSelected: number;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('confirmCancelReservationDialog', { static: true })
    private cancelReservationDialog: CancelReservationDialogComponent;
    @ViewChild('noTimezoneSetDialog', { static: true }) noTimezoneSetDialog: NoTimezoneSetComponent;

    editSelected: (rows: IdlObject[]) => void;
    pickupSelected: (rows: IdlObject[]) => void;
    pickupResource: (rows: IdlObject) => Observable<any>;
    reprintCaptureSlip: (rows: IdlObject[]) => void;
    returnSelected: (rows: IdlObject[]) => void;
    returnResource: (rows: IdlObject) => Observable<any>;
    cancelSelected: (rows: IdlObject[]) => void;
    viewByPatron: (rows: IdlObject[]) => void;
    viewByResource: (rows: IdlObject[]) => void;
    viewItemStatus: (rows: IdlObject[]) => void;
    viewPatronRecord: (rows: IdlObject[]) => void;
    listReadOnlyFields: () => string;

    handleRowActivate: (row: IdlObject) => void;
    redirectToCreate: () => void;

    noSelectedRows: (rows: IdlObject[]) => boolean;
    notOnePatronSelected: (rows: IdlObject[]) => boolean;
    notOneResourceSelected: (rows: IdlObject[]) => boolean;
    notOneCatalogedItemSelected: (rows: IdlObject[]) => boolean;
    cancelNotAppropriate: (rows: IdlObject[]) => boolean;
    pickupNotAppropriate: (rows: IdlObject[]) => boolean;
    reprintNotAppropriate: (rows: IdlObject[]) => boolean;
    editNotAppropriate: (rows: IdlObject[]) => boolean;
    returnNotAppropriate: (rows: IdlObject[]) => boolean;

    constructor(
        private auth: AuthService,
        private format: FormatService,
        private pcrud: PcrudService,
        private router: Router,
        private toast: ToastService,
        private net: NetService,
        private org: OrgService,
        private actions: ReservationActionsService,
    ) {

    }

    ngOnInit() {
        if (!(this.format.wsOrgTimezone)) {
            this.noTimezoneSetDialog.open();
        }

        this.gridSource = new GridDataSource();

        this.gridSource.getRows = (pager: Pager, sort: any[]): Observable<IdlObject> => {
            const orderBy: any = {};
            const where = {
                'usr' : (this.patron ? this.patron : {'>' : 0}),
                'target_resource_type' : (this.resourceType ? this.resourceType : {'>' : 0}),
                'cancel_time' : null,
                'xact_finish' : null,
            };
            if (this.resourceBarcode) {
                where['current_resource'] = {'in':
                    {'from': 'brsrc', 'select': {'brsrc': ['id']}, 'where': {'barcode': this.resourceBarcode}}};
            }
            if (this.pickupLibIds) {
                where['pickup_lib'] = this.pickupLibIds;
            }
            if (this.onlyCaptured) {
                where['capture_time'] = {'!=': null};
            }

            if (this.status) {
                if ('pickupReady' === this.status) {
                    where['pickup_time'] = null;
                    where['start_time'] = {'!=': null};
                } else if ('pickedUp' === this.status || 'returnReady' === this.status) {
                    where['pickup_time'] = {'!=': null};
                    where['return_time'] = null;
                } else if ('returnedToday' === this.status) {
                    where['return_time'] = {'>': moment().startOf('day').toISOString()};
                } else if ('capturedToday' === this.status) {
                    where['capture_time'] = {'between': [moment().startOf('day').toISOString(),
                        moment().add(1, 'day').startOf('day').toISOString()]};
                }
            } else {
                where['return_time'] = null;
            }
            if (sort.length) {
                orderBy.bresv = sort[0].name + ' ' + sort[0].dir;
            }
            return this.pcrud.search('bresv', where,  {
                order_by: orderBy,
                limit: pager.limit,
                offset: pager.offset,
                flesh: 2,
                flesh_fields: {'bresv' : [
                    'usr', 'capture_staff', 'target_resource', 'target_resource_type', 'current_resource', 'request_lib', 'pickup_lib'
                ], 'au': ['card'] }
            }).pipe(mergeMap((row) => this.enrichRow$(row)));
        };

        this.editDialog.mode = 'update';
        this.editSelected = (idlThings: IdlObject[]) => {
            const editOneThing = (thing: IdlObject) => {
                if (!thing) { return; }
                this.showEditDialog(thing).then(
                    () => editOneThing(idlThings.shift()));
            };
            editOneThing(idlThings.shift());
        };

        this.cancelSelected = (reservations: IdlObject[]) => {
            this.cancelReservationDialog.open(reservations.map(reservation => reservation.id()));
        };

        this.viewByResource = (reservations: IdlObject[]) => {
            this.actions.manageReservationsByResource(reservations[0].current_resource().barcode());
        };

        this.viewByPatron = (reservations: IdlObject[]) => {
            const patronIds = reservations.map(reservation => reservation.usr().id());
            this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_patron', patronIds[0]]);
        };

        this.viewItemStatus = (reservations: IdlObject[]) => {
            this.actions.viewItemStatus(reservations[0].current_resource().barcode());
        };

        this.viewPatronRecord = (reservations: IdlObject[]) => {
            const patronIds = reservations.map(reservation => reservation.usr().id());
            window.open('/eg/staff/circ/patron/' + patronIds[0] + '/checkout');
        };

        this.noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);
        this.notOnePatronSelected = (rows: IdlObject[]) => this.actions.notOneUniqueSelected(rows.map(row => row.usr().id()));
        this.notOneResourceSelected = (rows: IdlObject[]) => {
            return this.actions.notOneUniqueSelected(
                rows.map(row => { if (row.current_resource()) { return row.current_resource().id(); }}));
        };
        this.notOneCatalogedItemSelected = (rows: IdlObject[]) => {
            return this.actions.notOneUniqueSelected(
                rows.filter(row => (row.current_resource() && 't' === row.target_resource_type().catalog_item()))
                    .map(row => row.current_resource().id())
            );
        };
        this.cancelNotAppropriate = (rows: IdlObject[]) =>
            (this.noSelectedRows(rows) || ['pickedUp', 'returnReady', 'returnedToday'].includes(this.status));
        this.pickupNotAppropriate = (rows: IdlObject[]) =>
            (this.noSelectedRows(rows) || !('pickupReady' === this.status || 'capturedToday' === this.status));
        this.editNotAppropriate = (rows: IdlObject[]) => (this.noSelectedRows(rows) || ('returnedToday' === this.status));
        this.reprintNotAppropriate = (rows: IdlObject[]) => {
            if (this.noSelectedRows(rows)) {
                return true;
            } else if ('capturedToday' === this.status) {
                return false;
            } else if (rows.filter(row => !(row.capture_time())).length) { // If any of the rows have not been captured
                return true;
            }
            return false;
        };
        this.returnNotAppropriate = (rows: IdlObject[]) => {
            if (this.noSelectedRows(rows)) {
                return true;
            } else if (this.status && ('pickupReady' === this.status || 'capturedToday' === this.status)) {
                return true;
            } else {
                rows.forEach(row => {
                    // eslint-disable-next-line eqeqeq
                    if ((null == row.pickup_time()) || row.return_time()) { return true; }
                });
            }
            return false;
        };

        this.pickupSelected = (reservations: IdlObject[]) => {
            const pickupOne = (thing: IdlObject) => {
                if (!thing) { return; }
                this.pickupResource(thing).subscribe(
                    () => pickupOne(reservations.shift()));
            };
            pickupOne(reservations.shift());
        };

        this.returnSelected = (reservations: IdlObject[]) => {
            const returnOne = (thing: IdlObject) => {
                if (!thing) { return; }
                this.returnResource(thing).subscribe(
                    () => returnOne(reservations.shift()));
            };
            returnOne(reservations.shift());
        };

        this.reprintCaptureSlip = (reservations: IdlObject[]) => {
            this.actions.reprintCaptureSlip(reservations.map((r) => r.id())).subscribe();
        };

        this.pickupResource = (reservation: IdlObject) => {
            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.reservation.pickup',
                this.auth.token(),
                {'patron_barcode': reservation.usr().card().barcode(), 'reservation': reservation})
                .pipe(tap(
                    () => {
                        this.pickedUpResource.emit(reservation);
                        this.grid.reload();
                    },
                ));
        };

        this.returnResource = (reservation: IdlObject) => {
            return this.net.request(
                'open-ils.circ',
                'open-ils.circ.reservation.return',
                this.auth.token(),
                {'patron_barcode': this.patronBarcode, 'reservation': reservation})
                .pipe(tap(
                    () => {
                        this.returnedResource.emit(reservation);
                        this.grid.reload();
                    },
                ));
        };

        this.listReadOnlyFields = () => {
            let list = 'usr,xact_start,request_time,capture_time,pickup_time,return_time,capture_staff,target_resource_type,' +
                'email_notify,current_resource,target_resource,unrecovered,request_lib,pickup_lib,fine_interval,fine_amount,max_fine';
            if (this.status && ('pickupReady' !== this.status)) { list = list + ',start_time'; }
            if (this.status && ('returnedToday' === this.status)) { list = list + ',end_time'; }
            return list;
        };

        this.handleRowActivate = (row: IdlObject) => {
            if (this.status) {
                if ('returnReady' === this.status) {
                    this.returnResource(row).subscribe();
                } else if ('pickupReady' === this.status) {
                    this.pickupResource(row).subscribe();
                } else if ('returnedToday' === this.status) {
                    this.toast.warning('Cannot edit this reservation');
                } else {
                    this.showEditDialog(row);
                }
            } else {
                this.showEditDialog(row);
            }
        };

        this.redirectToCreate = () => {
            this.router.navigate(['/staff', 'booking', 'create_reservation']);
        };
    }

    ngOnChanges() { this.reloadGrid(); }

    reloadGrid() { this.grid.reload(); }

    enrichRow$ = (row: IdlObject): Observable<IdlObject> => {
        return from(this.org.settings('lib.timezone', row.pickup_lib().id())).pipe(
            switchMap((tz) => {
                row['length'] = moment(row['end_time']()).from(moment(row['start_time']()), true);
                row['timezone'] = tz['lib.timezone'];
                return of(row);
            })
        );
    };

    showEditDialog(idlThing: IdlObject) {
        this.editDialog.recordId = idlThing.id();
        this.editDialog.timezone = idlThing['timezone'];
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
                { next: ok => {
                    this.toast.success('Reservation successfully updated'); // TODO: needs i18n, pluralization
                    this.grid.reload();
                    resolve(ok);
                }, error: (rejection: unknown) => {} }
            );
        });
    }

    filterByResourceBarcode(barcode: string) {
        this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_resource', barcode]);
    }

    momentizeIsoString(isoString: string, timezone: string): moment.Moment {
        return this.format.momentizeIsoString(isoString, timezone);
    }
}

