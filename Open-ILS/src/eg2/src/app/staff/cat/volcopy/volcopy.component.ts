import {Component, OnInit, ViewChild, HostListener} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {BehaviorSubject, from, Observable, of} from 'rxjs';
import {catchError, finalize, switchMap, tap, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StoreService} from '@eg/core/store.service';
import {HoldingsService, CallNumData} from '@eg/staff/share/holdings/holdings.service';
import {VolCopyContext} from './volcopy';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {VolCopyPermissionDialogComponent} from './vol-copy-permission-dialog.component';
import {OpChangeComponent} from '@eg/staff/share/op-change/op-change.component';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {VolCopyService} from './volcopy.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {CopyAttrsComponent} from './copy-attrs.component';

const COPY_FLESH = {
    flesh: 1,
    flesh_fields: {
        acp: [
            'call_number', 'location', 'parts', 'tags',
            'creator', 'editor', 'stat_cat_entries', 'notes',
            'copy_alerts'
        ],
        acptcm: ['tag'],
        acpt: ['tag_type']
    }
};

interface EditSession {

    // Unset if editing in multi-record mode
    record_id: number;

    // list of copy IDs
    copies: number[];

    // Adding to or creating new call numbers
    raw: CallNumData[];

    // Hide the volumes editor
    hide_vols: boolean;

    // Hide the copy attrs editor.
    hide_copies: boolean;
}

@Component({
    templateUrl: 'volcopy.component.html'
})
export class VolCopyComponent implements OnInit {

    context: VolCopyContext;
    private contextChange = new BehaviorSubject<VolCopyContext>(null);
    // or this.context instead of null, but subscribers will get the broadcast during init
    contextChanged = this.contextChange.asObservable();
    loading = true;
    sessionExpired = false;

    tab = 'holdings'; // holdings | attrs | config
    target: string;   // item | callnumber | record | session
    targetId: string; // id value or session string

    volsCanSave = true;
    attrsCanSave = true;
    changesPending = false;
    changesPendingForStatusBar = false;
    routingAllowed = false;

    not_allowed_vols = [];

    @ViewChild('pendingChangesDialog', {static: false})
        pendingChangesDialog: ConfirmDialogComponent;

    @ViewChild('copyAttrs', {static: false}) copyAttrs: CopyAttrsComponent;

    @ViewChild('permDialog') permDialog: VolCopyPermissionDialogComponent;
    @ViewChild('uneditableItemsDialog') uneditableItemsDialog: AlertDialogComponent;

