import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Observable, Observer, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {StaffCatalogService} from '../catalog.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridToolbarCheckboxComponent
    } from '@eg/share/grid/grid-toolbar-checkbox.component';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {MarkDamagedDialogComponent
    } from '@eg/staff/share/holdings/mark-damaged-dialog.component';
import {MarkMissingDialogComponent
    } from '@eg/staff/share/holdings/mark-missing-dialog.component';
import {AnonCacheService} from '@eg/share/util/anon-cache.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {CopyAlertsDialogComponent
    } from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {ReplaceBarcodeDialogComponent
    } from '@eg/staff/share/holdings/replace-barcode-dialog.component';
import {DeleteVolcopyDialogComponent
    } from '@eg/staff/share/holdings/delete-volcopy-dialog.component';
import {BucketDialogComponent
    } from '@eg/staff/share/buckets/bucket-dialog.component';
import {ConjoinedItemsDialogComponent
    } from '@eg/staff/share/holdings/conjoined-items-dialog.component';
import {MakeBookableDialogComponent
    } from '@eg/staff/share/booking/make-bookable-dialog.component';

// The holdings grid models a single HoldingsTree, composed of HoldingsTreeNodes
// flattened on-demand into a list of HoldingEntry objects.
class HoldingsTreeNode {
    children: HoldingsTreeNode[];
    nodeType: 'org' | 'volume' | 'copy';
    target: any;
    parentNode: HoldingsTreeNode;
    expanded: boolean;
    copyCount: number;
    volumeCount: number;
    constructor() {
        this.children = [];
    }
}

class HoldingsTree {
    root: HoldingsTreeNode;
    constructor() {
        this.root = new HoldingsTreeNode();
    }
}

class HoldingsEntry {
    index: number;
    // org unit shortname, call number label, or copy barcode
    locationLabel: string;
    // location label indentation depth
    locationDepth: number | null;
    volumeCount: number | null;
    copyCount: number | null;
    callNumberLabel: string;
    copy: IdlObject;
    volume: IdlObject;
    circ: IdlObject;
    treeNode: HoldingsTreeNode;
}

@Component({
  selector: 'eg-holdings-maintenance',
  templateUrl: 'holdings.component.html',
  styleUrls: ['holdings.component.css']
})
export class HoldingsMaintenanceComponent implements OnInit {

    initDone = false;
    gridDataSource: GridDataSource;
    gridTemplateContext: any;
    @ViewChild('holdingsGrid') holdingsGrid: GridComponent;

    // Manage visibility of various sub-sections
    @ViewChild('volsCheckbox')
        private volsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('copiesCheckbox')
        private copiesCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyVolsCheckbox')
        private emptyVolsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyLibsCheckbox')
        private emptyLibsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('markDamagedDialog')
        private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('markMissingDialog')
        private markMissingDialog: MarkMissingDialogComponent;
    @ViewChild('copyAlertsDialog')
        private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('replaceBarcode')
        private replaceBarcode: ReplaceBarcodeDialogComponent;
    @ViewChild('deleteVolcopy')
        private deleteVolcopy: DeleteVolcopyDialogComponent;
    @ViewChild('bucketDialog')
        private bucketDialog: BucketDialogComponent;
    @ViewChild('conjoinedDialog')
        private conjoinedDialog: ConjoinedItemsDialogComponent;
    @ViewChild('makeBookableDialog')
        private makeBookableDialog: MakeBookableDialogComponent;

    holdingsTree: HoldingsTree;

    // nodeType => id => tree node cache
    treeNodeCache: {[nodeType: string]: {[id: number]: HoldingsTreeNode}};

    // When true and a grid reload is called, the holdings data will be
    // re-fetched from the server.
    refreshHoldings: boolean;

    // Used as a row identifier in th grid, since we're mixing object types.
    gridIndex: number;

    // List of copies whose due date we need to retrieve.
    itemCircsNeeded: IdlObject[];

    // When true draw the grid based on the stored preferences.
    // When not true, render based on the current "expanded" state of each node.
    // Rendering from prefs happens on initial load and when any prefs change.
    renderFromPrefs: boolean;

    rowClassCallback: (row: any) => string;

