import { Component, ElementRef, inject, OnInit, ViewChild, effect, Signal, computed } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { GridCellTextGenerator, GridDataSource } from '@eg/share/grid/grid';
import { of, from, toArray, switchMap, tap, Observable, throwError, catchError, EMPTY, defaultIfEmpty } from 'rxjs';
import { PcrudService, PcrudReqOps } from '@eg/core/pcrud.service';
import { GridComponent } from '@eg/share/grid/grid.component';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { PatronSearchDialogComponent } from '@eg/staff/share/patron/search-dialog.component';
import { PatronModule } from '@eg/staff/share/patron/patron.module';
import { HoldGroupInfoComponent } from '../hold-group-info/hold-group-info.component';
import { HoldGroupsService } from '../hold-groups.service';
import { AlertDialogComponent } from '@eg/share/dialog/alert.component';
import { ConfirmDialogComponent } from '@eg/share/dialog/confirm.component';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-hold-group-users',
    standalone: true,
    imports: [
        StaffCommonModule,
        PatronModule,
        HoldGroupInfoComponent
    ],
    templateUrl: './hold-group-users.component.html',
    styleUrl: './hold-group-users.component.css'
})
export class HoldGroupUsersComponent implements OnInit {
    private pcrud = inject(PcrudService);
    private net = inject(NetService);
    private auth = inject(AuthService);
    protected hg = inject(HoldGroupsService);

    @ViewChild('patronSearch', {static: false}) patronSearch!: PatronSearchDialogComponent;
    @ViewChild('selectHoldGroup', {static: false}) selectHoldGroupDialog!: ConfirmDialogComponent;
    @ViewChild('duplicatePatronAlert') duplicatePatronDialog!: AlertDialogComponent;
    duplicatePatrons: IdlObject[] = [];

    dataSource!: GridDataSource;
    @ViewChild('grid', {static: true}) grid!: GridComponent;
    @ViewChild('barcodeInput', {static: true}) barcodeInput!: ElementRef;

    cellTextGenerator: GridCellTextGenerator = {
        'group': (row: IdlObject) => row.group()?.name(),
        'card': (row: IdlObject) => row.card()?.barcode(),
        'mailing_address': (row: IdlObject) => row.mailing_address()
    };

    idlClass = 'au';

    barcodeValue = '';
    barcodeError = '';

    protected patronTransferSelectedBucket?: ComboboxEntry;
    protected patronTransferIdlBaseQuery: Signal<any> = computed(() => {
        return {
            btype: 'hold_subscription',
            'id': {'!=': this.hg.userBucketId()}
        };
    });

    constructor() {
        effect(() => {
            this.hg.userBucket(); // You have to put signals in the effect to run the code when they change.
            this.grid.reload();
        });
    }

    ngOnInit(): void {
        this.initDataSource();
    }

    initDataSource() {
        this.dataSource = new GridDataSource();
        this.dataSource.getRows = (pager, sort) => {

            if (!this.hg.userBucketId()) {
                return from([]);
            }

            const order_by: any = {};
            if (sort.length) {
                // Sort specified from grid
                order_by[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            }

            const pcrudOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: order_by,
                flesh: 1,
                flesh_fields: {'au': ['card']}
            };
            const reqOps: PcrudReqOps = {'fleshSelectors': true};

            return this.pcrud.search('cubi', {bucket: this.hg.userBucketId()}, {}, {}).pipe(
                toArray(),
                switchMap((cubis: IdlObject[]) => {
                    if (!cubis || cubis.length === 0) {
                        return from([]);
                    }
                    return this.pcrud.search('au', {id: cubis.map(cubi => cubi?.target_user?.())}, pcrudOps, reqOps);
                })
            );
        };
    }

    hasNoSelectedUsers() : boolean {
        return this.grid.context.getSelectedRows().length === 0;
    }