    @ViewChild('volEditOpChange', {static: false}) volEditOpChange: OpChangeComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService,
        private store: StoreService,
        private cache: AnonCacheService,
        private broadcaster: BroadcastService,
        private holdings: HoldingsService,
        private volcopy: VolCopyService
    ) { }

    ngOnInit() {
        console.log('VolCopyComponent, this',this);
        this.route.paramMap.subscribe(
            (params: ParamMap) => this.negotiateRoute(params));
    }

    orgName(orgId: number): string {
        return this.org.get(orgId).shortname();
    }

    cnPrefixName(id_or_obj: any): string {
        try {
            return id_or_obj.label();
        } catch(E) {
            return this.volcopy.commonData.acn_prefix[id_or_obj]?.label() || '';
        }
    }

    cnSuffixName(id_or_obj: any): string {
        try {
            return id_or_obj.label();
        } catch(E) {
            return this.volcopy.commonData.acn_suffix[id_or_obj]?.label() || '';
        }
    }

    localOpChange(): Observable<any> {  // Use the correct type instead of `any`
        const modalRef = this.volEditOpChange.open();

        console.log('VolCopyComponent, localOpChange, modalRef', modalRef);

        return modalRef.pipe(
            tap({
                next: res => console.log('VolCopyComponent, OpChangeComponent emission', res),
                error: (err: unknown) => console.error('VolCopyComponent, OpChangeComponent error', err),
                complete: () => console.log('VolCopyComponent, OpChangeComponent complete')
            }),
            finalize(() => {
                const opChangeData = { instigated: true, key: this.target + ':' + this.targetId };
                this.store.setSessionItem('opChangeInfo', opChangeData, false);

                // eslint-disable-next-line no-self-assign
                location.href = location.href; // my favorite sledgehammer
                // since we're communicating with broadcasts, this seems safe
            })
        );
    }

    localOpRestore() {
        // Restoring the original state
        const opChangeInfo = this.store.getSessionItem('opChangeInfo');
        console.log('VolCopyComponent, localOpRestore, opChangInfo', opChangeInfo);
        if (opChangeInfo?.instigated && opChangeInfo.key === this.target + ':' + this.targetId) {
            console.log('VolCopyComponent, localOpRestore, key matches');
            // Restore original operator
            try {
                this.volEditOpChange.restore();
                this.store.removeSessionItem('opChangeInfo');
            } catch(E) {
                window.alert(E);
            }
        } else {
            console.error('VolCopyComponent, localOpRestore, key does not match');
        }
    }

    closeWindow() {
        this.localOpRestore();
        window.close();
    }

    determineModal() {
        const itemCount = this.context.copyList().length;
        console.log('VolCopyComponent, itemCount', itemCount);
        if (itemCount <= 1) { return; } // skip dialog if only 1 item (or zero?!)
        from(this.perm.hasWorkPermAt(['UPDATE_COPY'], true))
            .pipe(
                switchMap(orgs => {

                    const owning_libs = this.context.getOwningLibIds();
                    const has_perm_for_each = owning_libs.every(owningLib => orgs['UPDATE_COPY'].includes(owningLib));

                    console.log('VolCopyComponent, hasWorkPermAt', orgs);
                    console.log('VolCopyComponent, owning libs', owning_libs);
                    console.log('VolCopyComponent, has perm for every lib? ', has_perm_for_each);

                    if (!has_perm_for_each) {
                        return this.permDialog.open().pipe(
                            map(dispatch => ({ dispatch, orgs }))
                        );
                    } else {
                        // Return an observable that completes without emitting if no dialog is needed
                        return of({dispatch: null, orgs});
                    }
                }),
                switchMap(({dispatch, orgs}) => {
                    console.log('VolCopyComponent, permDialog dispatch',dispatch);
                    if (dispatch === 'option-exit') {
                        // dialog was either X'ed out or "Exit Editor" was clicked.
                        this.closeWindow();
                        return of(null);
                    } else if (dispatch === 'option-filter') {
                        // "Only show permissible items."
                        const allowed_vols = this.context.volNodes().filter(n => orgs['UPDATE_COPY'].includes( n.target.owning_lib()));
                        this.not_allowed_vols = this.context.volNodes()
                            .filter(n => !orgs['UPDATE_COPY'].includes( n.target.owning_lib()));
                        this.not_allowed_vols.forEach(n => this.context.removeVolNode(n.target.id()));
                        if (this.not_allowed_vols.length > 0) {
                            this.contextChange.next(this.context);
                        }
                        return of(null);
                    } else if (dispatch === 'option-changeop') {
                        // "Change Operator and try again."
                        return this.localOpChange();
                    }
                    // option-readonly ("Read-only view for all items")
                    // is really the default behavior for mixed permissions,
                    // so just pass through
                    return of(null);
                }),
                finalize( () => {
                })
            ).subscribe(); // need this to start an Observable
    }

    negotiateRoute(params: ParamMap) {
        this.tab = params.get('tab') || 'holdings';
        this.target = params.get('target');
        this.targetId = params.get('target_id');

        if (this.volcopy.currentContext) {
            // Avoid clobbering the context on route change.
            this.context = this.volcopy.currentContext;
        } else {
            this.context = new VolCopyContext();
            this.context.org = this.org; // inject;
        }

        switch (this.target) {
            case 'item':
                this.context.copyId = +this.targetId;
                break;
            case 'callnumber':
                this.context.volId = +this.targetId;
                break;
            case 'record':
                this.context.recordId = +this.targetId;
                break;
            case 'session':
                this.context.session = this.targetId;
                break;
        }

        if (this.volcopy.currentContext) {
            this.loading = false;

        } else {
            // Avoid refetching the data during route changes.
            this.volcopy.currentContext = this.context;
            this.load().then( _ => { this.determineModal(); } );
        }
    }

    load(copyIds?: number[]): Promise<any> {
        this.sessionExpired = false;
        this.loading = true;
        this.context.reset();

        return this.volcopy.load()
            .then(_ => this.fetchHoldings(copyIds))
            .then(_ => this.volcopy.applyVolLabels(
                this.context.volNodes().map(n => n.target)))
            .then(_ => this.context.sortHoldings())
            .then(_ => this.context.setRecordId())
            .then(_ => {
            // unified display has no 'attrs' tab
                if (this.volcopy.defaults.values.unified_display
                && this.tab === 'attrs') {
                    this.tab = 'holdings';
                    this.routeToTab();
                }
            })
            .then(_ => this.loading = false);
    }

    fetchHoldings(copyIds?: number[]): Promise<any> {

        if (copyIds && copyIds.length > 0) {
            // Reloading copies that were just edited.
            return this.fetchCopies(copyIds);

        } else if (this.context.session) {
            this.context.sessionType = 'mixed';
            return this.fetchSession(this.context.session);

        } else if (this.context.copyId) {
            this.context.sessionType = 'copy';
            return this.fetchCopies(this.context.copyId);

        } else if (this.context.volId) {
            this.context.sessionType = 'vol';
            return this.fetchVols(this.context.volId);

        } else if (this.context.recordId) {
            this.context.sessionType = 'record';
            return this.fetchRecords(this.context.recordId);
        }
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    beforeTabChange(evt: NgbNavChangeEvent) {
        evt.preventDefault();

        // Always allow routing between tabs since no changes are lost
        // in the process.  In some cases, this is necessary to avoid
        // "pending changes" alerts while you are trying to resolve
        // other issues (e.g. applying values for required fields).
        this.routingAllowed = true;
        this.tab = evt.nextId;
        this.routeToTab();
    }

    routeToTab() {
        const url =
            `/staff/cat/volcopy/${this.tab}/${this.target}/${this.targetId}`;

        // Retain search parameters
        this.router.navigate([url], {queryParamsHandling: 'merge'});
    }

    fetchSession(session: string): Promise<any> {

        return this.cache.getItem(session, 'edit-these-copies')
            .then((editSession: EditSession) => {

                if (!editSession) {
                    this.loading = false;
                    this.sessionExpired = true;
                    return Promise.reject('Session Expired');
                }

                console.debug('Edit Session', editSession);

                this.context.recordId = editSession.record_id;

                if (editSession.copies && editSession.copies.length > 0) {
                    return this.fetchCopies(editSession.copies);
                }

                const volsToFetch = [];
                const volsToCreate = [];
                editSession.raw.forEach((volData: CallNumData) => {
                    this.context.fastAdd = volData.fast_add === true;

                    if (volData.callnumber > 0) {
                        volsToFetch.push(volData);
                    } else {
                        volsToCreate.push(volData);
                    }
                });

                let promise = Promise.resolve();
                if (volsToFetch.length > 0) {
                    promise = promise.then(_ =>
                        this.fetchVolsStubCopies(volsToFetch));
                }

                if (volsToCreate.length > 0) {
                    promise = promise.then(_ =>
                        this.createVolsStubCopies(volsToCreate));
                }

                return promise;
            });
    }

    // Creating new vols.  Each gets a stub copy.
    createVolsStubCopies(volDataList: CallNumData[]): Promise<any> {

        const vols = [];
        volDataList.forEach(volData => {

            const vol = this.volcopy.createStubVol(
                this.context.recordId,
                volData.owner || this.auth.user().ws_ou()
            );

            if (volData.label) {vol.label(volData.label); }

            volData.callnumber = vol.id(); // wanted by addStubCopies
            vols.push(vol);
            this.context.findOrCreateVolNode(vol);
        });

        return this.addStubCopies(vols, volDataList)
            .then(_ => this.volcopy.setVolClassLabels(vols));
    }

    // Fetch vols by ID, but instead of retrieving their copies
    // add a stub copy to each.
    fetchVolsStubCopies(volDataList: CallNumData[]): Promise<any> {

        const volIds = volDataList.map(volData => volData.callnumber);
        const vols = [];

        return this.pcrud.search('acn', {id: volIds})
            .pipe(tap((vol: IdlObject) => vols.push(vol))).toPromise()
            .then(_ => this.addStubCopies(vols, volDataList));
    }

    // Add a stub copy to each vol using data from the edit session.
    addStubCopies(vols: IdlObject[], volDataList: CallNumData[]): Promise<any> {

        const copies = [];
        vols.forEach(vol => {
            const volData = volDataList.filter(
                vData => vData.callnumber === vol.id())[0];

            const copy =
                this.volcopy.createStubCopy(vol, {circLib: volData.owner, barcode: volData.barcode});

            this.context.findOrCreateCopyNode(copy);
            copies.push(copy);
        });

        return this.volcopy.setCopyStatus(copies);
    }

    fetchCopies(copyIds: number | number[]): Promise<any> {
        const ids = [].concat(copyIds);
        if (ids.length === 0) { return Promise.resolve(); }
        return this.pcrud.search('acp', {id: ids}, COPY_FLESH)
            .pipe(tap(copy => this.context.findOrCreateCopyNode(copy)))
            .toPromise();
    }

    // Fetch call numbers and linked copies by call number ids.
    fetchVols(volIds?: number | number[]): Promise<any> {
        const ids = [].concat(volIds);
        if (ids.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('acn', {id: ids})
            .pipe(tap(vol => this.context.findOrCreateVolNode(vol)))
            .toPromise().then(_ => {
                return this.pcrud.search('acp',
                    {call_number: ids, deleted: 'f'}, COPY_FLESH
                ).pipe(tap(copy => this.context.findOrCreateCopyNode(copy))
                ).toPromise();
            });
    }

    // Fetch call numbers and copies by record ids.
    fetchRecords(recordIds: number | number[]): Promise<any> {
        const ids = [].concat(recordIds);

        return this.pcrud.search('acn',
            {record: ids, deleted: 'f', label: {'!=' : '##URI##'}},
            {}, {idlist: true, atomic: true}
        ).toPromise().then(volIds => this.fetchVols(volIds));
    }


    save(close?: boolean): Promise<any> {
        this.loading = true;

        if (this.copyAttrs) {
            // Won't exist on any non-attrs page.
            this.copyAttrs.applyPendingChanges();
        }

        // Volume update API wants volumes fleshed with copies, instead
        // of the other way around, which is what we have here.
        const volumes: IdlObject[] = [];

        if (this.not_allowed_vols.length > 0) {
            // remind staff about these items that were filtered out
            this.uneditableItemsDialog.open();
        }

        this.context.volNodes().forEach(volNode => {
            const newVol = this.idl.clone(volNode.target);
            const copies: IdlObject[] = [];

            volNode.children.forEach(copyNode => {
                const copy = copyNode.target;

                if (copy.isnew() && !copy.barcode()) {
                    // A new copy w/ no barcode is a stub copy sitting
                    // on an empty call number.  Ignore it.
                    return;
                }

                // Be sure to include copies when the volume is changed
                // without any changes to the copies.  This ensures the
                // API knows when we are modifying a subset of the total
                // copies on a volume, e.g. when changing volume labels
                if (newVol.ischanged()) { copy.ischanged(true); }

                if (copy.ischanged() || copy.isnew() || copy.isdeleted()) {
                    const copyClone = this.idl.clone(copy);
                    // De-flesh call number
                    copyClone.call_number(copy.call_number().id());
                    copies.push(copyClone);
                }
            });

            newVol.copies(copies);

            if (newVol.ischanged() || newVol.isnew() || copies.length > 0) {
                volumes.push(newVol);
            }
        });

        this.context.volsToDelete.forEach(vol => {
            const cloneVol = this.idl.clone(vol);
            // No need to flesh copies -- they'll be force deleted.
            cloneVol.copies([]);
            volumes.push(cloneVol);
        });

        this.context.copiesToDelete.forEach(copy => {
            const cloneCopy = this.idl.clone(copy);
            const copyVol = cloneCopy.call_number();
            cloneCopy.call_number(copyVol.id()); // de-flesh

            let vol = volumes.filter(v => v.id() === copyVol.id())[0];

            if (vol) {
                vol.copies().push(cloneCopy);
            } else {
                vol = this.idl.clone(copyVol);
                vol.copies([cloneCopy]);
            }

            volumes.push(vol);
        });

        // De-flesh before posting
        volumes.forEach(vol => {
            vol.copies().forEach(copy => {
                ['editor', 'creator', 'location'].forEach(field => {
                    if (typeof copy[field]() === 'object') {
                        copy[field](copy[field]().id());
                    }
                });
            });
        });

        let promise: Promise<number[]> = Promise.resolve([]);

        if (volumes.length > 0) {
            promise = this.saveApi(volumes, false, close);
        }

        return promise.then(copyIds => {

            // In addition to the copies edited in this update call,
            // reload any other copies that were previously loaded.
            const ids: any = {}; // dedupe
            this.context.copyList()
                .map(c => c.id())
                .filter(id => id > 0) // scrub the new copy IDs
                .concat(copyIds)
                .forEach(id => ids[id] = true);

            copyIds = Object.keys(ids).map(id => Number(id));

            if (close) {
                return this.openPrintLabels(copyIds)
                    .then(_ => setTimeout(() => this.closeWindow()));
            }

            return this.load(Object.keys(ids).map(id => Number(id)));

        }).then(_ => {
            this.loading = false;
            this.changesPending = false;
            this.changesPendingForStatusBar = false;
        });
    }

    broadcastChanges(volumes: IdlObject[]) {

        const volIds = volumes.map(v => v.id());
        const copyIds = [];
        const recIds = [];

        volumes.forEach(vol => {
            if (!recIds.includes(vol.record())) {
                recIds.push(vol.record());
            }
            vol.copies().forEach(copy => copyIds.push(copy.id()));
        });

        this.broadcaster.broadcast('eg.holdings.update', {
            copies : copyIds,
            volumes: volIds,
            records: recIds
        });
    }

    saveApi(volumes: IdlObject[], override?:
        boolean, close?: boolean): Promise<number[]> {

        let method = 'open-ils.cat.asset.volume.fleshed.batch.update';
        if (override) { method += '.override'; }

        return this.net.request('open-ils.cat',
            method, this.auth.token(), volumes, true,
            {   auto_merge_vols: true,
                create_parts: true,
                return_copy_ids: true,
                force_delete_copies: true
            }

        ).toPromise().then(copyIds => {

            const evt = this.evt.parse(copyIds);

            if (evt) {
                // TODO: handle overrides?
                // return this.saveApi(volumes, true, close);
                this.loading = false;
                alert(evt);
                return Promise.reject();
            }

            this.broadcastChanges(volumes);

            return copyIds;
        });
    }

    toggleCheckbox(field: string) {
        this.volcopy.defaults.values[field] =
            !this.volcopy.defaults.values[field];
        this.volcopy.saveDefaults();
    }

    openPrintLabels(copyIds?: number[]): Promise<any> {
        if (!this.volcopy.defaults.values.print_labels) {
            return Promise.resolve();
        }

        if (!copyIds || copyIds.length === 0) {
            copyIds = this.context.copyList()
                .map(c => c.id()).filter(id => id > 0);
        }

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'print-labels-these-copies', {copies : copyIds}

        ).toPromise().then(key => {

            const url = '/eg/staff/cat/printlabels/' + key;
            setTimeout(() => window.open(url, '_blank'));
        });
    }

    isNotSaveable(): boolean {

        if (!this.volsCanSave) { return true; }
        if (!this.attrsCanSave) { return true; }

        // This can happen regardless of whether we are modifying
        // volumes vs. copies.
        if (this.volcopy.missingRequiredStatCat()) { return true; }

        return false;
    }

    volsCanSaveChange(can: boolean) {
        this.volsCanSave = can;
        this.changesPending = true;
        this.changesPendingForStatusBar = true;
    }

    attrsCanSaveChange(can: boolean) {
        this.attrsCanSave = can;
        this.changesPending = true;
        this.changesPendingForStatusBar = true;
    }

    @HostListener('window:beforeunload', ['$event'])
    canDeactivate($event?: Event): boolean | Promise<boolean> {

        if (this.routingAllowed) {
            // We call canDeactive manually when routing between volcopy
            // tabs.  If routingAllowed, it means we'ave already confirmed
            // the tag change is OK.
            this.routingAllowed = false;
            return true;
        }

        const editing = this.copyAttrs ? this.copyAttrs.hasActiveInput() : false;

        if (!editing && !this.changesPending) { return true; }

        // Each warning dialog clears the current "changes are pending"
        // flag so the user is not presented with the dialog again
        // unless new changes are made.  The 'editing' value will reset
        // since the attrs component is getting destroyed.
        this.changesPending = false;
        // But don't do this for the indicator in the status bar, only Save does that
        // (or reset, if that ever gets reimplemented)
        // this.changesPendingForStatusBar = false;

        if ($event) { // window.onbeforeunload
            $event.preventDefault();
            $event.returnValue = true;

        } else { // tab OR route change.
            return this.pendingChangesDialog.open().toPromise();
        }
    }
}



