import {Component, OnInit, ViewChild} from '@angular/core';
import {FormControl, FormGroup, Validators} from '@angular/forms';
import {from, Observable, of} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ReservationActionsService} from './reservation-actions.service';
import {CancelReservationDialogComponent} from './cancel-reservation-dialog.component';

// The data that comes from the API, along with some fleshing
interface PullListRow {
    call_number?: string;
    call_number_sortkey?: string;
    current_resource: IdlObject;
    reservations: IdlObject[];
    shelving_location?: string;
    target_resource_type: IdlObject;
}

@Component({
    templateUrl: './pull-list.component.html'
})

export class PullListComponent implements OnInit {
    @ViewChild('confirmCancelReservationDialog', { static: true })
        private cancelReservationDialog: CancelReservationDialogComponent;

    public dataSource: GridDataSource;

    public disableOrgs: () => number[];
    public fillGrid: (orgId?: number) => void;
    pullListCriteria: FormGroup;

    constructor(
        private auth: AuthService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private actions: ReservationActionsService,
    ) { }


    ngOnInit() {
        this.dataSource = new GridDataSource();

        const defaultDaysHence = 5;

        this.pullListCriteria = new FormGroup({
            'daysHence': new FormControl(defaultDaysHence, [
                Validators.required,
                Validators.min(1)])
        });

        this.pullListCriteria.valueChanges.subscribe(() => this.fillGrid() );

        this.disableOrgs = () => this.org.filterList( { canHaveVolumes : false }, true);

        this.fillGrid = (orgId = this.auth.user().ws_ou()) => {
            this.dataSource.data = [];
            const numberOfSecondsInADay = 86400;
            this.net.request(
                'open-ils.booking', 'open-ils.booking.reservations.get_pull_list',
                this.auth.token(), null,
                (this.daysHence.value * numberOfSecondsInADay),
                orgId
            ).pipe(switchMap((resources) => from(resources)),
                switchMap((resource: PullListRow) => this.fleshResource(resource))
            )
            .subscribe((resource) => this.dataSource.data.push(resource));
        };
    }

    noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);

    notOneResourceSelected = (rows: IdlObject[]) => {
        return this.actions.notOneUniqueSelected(
            rows.map(row => { if (row['current_resource']) { return row['current_resource']['id']; }}));
    }

    notOneCatalogedItemSelected = (rows: IdlObject[]) => {
        return this.actions.notOneUniqueSelected(
            rows.filter(row => (row['current_resource'] && row['call_number']))
            .map(row => row['current_resource'].id())
        );
    }

    cancelSelected = (rows: IdlObject[]) => {
        this.cancelReservationDialog.open(rows.map(row => row['reservations'][0].id()));
    }

    fleshResource = (resource: PullListRow): Observable<PullListRow> => {
        if ('t' === resource['target_resource_type'].catalog_item()) {
            return this.pcrud.search('acp', {
                'barcode': resource['current_resource'].barcode()
                }, {
                    limit: 1,
                    flesh: 1,
                    flesh_fields: {'acp' : ['call_number', 'location' ]}
            }).pipe(switchMap((acp) => {
                resource['call_number'] = acp.call_number().label();
                resource['call_number_sortkey'] = acp.call_number().label_sortkey();
                resource['shelving_location'] = acp.location().name();
                return of(resource);
            }));
        } else {
            return of(resource);
        }
    }

    viewByResource = (reservations: IdlObject[]) => {
        this.actions.manageReservationsByResource(reservations[0]['current_resource'].barcode());
    }

    viewItemStatus = (reservations: IdlObject[]) => {
        this.actions.viewItemStatus(reservations[0]['current_resource'].barcode());
    }

    get daysHence() {
        return this.pullListCriteria.get('daysHence');
    }

}