    private _recId: number;
    @Input() set recordId(id: number) {
        this._recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.hardRefresh();
        }
    }
    get recordId(): number {
        return this._recId;
    }

    contextOrg: IdlObject;

    constructor(
        private router: Router,
        private org: OrgService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private staffCat: StaffCatalogService,
        private store: ServerStoreService,
        private localStore: StoreService,
        private holdings: HoldingsService,
        private anonCache: AnonCacheService
    ) {
        // Set some sane defaults before settings are loaded.
        this.gridDataSource = new GridDataSource();
        this.refreshHoldings = true;
        this.renderFromPrefs = true;

        // TODO: need a separate setting for this?
        this.contextOrg = this.staffCat.searchContext.searchOrg;

        this.rowClassCallback = (row: any): string => {
            if (row.volume) {
                if (row.copy) {
                    return 'holdings-copy-row';
                } else {
                    return 'holdings-volume-row';
                }
            } else {
                // Add a generic org unit class and a depth-specific
                // class for styling different levels of the org tree.
                return 'holdings-org-row holdings-org-row-' +
                    row.treeNode.target.ou_type().depth();
            }
        };

        this.gridTemplateContext = {
            toggleExpandRow: (row: HoldingsEntry) => {
                row.treeNode.expanded = !row.treeNode.expanded;

                if (!row.treeNode.expanded) {
                    // When collapsing a node, all child nodes should be
                    // collapsed as well.
                    const traverse = (node: HoldingsTreeNode) => {
                        node.expanded = false;
                        node.children.forEach(traverse);
                    };
                    traverse(row.treeNode);
                }

                this.holdingsGrid.reload();
            },

            copyIsHoldable: (copy: IdlObject): boolean => {
                return copy.holdable() === 't'
                    && copy.location().holdable() === 't'
                    && copy.status().holdable() === 't';
            }
        };
    }

    ngOnInit() {
        this.initDone = true;

        // These are pre-cached via the catalog resolver.
        const settings = this.store.getItemBatchCached([
            'cat.holdings_show_empty_org',
            'cat.holdings_show_empty',
            'cat.holdings_show_copies',
            'cat.holdings_show_vols'
        ]);

        // Show volumes by default when no preference is set.
        let showVols = settings['cat.holdings_show_vols'];
        if (showVols === null) { showVols = true; }

        this.volsCheckbox.checked(showVols);
        this.copiesCheckbox.checked(settings['cat.holdings_show_copies']);
        this.emptyVolsCheckbox.checked(settings['cat.holdings_show_empty']);
        this.emptyLibsCheckbox.checked(settings['cat.holdings_show_empty_org']);

        this.initHoldingsTree();
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchHoldings(pager);
        };
    }

    contextOrgChanged(org: IdlObject) {
        this.contextOrg = org;
        this.hardRefresh();
    }

    hardRefresh() {
        this.renderFromPrefs = true;
        this.refreshHoldings = true;
        this.initHoldingsTree();
        this.holdingsGrid.reload();
    }

    toggleShowCopies(value: boolean) {
        this.store.setItem('cat.holdings_show_copies', value);
        if (value) {
            // Showing copies implies showing volumes
            this.volsCheckbox.checked(true);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowVolumes(value: boolean) {
        this.store.setItem('cat.holdings_show_vols', value);
        if (!value) {
            // Hiding volumes implies hiding empty vols and copies.
            this.copiesCheckbox.checked(false);
            this.emptyVolsCheckbox.checked(false);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowEmptyVolumes(value: boolean) {
        this.store.setItem('cat.holdings_show_empty', value);
        if (value) {
            this.volsCheckbox.checked(true);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowEmptyLibs(value: boolean) {
        this.store.setItem('cat.holdings_show_empty_org', value);
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    onRowActivate(row: any) {
        if (row.copy) {
            // Launch copy editor?
        } else {
            this.gridTemplateContext.toggleExpandRow(row);
        }
    }

    initHoldingsTree() {

        const visibleOrgs = this.org.fullPath(this.contextOrg, true);

        // The initial tree simply matches the org unit tree
        const traverseOrg = (node: HoldingsTreeNode) => {
            node.target.children().forEach((org: IdlObject) => {
                if (visibleOrgs.indexOf(org.id()) === -1) {
                    return; // Org is outside of scope
                }
                const nodeChild = new HoldingsTreeNode();
                nodeChild.nodeType = 'org';
                nodeChild.target = org;
                nodeChild.parentNode = node;
                node.children.push(nodeChild);
                this.treeNodeCache.org[org.id()] = nodeChild;
                traverseOrg(nodeChild);
            });
        };

        this.treeNodeCache = {
            org: {},
            volume: {},
            copy: {}
        };

        this.holdingsTree = new HoldingsTree();
        this.holdingsTree.root.nodeType = 'org';
        this.holdingsTree.root.target = this.org.root();
        this.treeNodeCache.org[this.org.root().id()] = this.holdingsTree.root;

        traverseOrg(this.holdingsTree.root);
    }

    // Org node children are sorted with any child org nodes pushed to the
    // front, followed by the call number nodes sorted alphabetcially by label.
    sortOrgNodeChildren(node: HoldingsTreeNode) {
        node.children = node.children.sort((a, b) => {
            if (a.nodeType === 'org') {
                if (b.nodeType === 'org') {
                    return a.target.shortname() < b.target.shortname() ? -1 : 1;
                } else {
                    return -1;
                }
            } else if (b.nodeType === 'org') {
                return 1;
            } else {
                // TODO: should this use label sortkey instead of
                // the compiled volume label?
                return a.target._label < b.target._label ? -1 : 1;
            }
        });
    }

    // Sets call number and copy count sums to nodes that need it.
    // Applies the initial expansed state of each container node.
    setTreeCounts(node: HoldingsTreeNode) {

        if (node.nodeType === 'org') {
            node.copyCount = 0;
            node.volumeCount = 0;
        } else if (node.nodeType === 'volume') {
            node.copyCount = 0;
        }

        let hasChildOrgWithData = false;
        let hasChildOrgSansData = false;
        node.children.forEach(child => {
            this.setTreeCounts(child);
            if (node.nodeType === 'org') {
                node.copyCount += child.copyCount;
                if (child.nodeType === 'volume') {
                    node.volumeCount++;
                } else {
                    hasChildOrgWithData = child.volumeCount > 0;
                    hasChildOrgSansData = child.volumeCount === 0;
                    node.volumeCount += child.volumeCount;
                }
            } else if (node.nodeType === 'volume') {
                node.copyCount = node.children.length;
                if (this.renderFromPrefs) {
                    node.expanded = this.copiesCheckbox.checked();
                }
            }
        });

        if (this.renderFromPrefs && node.nodeType === 'org') {
            if (node.copyCount > 0 && this.volsCheckbox.checked()) {
                node.expanded = true;
            } else if (node.volumeCount > 0 && this.emptyVolsCheckbox.checked()) {
                node.expanded = true;
            } else if (hasChildOrgWithData) {
                node.expanded = true;
            } else if (hasChildOrgSansData && this.emptyLibsCheckbox.checked()) {
                node.expanded = true;
            } else {
                node.expanded = false;
            }
        }
    }

    // Create HoldingsEntry objects for tree nodes that should be displayed
    // and relays them to the grid via the observer.
    propagateTreeEntries(observer: Observer<HoldingsEntry>, node: HoldingsTreeNode) {
        const entry = new HoldingsEntry();
        entry.treeNode = node;
        entry.index = this.gridIndex++;

        switch (node.nodeType) {
            case 'org':
                if (node.volumeCount === 0
                    && !this.emptyLibsCheckbox.checked()) {
                    return;
                }
                entry.locationLabel = node.target.shortname();
                entry.locationDepth = node.target.ou_type().depth();
                entry.copyCount = node.copyCount;
                entry.volumeCount = node.volumeCount;
                this.sortOrgNodeChildren(node);
                break;

            case 'volume':
                if (this.renderFromPrefs) {
                    if (!this.volsCheckbox.checked()) {
                        return;
                    }
                    if (node.copyCount === 0
                        && !this.emptyVolsCheckbox.checked()) {
                        return;
                    }
                }
                entry.locationLabel = node.target._label;
                entry.locationDepth = node.parentNode.target.ou_type().depth() + 1;
                entry.callNumberLabel = entry.locationLabel;
                entry.volume = node.target;
                entry.copyCount = node.copyCount;
                break;

            case 'copy':
                entry.locationLabel = node.target.barcode();
                entry.locationDepth = node.parentNode.parentNode.target.ou_type().depth() + 2;
                entry.callNumberLabel = node.parentNode.target.label(); // TODO
                entry.volume = node.parentNode.target;
                entry.copy = node.target;
                entry.circ = node.target._circ;
                break;
        }

        // Tell the grid about the node entry
        observer.next(entry);

        if (node.expanded) {
            // Process the child nodes.
            node.children.forEach(child =>
                this.propagateTreeEntries(observer, child));
        }
    }

    // Turns the tree into a list of entries for grid display
    flattenHoldingsTree(observer: Observer<HoldingsEntry>) {
        this.gridIndex = 0;
        this.setTreeCounts(this.holdingsTree.root);
        this.propagateTreeEntries(observer, this.holdingsTree.root);
        observer.complete();
        this.renderFromPrefs = false;
    }

    // Grab volumes, copies, and related data.
    fetchHoldings(pager: Pager): Observable<any> {
        if (!this.recordId) { return of([]); }

        return new Observable<any>(observer => {

            if (!this.refreshHoldings) {
                this.flattenHoldingsTree(observer);
                return;
            }

            this.itemCircsNeeded = [];

            this.pcrud.search('acn',
                {   record: this.recordId,
                    owning_lib: this.org.fullPath(this.contextOrg, true),
                    deleted: 'f',
                    label: {'!=' : '##URI##'}
                }, {
                    flesh: 3,
                    flesh_fields: {
                        acp: ['status', 'location', 'circ_lib', 'parts',
                            'age_protect', 'copy_alerts', 'latest_inventory'],
                        acn: ['prefix', 'suffix', 'copies'],
                        acli: ['inventory_workstation']
                    }
                },
                {authoritative: true}
            ).subscribe(
                vol => this.appendVolume(vol),
                err => {},
                ()  => {
                    this.refreshHoldings = false;
                    this.fetchCircs().then(
                        ok => this.flattenHoldingsTree(observer)
                    );
                }
            );
        });
    }

    // Retrieve circulation objects for checked out items.
    fetchCircs(): Promise<any> {
        const copyIds = this.itemCircsNeeded.map(copy => copy.id());
        if (copyIds.length === 0) { return Promise.resolve(); }

        return this.pcrud.search('circ', {
            target_copy: copyIds,
            checkin_time: null
        }).pipe(map(circ => {
            const copy = this.itemCircsNeeded.filter(
                c => Number(c.id()) === Number(circ.target_copy()))[0];
            copy._circ = circ;
        })).toPromise();
    }

    // Compile prefix + label + suffix into field volume._label;
    setVolumeLabel(volume: IdlObject) {
        const pfx = volume.prefix() ? volume.prefix().label() : '';
        const sfx = volume.suffix() ? volume.suffix().label() : '';
        volume._label = pfx ? pfx + ' ' : '';
        volume._label += volume.label();
        volume._label += sfx ? ' ' + sfx : '';
    }

    // Create the tree node for the volume if it doesn't already exist.
    // Do the same for its linked copies.
    appendVolume(volume: IdlObject) {
        let volNode = this.treeNodeCache.volume[volume.id()];
        this.setVolumeLabel(volume);

        if (volNode) {
            const pNode = this.treeNodeCache.org[volume.owning_lib()];
            if (volNode.parentNode.target.id() !== pNode.target.id()) {
                // Volume owning library changed.  Un-link it from the previous
                // org unit collection before adding to the new one.
                // XXX TODO: ^--
                volNode.parentNode = pNode;
                volNode.parentNode.children.push(volNode);
            }
        } else {
            volNode = new HoldingsTreeNode();
            volNode.nodeType = 'volume';
            volNode.parentNode = this.treeNodeCache.org[volume.owning_lib()];
            volNode.parentNode.children.push(volNode);
            this.treeNodeCache.volume[volume.id()] = volNode;
        }

        volNode.target = volume;

        volume.copies()
            .filter((copy: IdlObject) => (copy.deleted() !== 't'))
            .sort((a: IdlObject, b: IdlObject) => a.barcode() < b.barcode() ? -1 : 1)
            .forEach((copy: IdlObject) => this.appendCopy(volNode, copy));
    }

    // Find or create a copy node.
    appendCopy(volNode: HoldingsTreeNode, copy: IdlObject) {
        let copyNode = this.treeNodeCache.copy[copy.id()];

        if (copyNode) {
            const oldParent = copyNode.parentNode;
            if (oldParent.target.id() !== volNode.target.id()) {
                // TODO: copy changed owning volume.  Remove it from
                // the previous volume before adding to the new volume.
                copyNode.parentNode = volNode;
                volNode.children.push(copyNode);
            }
        } else {
            // New node required
            copyNode = new HoldingsTreeNode();
            copyNode.nodeType = 'copy';
            volNode.children.push(copyNode);
            copyNode.parentNode = volNode;
            this.treeNodeCache.copy[copy.id()] = copyNode;
        }

        copyNode.target = copy;
        const stat = Number(copy.status().id());

        if (stat === 1 /* checked out */ || stat === 16 /* long overdue */) {
            // Avoid looking up circs on items that are not checked out.
            this.itemCircsNeeded.push(copy);
        }
    }

    // Which copies in the grid are selected.
    selectedCopyIds(rows: HoldingsEntry[], skipStatus?: number): number[] {
        let copyRows = rows.filter(r => Boolean(r.copy)).map(r => r.copy);
        if (skipStatus) {
            copyRows = copyRows.filter(
                c => Number(c.status().id()) !== Number(skipStatus));
        }
        return copyRows.map(c => Number(c.id()));
    }

    selectedVolumeIds(rows: HoldingsEntry[]): number[] {
        return rows
            .filter(r => r.treeNode.nodeType === 'volume')
            .map(r => Number(r.volume.id()));
    }

    async showMarkDamagedDialog(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows, 14 /* ignore damaged */);

        if (copyIds.length === 0) { return; }

        let rowsModified = false;

        const markNext = async(ids: number[]) => {
            if (ids.length === 0) {
                return Promise.resolve();
            }

            this.markDamagedDialog.copyId = ids.pop();
            return this.markDamagedDialog.open({size: 'lg'}).subscribe(
                ok => {
                    if (ok) { rowsModified = true; }
                    return markNext(ids);
                },
                dismiss => markNext(ids)
            );
        };

        await markNext(copyIds);
        if (rowsModified) {
            this.refreshHoldings = true;
            this.holdingsGrid.reload();
        }
    }

    showMarkMissingDialog(rows: any[]) {
        const copyIds = this.selectedCopyIds(rows, 4 /* ignore missing */);
        if (copyIds.length > 0) {
            this.markMissingDialog.copyIds = copyIds;
            this.markMissingDialog.open({}).subscribe(
                rowsModified => {
                    if (rowsModified) {
                        this.refreshHoldings = true;
                        this.holdingsGrid.reload();
                    }
                },
                dismissed => {} // avoid console errors
            );
        }
    }

    // Mark record, library, and potentially the selected call number
    // as the current transfer target.
    markLibCnForTransfer(rows: HoldingsEntry[]) {
        if (rows.length === 0) {
            return;
        }

        // Action may only apply to a single org or volume row.
        const node = rows[0].treeNode;
        if (node.nodeType === 'copy') {
            return;
        }

        let orgId: number;

        if (node.nodeType === 'org') {
            orgId = node.target.id();

            // Clear volume target when performed on an org unit row
            this.localStore.removeLocalItem('eg.cat.transfer_target_vol');

        } else if (node.nodeType === 'volume') {

            // All volume nodes are children of org nodes.
            orgId = node.parentNode.target.id();

            // Add volume target when performed on a volume row.
            this.localStore.setLocalItem(
                'eg.cat.transfer_target_vol', node.target.id());
        }

        this.localStore.setLocalItem('eg.cat.transfer_target_record', this.recordId);
        this.localStore.setLocalItem('eg.cat.transfer_target_lib', orgId);
    }

    openAngJsWindow(path: string) {
        const url = `/eg/staff/${path}`;
        window.open(url, '_blank');
    }

    openItemHolds(rows: HoldingsEntry[]) {
        if (rows.length > 0 && rows[0].copy) {
            this.openAngJsWindow(`cat/item/${rows[0].copy.id()}/holds`);
        }
    }

    openItemStatusList(rows: HoldingsEntry[]) {
        const ids = this.selectedCopyIds(rows);
        if (ids.length > 0) {
            return this.openAngJsWindow(`cat/item/search/${ids.join(',')}`);
        }
    }

    openItemStatus(rows: HoldingsEntry[]) {
        if (rows.length > 0 && rows[0].copy) {
           return this.openAngJsWindow(`cat/item/${rows[0].copy.id()}`);
        }
    }

    openItemTriggeredEvents(rows: HoldingsEntry[]) {
        if (rows.length > 0 && rows[0].copy) {
           return this.openAngJsWindow(
               `cat/item/${rows[0].copy.id()}/triggered_events`);
        }
    }

    openItemPrintLabels(rows: HoldingsEntry[]) {
        const ids = this.selectedCopyIds(rows);
        if (ids.length === 0) { return; }

        this.anonCache.setItem(null, 'print-labels-these-copies', {copies: ids})
        .then(key => this.openAngJsWindow(`cat/printlabels/${key}`));
    }

    openVolCopyEdit(rows: HoldingsEntry[], addVols: boolean, addCopies: boolean) {

        // The user may select a set of volumes by selecting volume and/or
        // copy rows.
        const volumes = [];
        rows.forEach(r => {
            if (r.treeNode.nodeType === 'volume') {
                volumes.push(r.volume);
            } else if (r.treeNode.nodeType === 'copy') {
                volumes.push(r.treeNode.parentNode.target);
            }
        });

        if (addCopies && !addVols) {
            // Adding copies to an existing set of volumes.
            if (volumes.length > 0) {
                const volIds = volumes.map(v => Number(v.id()));
                this.holdings.spawnAddHoldingsUi(this.recordId, volIds);
            }

        } else if (addVols) {
            const entries = [];

            if (volumes.length > 0) {

                // When adding volumes, if any are selected in the grid,
                // create volumes that have the same label and owner.
                volumes.forEach(v =>
                    entries.push({label: v.label(), owner: v.owning_lib()}));

                } else {

                // Otherwise create new volumes from scratch.
                entries.push({owner: this.auth.user().ws_ou()});
            }

            this.holdings.spawnAddHoldingsUi(
                this.recordId, null, entries, !addCopies);
        }
    }

    openItemNotes(rows: HoldingsEntry[], mode: string) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.mode = mode;
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            modified => {
                if (modified) {
                    this.hardRefresh();
                }
            }
        );
    }

    openReplaceBarcodeDialog(rows: HoldingsEntry[]) {
        const ids = this.selectedCopyIds(rows);
        if (ids.length === 0) { return; }
        this.replaceBarcode.copyIds = ids;
        this.replaceBarcode.open({}).subscribe(
            modified => {
                if (modified) {
                    this.hardRefresh();
                }
            }
        );
    }

    // mode 'vols' -- only delete empty volumes
    // mode 'copies' -- only delete selected copies
    // mode 'both' -- delete selected copies and selected volumes, plus all
    // copies linked to selected volumes, regardless of whether they are selected.
    deleteHoldings(rows: HoldingsEntry[], mode: 'vols' | 'copies' | 'both') {
        const volHash: any = {};

        if (mode === 'vols' || mode === 'both') {
            // Collect the volumes to be deleted.
            rows.filter(r => r.treeNode.nodeType === 'volume').forEach(r => {
                const vol = this.idl.clone(r.volume);
                if (mode === 'vols') {
                    if (vol.copies().length > 0) {
                        // cannot delete non-empty volume in this mode.
                        return;
                    }
                } else {
                    vol.copies().forEach(c => c.isdeleted(true));
                }
                vol.isdeleted(true);
                volHash[vol.id()] = vol;
            });
        }

        if (mode === 'copies' || mode === 'both') {
            // Collect the copies to be deleted, including their volumes
            // since the API expects fleshed volume objects.
            rows.filter(r => r.treeNode.nodeType === 'copy').forEach(r => {
                const vol = r.treeNode.parentNode.target;
                if (!volHash[vol.id()]) {
                    volHash[vol.id()] = this.idl.clone(vol);
                    volHash[vol.id()].copies([]);
                }
                const copy = this.idl.clone(r.copy);
                copy.isdeleted(true);
                volHash[vol.id()].copies().push(copy);
            });
        }

        if (Object.keys(volHash).length === 0) {
            // No data to process.
            return;
        }

        // Note forceDeleteCopies should not be necessary here, since we
        // manually marked all copies as deleted on deleted volumes in
        // "both" mode.
        this.deleteVolcopy.forceDeleteCopies = mode === 'both';
        this.deleteVolcopy.volumes = Object.values(volHash);
        this.deleteVolcopy.open({size: 'sm'}).subscribe(
            modified => {
                if (modified) {
                    this.hardRefresh();
                }
            }
        );
    }

    requestItems(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }
        const params = {target: copyIds, holdFor: 'staff'};
        this.router.navigate(['/staff/catalog/hold/C'], {queryParams: params});
    }

    openBucketDialog(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            this.bucketDialog.bucketClass = 'copy';
            this.bucketDialog.itemIds = copyIds;
            this.bucketDialog.open({size: 'lg'});
        }
    }

    openConjoinedDialog(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            this.conjoinedDialog.copyIds = copyIds;
            this.conjoinedDialog.open({size: 'sm'});
        }
    }

    bookItems(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            alert('TODO');
        }
    }

    makeBookable(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            this.makeBookableDialog.copyIds = copyIds;
            this.makeBookableDialog.open({});
        }
    }
}
