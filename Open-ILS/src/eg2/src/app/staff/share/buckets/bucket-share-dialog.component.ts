/* eslint-disable no-empty */
import {Component, Input, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {Subscription, Observable, of, from, firstValueFrom} from 'rxjs';
import {tap} from 'rxjs/operators';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {Tree, TreeNode} from '@eg/share/tree/tree';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
// import {FormatService} from '@eg/core/format.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {PatronSearchDialogComponent} from '@eg/staff/share/patron/search-dialog.component';
import {BucketUserShareComponent} from '@eg/staff/share/buckets/bucket-user-share.component';
import {Pager} from '@eg/share/util/pager';
import {ToastService} from '@eg/share/toast/toast.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    selector: 'eg-bucket-share-dialog',
    templateUrl: './bucket-share-dialog.component.html'
})

export class BucketShareDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    subscriptions: Subscription[] = []; // unsubscribed from in ngOnDestroy

    activeTabId = 1; // User Sharing Tab

    cellTextGeneratorViewPermGrid: GridCellTextGenerator;
    cellTextGeneratorEditPermGrid: GridCellTextGenerator;
    dataSourceViewPermGrid: GridDataSource = new GridDataSource();
    dataSourceEditPermGrid: GridDataSource = new GridDataSource();
    @Input() usersViewPermGrid: IdlObject[] = [];
    @Input() usersEditPermGrid: IdlObject[] = [];
    @Input() shareTree: Tree;
    @Input() containerObjects: any[];

    @ViewChild('fail', { static: true }) fail: AlertDialogComponent;
    @ViewChild('confirm', { static: true }) confirm: ConfirmDialogComponent;
    @ViewChild('patronSearch') patronSearch: PatronSearchDialogComponent;

    // ViewChild doesn't work in this context
    userShareViewPermGrid: BucketUserShareComponent;
    userShareEditPermGrid: BucketUserShareComponent;

    _original_orgs = [];
    _original_view_users = [];
    _original_edit_users = [];

    shareUsersDisabledViewPermGrid = true;
    shareUsersDisabledEditPermGrid = true;
    shareOrgsDisabled = true;

    users_touchedViewPermGrid = false;
    users_touchedEditPermGrid = false;
    orgsTouched = false;

    constructor(
        private auth: AuthService,
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private idl: IdlService,
        private modal: NgbModal,
        private toast: ToastService
    ) {
        super(modal);
        if (this.modal) {} // de-lint
    }

    async ngOnInit() {
        console.debug('BucketShareDialogComponent, this',this);
        await this.initAuGridViewPermGrid();
        await this.initAuGridEditPermGrid();
        if (!this.shareTree) {
            console.debug('BucketShareDialogComponent, loading org tree');
            await this.loadAouTree();
        }
    }

    async initialize() {
        if (this.containerObjects?.length) {
            console.debug('BucketShareDialogComponent, initialize, loading org share maps');
            await this.populateCheckedNodes();
        } else {
            console.error('BucketShareDialogComponent, initialize, no containers');
        }
    }

    ngOnDestroy() {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

    trickeryViewPermGrid = (that: any) => {
        console.debug('trickeryViewPermGrid, that', that);
        this.userShareViewPermGrid = that;
    };

    trickeryEditPermGrid = (that: any) => {
        console.debug('trickeryEditPermGrid, that', that);
        this.userShareEditPermGrid = that;
    };

    async loadAuGridViewPermGrid(): Promise<any> {
        this.usersViewPermGrid = [];
        this.users_touchedViewPermGrid = false;

        const userIds = await firstValueFrom(
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.user_share.retrieve',
                this.auth.token(),
                'biblio',
                this.containerObjects.map(o => o.id),
                'VIEW_CONTAINER'
            )
        );

        const evt = this.evt.parse(userIds);
        this.usersViewPermGrid = [];
        this._original_view_users = [];
        console.debug('resetting this._original_view_users', this._original_view_users );
        if (evt) {
            console.error(evt.toString());
            this.fail.dialogBody = evt.toString();
            this.fail.open();
            return;
        } else if (!userIds.length) {
            return;
        } else {
            this.usersViewPermGrid = await firstValueFrom( this.pcrud.search('au',
                {id: userIds},
                {flesh: 1, flesh_fields: {au: ['card']}},
                {atomic: true, authoritative: true})
            );
            this._original_view_users = this.idl.clone( this.usersViewPermGrid );
            console.debug('populating this._original_view_users', this._original_view_users );
            this.userShareViewPermGrid?.reload();
        }
    }

    async loadAuGridEditPermGrid(): Promise<any> {
        this.usersEditPermGrid = [];
        this.users_touchedEditPermGrid = false;

        const userIds = await firstValueFrom(
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.user_share.retrieve',
                this.auth.token(),
                'biblio',
                this.containerObjects.map(o => o.id),
                'UPDATE_CONTAINER'
            )
        );

        const evt = this.evt.parse(userIds);
        this.usersEditPermGrid = [];
        this._original_edit_users = [];
        console.debug('resetting this._original_edit_users', this._original_edit_users );
        if (evt) {
            console.error(evt.toString());
            this.fail.dialogBody = evt.toString();
            this.fail.open();
            return;
        } else if (!userIds.length) {
            return;
        } else {
            this.usersEditPermGrid = await firstValueFrom( this.pcrud.search('au',
                {id: userIds},
                {flesh: 1, flesh_fields: {au: ['card']}},
                {atomic: true, authoritative: true})
            );
            this._original_edit_users = this.idl.clone( this.usersEditPermGrid );
            console.debug('populating this._original_edit_users', this._original_edit_users );
            this.userShareEditPermGrid?.reload();
        }
    }

    async initAuGridViewPermGrid(): Promise<any> {
        this.dataSourceViewPermGrid.getRows = (pager: Pager, sort: any[]) =>
            from(this.usersViewPermGrid.slice(pager.offset, pager.offset + pager.limit));

        this.cellTextGeneratorViewPermGrid = {
            'barcode': (user: IdlObject) => user.card().barcode(),
            'username': (user: IdlObject) => user.usrname(),
            'name': (user: IdlObject) => user.family_name() + ', ' + user.first_given_name()
        };
    }

    async initAuGridEditPermGrid(): Promise<any> {
        this.dataSourceEditPermGrid.getRows = (pager: Pager, sort: any[]) =>
            from(this.usersEditPermGrid.slice(pager.offset, pager.offset + pager.limit));

        this.cellTextGeneratorEditPermGrid = {
            'barcode': (user: IdlObject) => user.card().barcode(),
            'username': (user: IdlObject) => user.usrname(),
            'name': (user: IdlObject) => user.family_name() + ', ' + user.first_given_name()
        };
    }

    isSharingAllowedViewPermGrid(): boolean {
        // get the selected IDs
        const currently_selected = this.usersViewPermGrid;
        console.debug('dialog: isSharingAllowedViewPermGrid(), _original_view_users', this._original_view_users);
        console.debug('dialog: isSharingAllowedViewPermGrid(), currently_selected', currently_selected);

        // see if the list lengths are different (changed!)
        if (currently_selected.length !== this._original_view_users.length) {
            console.debug('dialog: isSharingAllowedViewPermGrid(), original.length != current.length, so allow save');
            return true;
        }

        // same length, but both 0, nope
        if (currently_selected.length === 0) {
            console.debug('dialog: isSharingAllowedViewPermGrid(), original.length == current.length, but length == 0, so no save');
            return false;
        }

        // see if the sorted values are all the same (unchanged); == because number vs number as string
        if (currently_selected
            .sort((a: IdlObject, b: IdlObject) => a.id() - b.id() )
            // eslint-disable-next-line eqeqeq
            .every((e,i) => e.id() == this._original_view_users.sort()[i].id())) {
            console.debug('dialog: isSharingAllowedViewPermGrid(), all elements match, so no save');
            return false;
        }

        // no? it changed, allow
        console.debug('dialog: isSharingAllowedViewPermGrid(), fell through all tests, so allow save');
        return true;
    }

    isSharingAllowedEditPermGrid(): boolean {
        // get the selected IDs
        const currently_selected = this.usersEditPermGrid;
        console.debug('dialog: isSharingAllowedEditPermGrid(), _original_edit_users', this._original_edit_users);
        console.debug('dialog: isSharingAllowedEditPermGrid(), currently_selected', currently_selected);

        // see if the list lengths are different (changed!)
        if (currently_selected.length !== this._original_edit_users.length) {
            console.debug('dialog: isSharingAllowedEditPermGrid(), original.length != current.length, so allow save');
            return true;
        }

        // same length, but both 0, nope
        if (currently_selected.length === 0) {
            console.debug('dialog: isSharingAllowedEditPermGrid(), original.length == current.length, but length == 0, so no save');
            return false;
        }

        // see if the sorted values are all the same (unchanged); == because number vs number as string
        if (currently_selected
            .sort((a: IdlObject, b: IdlObject) => a.id() - b.id() )
            // eslint-disable-next-line eqeqeq
            .every((e,i) => e.id() == this._original_edit_users.sort()[i].id())) {
            console.debug('dialog: isSharingAllowedEditPermGrid(), all elements match, so no save');
            return false;
        }

        // no? it changed, allow
        console.debug('dialog: isSharingAllowedEditPermGrid(), fell through all tests, so allow save');
        return true;
    }

    addUsersViewPermGrid = () => {
        this.patronSearch.open({size: 'xl'}).toPromise().then(
            users => {
                console.debug('patronSearch, result', users);
                if (!users || users.length === 0) { return; }

                const newUsers = users.filter(user => {
                    return !this.usersViewPermGrid.some(existingUser => existingUser.id() === user.id());
                });

                this.usersViewPermGrid.push(...newUsers);
                this.userShareViewPermGrid.reload();
                this.shareUsersDisabledViewPermGrid = !this.isSharingAllowedViewPermGrid();
                this.users_touchedViewPermGrid = !this.shareUsersDisabledViewPermGrid;
                console.debug('Added new users:', newUsers);
            }
        );
    };

    addUsersEditPermGrid = () => {
        this.patronSearch.open({size: 'xl'}).toPromise().then(
            users => {
                console.debug('patronSearch, result', users);
                if (!users || users.length === 0) { return; }

                const newUsers = users.filter(user => {
                    return !this.usersEditPermGrid.some(existingUser => existingUser.id() === user.id());
                });

                this.usersEditPermGrid.push(...newUsers);
                this.userShareEditPermGrid.reload();
                this.shareUsersDisabledEditPermGrid = !this.isSharingAllowedEditPermGrid();
                this.users_touchedEditPermGrid = !this.shareUsersDisabledEditPermGrid;
                console.debug('Added new users:', newUsers);
            }
        );
    };

    removeUsersViewPermGrid = (rows: any[]) => {
        console.debug('removeUsers, rows', rows);
        if (!rows || rows.length === 0) { return; }
        const userIdsToRemove = new Set(rows.map(user => user.id()));
        this.usersViewPermGrid = this.usersViewPermGrid.filter(user => !userIdsToRemove.has(user.id()));
        this.userShareViewPermGrid.reload();
        this.shareUsersDisabledViewPermGrid = !this.isSharingAllowedViewPermGrid();
        this.users_touchedViewPermGrid = !this.shareUsersDisabledViewPermGrid;
    };

    removeUsersEditPermGrid = (rows: any[]) => {
        console.debug('removeUsers, rows', rows);
        if (!rows || rows.length === 0) { return; }
        const userIdsToRemove = new Set(rows.map(user => user.id()));
        this.usersEditPermGrid = this.usersEditPermGrid.filter(user => !userIdsToRemove.has(user.id()));
        this.userShareEditPermGrid.reload();
        this.shareUsersDisabledEditPermGrid = !this.isSharingAllowedEditPermGrid();
        this.users_touchedEditPermGrid = !this.shareUsersDisabledEditPermGrid;
    };

    async shareBucketsWithUsersViewPermGrid(): Promise<void> {
        console.debug('shareBucketsWithUsers()');
        this.shareUsersDisabledViewPermGrid = !this.isSharingAllowedViewPermGrid();
        if (this.shareUsersDisabledViewPermGrid) { return; }
        const userIds: number[] = [];

        try {
            await firstValueFrom(new Observable<void>(observer => {
                this.userShareViewPermGrid.getGrid().context.getAllRowsAsText().subscribe({
                    next: row => {
                        console.debug('shareBucketsWithUsers, row', row);
                        if (row.id) {
                            userIds.push(row.id);
                        }
                    },
                    error: (err: unknown) => {
                        console.debug('shareBucketsWithUsers, err', err);
                        observer.error(err);
                    },
                    complete: () => {
                        console.debug('shareBucketsWithUsers, complete');
                        observer.next(); // firstValueFrom needs an emission
                        observer.complete();
                    }
                });
            }));
            console.debug('shareBucketsWithUsers, userIds', userIds);
            if (userIds.length === 0) {
                this.confirm.dialogTitle = $localize`Confirm Removal`;
                this.confirm.dialogBody =
                    $localize`Are you sure you want to remove all VIEW_CONTAINER user shares from the selected buckets?`;
                this.confirm.confirmString = $localize`Remove`;
                const confirmed = await firstValueFrom(this.confirm.open());
                if (!confirmed) { return; }
            }
            this.subscriptions.push(this.updateUserSharesViewPermGrid$(userIds).subscribe());
        } catch (error) {
            console.error('Error while fetching user IDs from grid', error);
        }
    }

    async shareBucketsWithUsersEditPermGrid(): Promise<void> {
        console.debug('shareBucketsWithUsers()');
        this.shareUsersDisabledEditPermGrid = !this.isSharingAllowedEditPermGrid();
        if (this.shareUsersDisabledEditPermGrid) { return; }
        const userIds: number[] = [];

        try {
            await firstValueFrom(new Observable<void>(observer => {
                this.userShareEditPermGrid.getGrid().context.getAllRowsAsText().subscribe({
                    next: row => {
                        console.debug('shareBucketsWithUsers, row', row);
                        if (row.id) {
                            userIds.push(row.id);
                        }
                    },
                    error: (err: unknown) => {
                        console.debug('shareBucketsWithUsers, err', err);
                        observer.error(err);
                    },
                    complete: () => {
                        console.debug('shareBucketsWithUsers, complete');
                        observer.next(); // firstValueFrom needs an emission
                        observer.complete();
                    }
                });
            }));
            console.debug('shareBucketsWithUsers, userIds', userIds);
            if (userIds.length === 0) {
                this.confirm.dialogTitle = $localize`Confirm Removal`;
                this.confirm.dialogBody =
                    $localize`Are you sure you want to remove all UPDATE_CONTAINER user shares from the selected buckets?`;
                this.confirm.confirmString = $localize`Remove`;
                const confirmed = await firstValueFrom(this.confirm.open());
                if (!confirmed) { return; }
            }
            this.subscriptions.push(this.updateUserSharesEditPermGrid$(userIds).subscribe());
        } catch (error) {
            console.error('Error while fetching user IDs from grid', error);
        }
    }

    updateUserSharesViewPermGrid$ = (selectedUserIds: number[]) => {
        console.debug('BucketUserShareDialog, updateUserShares$', selectedUserIds);
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.update_record_bucket_user_share_mapping',
            this.auth.token(),
            this.containerObjects.map(o => o.id),
            selectedUserIds,
            'VIEW_CONTAINER'
        ).pipe(
            tap({
                next: (response) => {
                    const evt = this.evt.parse(response);
                    if (evt) {
                        console.error(evt.toString());
                        this.fail.dialogBody = evt.toString();
                        this.fail.open();
                    } else {
                        console.debug('BucketUserShareDialogComponent, updated successfully');
                        this.toast.success($localize`User shares updated successfully`);
                    }
                },
                error: (error: unknown) => {
                    console.error('Error updating user shares', error);
                    this.fail.dialogBody = $localize`Error updating user shares`;
                    this.fail.open();
                },
                complete: () => {
                    console.debug('BucketUserShareDialogComponent, update complete');
                    this.close({success: true});
                }
            })
        );
    };

    updateUserSharesEditPermGrid$ = (selectedUserIds: number[]) => {
        console.debug('BucketUserShareDialog, updateUserShares$', selectedUserIds);
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.update_record_bucket_user_share_mapping',
            this.auth.token(),
            this.containerObjects.map(o => o.id),
            selectedUserIds,
            'UPDATE_CONTAINER'
        ).pipe(
            tap({
                next: (response) => {
                    const evt = this.evt.parse(response);
                    if (evt) {
                        console.error(evt.toString());
                        this.fail.dialogBody = evt.toString();
                        this.fail.open();
                    } else {
                        console.debug('BucketUserShareDialogComponent, updated successfully');
                        this.toast.success($localize`User shares updated successfully`);
                    }
                },
                error: (error: unknown) => {
                    console.error('Error updating user shares', error);
                    this.fail.dialogBody = $localize`Error updating user shares`;
                    this.fail.open();
                },
                complete: () => {
                    console.debug('BucketUserShareDialogComponent, update complete');
                    this.close({success: true});
                }
            })
        );
    };

    // TODO: second time we've used these two methods, so maybe time to move into a service
    async loadAouTree(selectNodeId?: number): Promise<any> {
        const flesh = ['children', 'ou_type'];
        this.orgsTouched = false;

        try {
            const tree = await firstValueFrom(this.pcrud.search('aou', {parent_ou : null},
                {flesh : -1, flesh_fields : {aou : flesh}}, {authoritative: true}
            ));

            this.ingestAouTree(tree); // sets this.shareTree as a side-effect
            if (!selectNodeId) { selectNodeId = this.org.root().id(); }

            return this.shareTree;
        } catch (E) {
            console.warn('caught from pcrud (aou)', E);
        }
    }

    ingestAouTree(aouTree: IdlObject) {

        const handleNode = (orgNode: IdlObject, expand?: boolean): TreeNode => {
            if (!orgNode) { return; }

            const treeNode = new TreeNode({
                id: orgNode.id(),
                label: orgNode.name() + '--' + orgNode.shortname(),
                callerData: {orgId: orgNode.id()},
                expanded: expand,
                stateFlagLabel: $localize`Select for record bucket sharing.`
            });

            // Tree node labels are "name -- shortname".  Sorting
            // by name suffices and bypasses the need the wait
            // for all of the labels to interpolate.
            orgNode.children()
                .sort((a: IdlObject, b: IdlObject) => a.name() < b.name() ? -1 : 1)
                .forEach((childNode: IdlObject) =>
                    treeNode.children.push(handleNode(childNode))
                );

            return treeNode;
        };

        const rootNode = handleNode(aouTree, true);
        this.shareTree = new Tree(rootNode);
    }

    dialog_nodeClicked($event: any) {
        console.debug('dialog: dialog_nodeClicked',$event);
        $event.stateFlag = !$event.stateFlag; // toggle
        this.shareOrgsDisabled = !this.isShareOrgsAllowed();
        this.orgsTouched = !this.shareOrgsDisabled;
        console.debug('dialog: dialog_nodeClicked exit, this.sharedOrgsDisabled',this.shareOrgsDisabled);
        console.debug('dialog: dialog_nodeClicked exit, this.orgsTouched',this.orgsTouched);
    }
    dialog_flagClicked($event: any) {
        console.debug('dialog: dialog_flagClicked',$event);
        this.shareOrgsDisabled = !this.isShareOrgsAllowed();
        this.orgsTouched = !this.shareOrgsDisabled;
        console.debug('dialog: dialog_flagClicked exit, this.sharedOrgsDisabled',this.shareOrgsDisabled);
        console.debug('dialog: dialog_flagClicked exit, this.orgsTouched',this.orgsTouched);
    }

    isShareOrgsAllowed(): boolean {
        // get the selected IDs
        const currently_selected = this.shareTree.findStateFlagNodes().map(n => n.id).sort((a,b) => { return a - b; });
        console.debug('dialog: isShareOrgsAllowed(), currently_selected', currently_selected);

        // see if the list lengths are different (changed!)
        if (currently_selected.length !== this._original_orgs.length) {
            console.debug('dialog: isShareOrgsAllowed(), original.length != current.length, so allow save');
            return true;
        }

        // same length, but both 0, nope
        if (currently_selected.length === 0) {
            console.debug('dialog: isShareOrgsAllowed(), original.length == current.length, but length == 0, so no save');
            return false;
        }

        // see if the sorted values are all the same (unchanged)
        // eslint-disable-next-line eqeqeq -- using == because number vs number as string
        if (currently_selected.sort().every((e,i) => e == this._original_orgs.sort()[i])) {
            console.debug('dialog: isShareOrgsAllowed(), all elements match, so no save');
            return false;
        }

        // no? it changed, allow
        console.debug('dialog: isShareOrgsAllowed(), fell through all tests, so allow save');
        return true;
    }

    async shareBucketsWithOrgs(): Promise<void> {
        this.shareOrgsDisabled = !this.isShareOrgsAllowed();
        if (this.shareOrgsDisabled) { return; }

        const checkedNodes = this.shareTree.findStateFlagNodes();
        if (checkedNodes.length === 0) {
            this.confirm.dialogTitle = $localize`Confirm Removal`;
            this.confirm.dialogBody = $localize`Are you sure you want to remove all org associations from the selected buckets?`;
            this.confirm.confirmString = $localize`Remove`;
            const confirmed = await firstValueFrom(this.confirm.open());
            if (!confirmed) { return; }
        }

        this.subscriptions.push(this.updateOrgShares$(checkedNodes).subscribe());
    }

    async populateCheckedNodes(): Promise<void> {
        this._original_orgs = (await firstValueFrom(
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_record_bucket_shared_org_ids', // hard-coded to record buckets for now
                this.auth.token(),
                this.containerObjects.map( o => o.id ),
            )
        )).sort((a,b) => { return a - b; });
        console.debug('populating this._original_orgs', this._original_orgs );
        this._original_orgs.forEach( orgId => {
            const node = this.shareTree.findNode( orgId );
            console.debug('populating node', node);
            node.stateFlag = true;
            this.shareTree.expandPathTo(node);
        });
    }

    updateOrgShares$ = (checkedNodes) => {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.update_record_bucket_org_share_mapping', // hard-coded to record buckets for now
            this.auth.token(),
            this.containerObjects.map( o => o.id ),
            checkedNodes.map( n => n.id )
        ).pipe(
            tap({
                next: (response) => {
                    const evt = this.evt.parse(response);
                    if (evt) {
                        console.error('BucketOrgShareDialogComponent, error', evt.toString());
                        this.fail.dialogBody = evt.toString();
                        this.fail.open();
                    } else {
                        Object.entries(response).map(([id, result]) => {
                            const evt2 = this.evt.parse(result);
                            if (evt2) {
                                console.error('BucketOrgShareDialogComponent, error2', evt.toString());
                                this.fail.dialogBody = evt2.toString();
                                this.fail.open();
                            }
                        });
                    }
                },
                error: (response: unknown) => {
                    console.error('BucketOrgShareDialogComponent, unknown error', response);
                    try {
                        this.fail.dialogBody = response.toString();
                    } catch(E) {
                        this.fail.dialogBody = $localize`Unexpected error. Check the developer tools console for the actual error.`;
                    }
                    this.fail.open({});
                },
                complete: () => {
                    this.close({success: true});
                }
            })
        );
    };

    async shareBuckets() {
        await this.shareBucketsWithUsersViewPermGrid();
        await this.shareBucketsWithUsersEditPermGrid();
        await this.shareBucketsWithOrgs();
    }
}