    removeSelectedUsers(userIds?: number[]): Observable<any> {

        if (userIds === undefined) {
            userIds = this.grid.context.getSelectedRows().map((row: IdlObject) => row.id());
        }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete.batch',
            this.auth.token(),
            'user',
            this.hg.userBucketId(),
            userIds
        ).pipe(
            catchError((err) => this.barcodeError = err),
            tap((res) => {this.hg.reloadUserBucket();})
        );
    }

    addUserByBarcode(): Observable<any> {
        this.barcodeError = '';
        if (!this.hg.userBucketId()) {
            this.barcodeError = $localize`Please select a hold group before adding users.`;
            return throwError(() => new Error('No hold group selected'));
        }
        return this.pcrud.search(
            'ac',
            {barcode: this.barcodeValue},
            {flesh: 2, flesh_fields: {ac: ['usr'], au: ['home_ou']}}
        ).pipe(
            catchError((err) => {
                console.log('Error searching for user by barcode', err);
                this.barcodeError = $localize`Unable to find user with barcode '${this.barcodeValue}'`;
                return of(null); // Return null to indicate no user found
            }),
            defaultIfEmpty(null),
            switchMap((response: IdlObject) => {
                if (!response) {
                    this.barcodeError = $localize`Unable to find user with barcode '${this.barcodeValue}'`;
                    return of(null);
                }
                this.barcodeError = '';
                this.barcodeValue = '';
                return this.addUserIdsToHoldGroup([response.usr().id()]);
            })
        );
    }

    addUsersToHoldGroup(users: IdlObject[], bucketId?: number): Observable<any> {
        return this.addUserIdsToHoldGroup(users.map(user => user.id()), bucketId);

    }

    addUserIdsToHoldGroup(userIds: number[], bucketId?: number): Observable<any> {
        this.barcodeError = '';
        if (!bucketId){
            bucketId = this.hg.userBucketId() ?? undefined;
        }

        if (!bucketId) {
            this.barcodeError = $localize`Please select a hold group before adding users.`;
            return throwError(() => new Error('No hold group selected'));
        }

        const existingItems$: Observable<IdlObject[]> = (bucketId === this.hg.userBucketId())
            ? of(this.hg?.userBucket()?.items() || [])
            : this.pcrud.search(
                'cubi',
                { bucket: bucketId },
                { flesh: 3, flesh_fields: { 'cubi': ['target_user'], 'au': ['card'] } }
            )
                .pipe(toArray());

        return existingItems$.pipe(
            switchMap((existingItems: IdlObject[])=> {
                const duplicates = existingItems
                    .filter(item => userIds.includes(item.target_user().id()))
                    .map(item => item.target_user());

                if (duplicates.length > 0) {
                    this.duplicatePatrons = duplicates;
                    this.duplicatePatronDialog.open();
                    return EMPTY;
                }

                return this.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.item.create.batch',
                    this.auth.token(),
                    'user',
                    bucketId,
                    userIds
                ).pipe(
                    catchError((err) => {
                        console.log('Error adding users to hold group', err);
                        this.barcodeError = $localize`Error adding users to hold group. Please try again.`;
                        return throwError(() => err);
                    }),
                    tap({
                        complete: () => {
                            this.hg.reloadUserBucket();
                        }
                    })
                );
            })
        );

    }

    addFromSearchDialog() {

        this.patronSearch.open({size: 'xl', animation: true}).pipe(
            switchMap((patrons: IdlObject[]) => {
                if (patrons.length === 0) {
                    return of(null);
                }
                return this.addUserIdsToHoldGroup(patrons.map(patron => patron.id()));
            })
        ).subscribe();
    }

    copySelectedUsers(removeFromCurrentBucket = false): Observable<any> {
        const userCount = this.grid.context.getSelectedRows().length;
        this.selectHoldGroupDialog.dialogTitle = removeFromCurrentBucket
            ? $localize`Move ${userCount} User(s) to which Hold Group?`
            : $localize`Copy ${userCount} User(s) to which Hold Group?`;

        const users = this.grid.context.getSelectedRows();

        return this.selectHoldGroupDialog.open({animation: true}).pipe(
            switchMap((proceed: boolean) => {
                return proceed ? this.addUsersToHoldGroup(users, this.patronTransferSelectedBucket?.id): EMPTY;
            }),
            toArray(),
            switchMap((res: number[]) => {
                if (removeFromCurrentBucket && res?.length > 0) {
                    return this.removeSelectedUsers(res);
                } else {
                    return of(res);
                }
            })
        );
    }
}
