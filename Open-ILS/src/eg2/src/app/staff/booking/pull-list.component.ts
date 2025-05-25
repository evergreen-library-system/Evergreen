import {Component, OnInit, ViewChild} from '@angular/core';
import {FormControl, FormGroup, Validators} from '@angular/forms';
import {Observable, of, from, switchMap, mergeMap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ReservationActionsService} from './reservation-actions.service';
import {CancelReservationDialogComponent} from './cancel-reservation-dialog.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';

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

    @ViewChild('pullList', { static: true }) private pullList: GridComponent;

    public dataSource: GridDataSource = new GridDataSource();

    public disableOrgs: () => number[];
    public handleOrgChange: (org: IdlObject) => void;

    currentOrg: number;
    pullListCriteria: FormGroup;

    constructor(
        private auth: AuthService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private actions: ReservationActionsService,
    ) { }


    ngOnInit() {

        const defaultDaysHence = 5;
        this.currentOrg = this.auth.user().ws_ou();

        this.pullListCriteria = new FormGroup({
            'daysHence': new FormControl(defaultDaysHence, [
                Validators.required,
                Validators.min(1)])
        });

        this.pullListCriteria.valueChanges.subscribe(() => this.pullList.reload() );

        this.disableOrgs = () => this.org.filterList( { canHaveVolumes : false }, true);

        this.handleOrgChange = (org: IdlObject) => {
            this.currentOrg = org.id();
            this.pullList.reload();
        };

        this.dataSource.getRows = (pager: Pager) => {
            const numberOfSecondsInADay = 86400;
            return this.net.request(
                'open-ils.booking', 'open-ils.booking.reservations.get_pull_list',
                this.auth.token(), null,
                (this.daysHence.value * numberOfSecondsInADay),
                this.currentOrg
            ).pipe(switchMap(arr => from(arr)), // Change the array we got into a stream
                mergeMap(resource => this.fleshResource$(resource)) // Add info for cataloged resources
            );
        };
    }

    noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);

    notOneResourceSelected = (rows: IdlObject[]) => {
        return this.actions.notOneUniqueSelected(
            rows.map(row => { if (row['current_resource']) { return row['current_resource']['id']; }}));
    };

    notOneCatalogedItemSelected = (rows: IdlObject[]) => {
        return this.actions.notOneUniqueSelected(
            rows.filter(row => (row['current_resource'] && row['call_number']))
                .map(row => row['current_resource'].id())
        );
    };

    cancelSelected = (rows: IdlObject[]) => {
        this.cancelReservationDialog.open(rows.map(row => row['reservations'][0].id()));
    };

    fleshResource$ = (resource: any): Observable<PullListRow> => {
        if ('t' === resource['target_resource_type'].catalog_item()) {
            return this.pcrud.search('acp', {
                'barcode': resource['current_resource'].barcode()
            }, {
                limit: 1,
                flesh: 1,
                flesh_fields: {'acp' : ['call_number', 'location' ]}
            }).pipe(mergeMap((acp) => {
                resource['call_number'] = acp.call_number().label();
                resource['call_number_sortkey'] = acp.call_number().label_sortkey();
                resource['shelving_location'] = acp.location().name();
                return of(resource);
            }));
        } else {
            return of(resource);
        }
    };

    viewByResource = (reservations: IdlObject[]) => {
        this.actions.manageReservationsByResource(reservations[0]['current_resource'].barcode());
    };

    viewItemStatus = (reservations: IdlObject[]) => {
        this.actions.viewItemStatus(reservations[0]['current_resource'].barcode());
    };

    get daysHence() {
        return this.pullListCriteria.get('daysHence');
    }

}

