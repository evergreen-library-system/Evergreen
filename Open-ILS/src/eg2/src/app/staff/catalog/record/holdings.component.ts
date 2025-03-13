import {Component, OnInit, Input, ViewChild, ViewEncapsulation
} from '@angular/core';
import {Router} from '@angular/router';
import {Observable, Observer, of, EMPTY} from 'rxjs';
import {map, tap, concatMap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {StaffCatalogService} from '../catalog.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
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
import {CopyTagsDialogComponent
} from '@eg/staff/share/holdings/copy-tags-dialog.component';
import {CopyNotesDialogComponent
} from '@eg/staff/share/holdings/copy-notes-dialog.component';
import {ReplaceBarcodeDialogComponent
} from '@eg/staff/share/holdings/replace-barcode-dialog.component';
import {DeleteHoldingDialogComponent
} from '@eg/staff/share/holdings/delete-volcopy-dialog.component';
import {BucketDialogComponent
} from '@eg/staff/share/buckets/bucket-dialog.component';
import {ConjoinedItemsDialogComponent
} from '@eg/staff/share/holdings/conjoined-items-dialog.component';
import {MakeBookableDialogComponent
} from '@eg/staff/share/booking/make-bookable-dialog.component';
import {TransferItemsComponent
} from '@eg/staff/share/holdings/transfer-items.component';
import {TransferHoldingsComponent
} from '@eg/staff/share/holdings/transfer-holdings.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';


// The holdings grid models a single HoldingsTree, composed of HoldingsTreeNodes
// flattened on-demand into a list of HoldingEntry objects.
export class HoldingsTreeNode {
    children: HoldingsTreeNode[];
    nodeType: 'org' | 'callNum' | 'copy';
    target: any;
    parentNode: HoldingsTreeNode;
    expanded: boolean;
    copyCount: number;
    callNumCount: number;
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

export class HoldingsEntry {
    index: number;
    // org unit shortname, call number label, or copy barcode
    locationLabel: string;
    // location label indentation depth
    locationDepth: number | null;
    callNumCount: number | null;
    copyCount: number | null;
    callNumberLabel: string;
    copy: IdlObject;
    callNum: IdlObject;
    circ: IdlObject;
    treeNode: HoldingsTreeNode;
}

@Component({
    selector: 'eg-holdings-maintenance',
    templateUrl: 'holdings.component.html',
    styleUrls: ['holdings.component.css'],
    encapsulation: ViewEncapsulation.None
})
export class HoldingsMaintenanceComponent implements OnInit {

    initDone = false;
    gridDataSource: GridDataSource;
    gridTemplateContext: any;
    @ViewChild('holdingsGrid', { static: true }) holdingsGrid: GridComponent;

    // Manage visibility of various sub-sections
    @ViewChild('callNumsCheckbox', { static: true })
    private callNumsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('copiesCheckbox', { static: true })
    private copiesCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyCallNumsCheckbox', { static: true })
    private emptyCallNumsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyLibsCheckbox', { static: true })
    private emptyLibsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('markDamagedDialog', { static: true })
    private markDamagedDialog: MarkDamagedDialogComponent;
    @ViewChild('markMissingDialog', { static: true })
    private markMissingDialog: MarkMissingDialogComponent;
    @ViewChild('copyAlertsDialog', { static: true })
    private copyAlertsDialog: CopyAlertsDialogComponent;
    @ViewChild('copyTagsDialog', {static: false})
    private copyTagsDialog: CopyTagsDialogComponent;
    @ViewChild('copyNotesDialog', {static: false})
    private copyNotesDialog: CopyNotesDialogComponent;
    @ViewChild('replaceBarcode', { static: true })
    private replaceBarcode: ReplaceBarcodeDialogComponent;
    @ViewChild('deleteHolding', { static: true })
    private deleteHolding: DeleteHoldingDialogComponent;
    @ViewChild('bucketDialog', { static: true })
    private bucketDialog: BucketDialogComponent;
    @ViewChild('conjoinedDialog', { static: true })
    private conjoinedDialog: ConjoinedItemsDialogComponent;
    @ViewChild('makeBookableDialog', { static: true })
    private makeBookableDialog: MakeBookableDialogComponent;
    @ViewChild('transferItems', {static: false})
    private transferItems: TransferItemsComponent;
    @ViewChild('transferHoldings', {static: false})
    private transferHoldings: TransferHoldingsComponent;
    @ViewChild('transferAlert', {static: false})
    private transferAlert: AlertDialogComponent;

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

    cellTextGenerator: GridCellTextGenerator;
    orgClassCallback: (orgId: number) => string;
    marked_orgs: number[] = [];

    copyCounts: {[orgId: number]: {}} = {};

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

    // The context org may come from a workstation setting.
    // Wait for confirmation from the org-select (via onchange in this
    // case) that the desired context org unit has been found.
    contextOrgLoaded = false;

    constructor(
        private router: Router,
        private org: OrgService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private net: NetService,
        private auth: AuthService,
        private staffCat: StaffCatalogService,
        private store: ServerStoreService,
        private localStore: StoreService,
        private holdings: HoldingsService,
        private broadcaster: BroadcastService,
        private anonCache: AnonCacheService
    ) {
        // Set some sane defaults before settings are loaded.
        this.gridDataSource = new GridDataSource();
        this.refreshHoldings = true;
        this.renderFromPrefs = true;

        // TODO: need a separate setting for this?
        this.contextOrg = this.staffCat.searchContext.searchOrg;

        this.rowClassCallback = (row: any): string => {
            if (row.callNum) {
                if (row.copy) {
                    return 'holdings-copy-row';
                } else {
                    return 'holdings-callNum-row';
                }
            } else {
                // Add a generic org unit class and a depth-specific
                // class for styling different levels of the org tree.
                return 'holdings-org-row holdings-org-row-' +
                    row.treeNode.target.ou_type().depth();
            }
        };


        // Text-ify function for cells that use display templates.
        this.cellTextGenerator = {
            owner_label: row => row.locationLabel,
            holdable: row => row.copy ?
                this.gridTemplateContext.copyIsHoldable(row.copy) : ''
        };

        this.orgClassCallback = (orgId: number): string => {
            if (this.marked_orgs.includes(orgId)) { return 'font-weight-bold'; }
            return '';
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
        // console.debug('HoldingsComponent, ngOnInit(), this', this);
        this.initDone = true;

        this.broadcaster.listen('eg.holdings.update').subscribe(data => {
            if (data && data.records && data.records.includes(this.recordId)) {
                this.hardRefresh();
                // A hard refresh is needed to accommodate cases where
                // a new call number is created for a subset of copies.
                // We may revisit this later and use soft refresh
                // (below) vs. hard refresh (above) depending on what
                // specifically is changed.
                // this.refreshHoldings = true;
                // this.holdingsGrid.reload();
            }
        });

        // These are pre-cached via the catalog resolver.
        const settings = this.store.getItemBatchCached([
            'cat.holdings_show_empty_org',
            'cat.holdings_show_empty',
            'cat.holdings_show_copies',
            'cat.holdings_show_vols'
        ]);

        // Show call numbers by default when no preference is set.
        let showCallNums = settings['cat.holdings_show_vols'];
        if (showCallNums === null) { showCallNums = true; }

        this.callNumsCheckbox.checked(showCallNums);
        this.copiesCheckbox.checked(settings['cat.holdings_show_copies']);
        this.emptyCallNumsCheckbox.checked(settings['cat.holdings_show_empty']);
        this.emptyLibsCheckbox.checked(settings['cat.holdings_show_empty_org']);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            if (!this.contextOrgLoaded) { return EMPTY; }
            return this.fetchHoldings(pager);
        };

        this.net.request(
            'open-ils.search',
            'open-ils.search.biblio.copy_counts.retrieve.staff',
            this.recordId
        ).toPromise().then(result => {
            result.forEach(copy_count => {
                this.marked_orgs.push(copy_count[0]);
            });
        });
    }

    // No data is loaded until the first occurrence of the org change handler
    contextOrgChanged(org: IdlObject) {
        this.contextOrgLoaded = true;
        this.contextOrg = org;
        this.hardRefresh();
    }

    hardRefresh() {
        // console.debug('HoldingsComponent, hardRefresh()');
        this.renderFromPrefs = true;
        this.refreshHoldings = true;
        this.initHoldingsTree();
        this.holdingsGrid.reload();
    }

    toggleShowCopies(value: boolean) {
        this.store.setItem('cat.holdings_show_copies', value);
        if (value) {
            // Showing copies implies showing call numbers
            this.callNumsCheckbox.checked(true);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowCallNums(value: boolean) {
        this.store.setItem('cat.holdings_show_vols', value);
        if (!value) {
            // Hiding call numbers implies hiding empty call numbers and copies.
            this.copiesCheckbox.checked(false);
            this.emptyCallNumsCheckbox.checked(false);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowEmptyCallNums(value: boolean) {
        this.store.setItem('cat.holdings_show_empty', value);
        if (value) {
            this.callNumsCheckbox.checked(true);
        }
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    toggleShowEmptyLibs(value: boolean) {
        this.store.setItem('cat.holdings_show_empty_org', value);
        this.renderFromPrefs = true;
        this.holdingsGrid.reload();
    }

    getRowPaddingDepth(row) {
        let depth = row.locationDepth;
        // let leaf nodes line up with their parents
        if (row.copy || row.treeNode.children.length === 0) {
            depth = depth - 1;
        }
        return depth;
    }

    onRowActivate(row: any) {
        if (row.copy) {
            this.openHoldingEdit([row], true, false);
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
            callNum: {},
            copy: {}
        };

        this.holdingsTree = new HoldingsTree();
        this.holdingsTree.root.nodeType = 'org';
        this.holdingsTree.root.target = this.org.root();
        this.treeNodeCache.org[this.org.root().id()] = this.holdingsTree.root;

        traverseOrg(this.holdingsTree.root);
    }

    // Org node children are sorted by call number nodes attached to the org unit first,
    // followed by child org unit nodes. Peers are sorted alphabetically by label.
    // Example: If SYS2-BR3 has holdings but also has a bookmobile SYS2-BR3-BM1
    // that has its own holdings then the hierarchy should display as:
    // SYS2
    // - BR3
    // - - MR248 (BR3's holdings)
    // - - BM1
    // - - - MR248 (BM1's holdings)

    sortOrgNodeChildren(node: HoldingsTreeNode) {
        node.children = node.children.sort((a, b) => {
            if (a.nodeType === 'org') {
                if (b.nodeType === 'org') {
                    return a.target.shortname() < b.target.shortname() ? -1 : 1;
                } else {
                    return 1;
                }
            } else if (b.nodeType === 'org') {
                return -1;
            } else {
                // TODO: should this use label sortkey instead of
                // the compiled call number label?
                return a.target._label < b.target._label ? -1 : 1;
            }
        });
    }

    // Sets call number and copy count sums to nodes that need it.
    // Applies the initial expansed state of each container node.
    setTreeCounts(node: HoldingsTreeNode) {

        if (node.nodeType === 'org') {
            node.copyCount = this.copyCounts[node.target.id() + ''].copies;
            node.callNumCount = this.copyCounts[node.target.id() + ''].call_numbers;
        } else if (node.nodeType === 'callNum') {
            node.copyCount = 0;
        }

        let hasChildOrgWithData = false;
        let hasChildOrgSansData = false;
        node.children.forEach(child => {
            this.setTreeCounts(child);
            if (node.nodeType === 'org') {
                if (child.nodeType !== 'callNum') {
                    hasChildOrgWithData = child.callNumCount > 0;
                    hasChildOrgSansData = child.callNumCount === 0;
                }
            } else if (node.nodeType === 'callNum') {
                node.copyCount = node.children.length;
                if (this.renderFromPrefs) {
                    node.expanded = this.copiesCheckbox.checked();
                }
            }
        });

        if (this.renderFromPrefs && node.nodeType === 'org') {
            if (node.copyCount > 0 && this.callNumsCheckbox.checked()) {
                node.expanded = true;
            } else if (node.callNumCount > 0 && this.emptyCallNumsCheckbox.checked()) {
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
                if (node.callNumCount === 0
                    && !this.emptyLibsCheckbox.checked()) {
                    return;
                }
                entry.locationLabel = node.target.shortname();
                entry.locationDepth = node.target.ou_type().depth();
                entry.copyCount = node.copyCount;
                entry.callNumCount = node.callNumCount;
                this.sortOrgNodeChildren(node);
                break;

            case 'callNum':
                if (this.renderFromPrefs) {
                    if (!this.callNumsCheckbox.checked()) {
                        return;
                    }
                    if (node.copyCount === 0
                        && !this.emptyCallNumsCheckbox.checked()) {
                        return;
                    }
                }
                entry.locationLabel = node.target._label;
                entry.locationDepth = node.parentNode.target.ou_type().depth() + 1;
                entry.callNumberLabel = entry.locationLabel;
                entry.callNum = node.target;
                entry.copyCount = node.copyCount;
                break;

            case 'copy':
                entry.locationLabel = node.target.barcode();
                entry.locationDepth = node.parentNode.parentNode.target.ou_type().depth() + 2;
                entry.callNumberLabel = node.parentNode.target.label(); // TODO
                entry.callNum = node.parentNode.target;
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

    // Grab call numbers, copies, and related data.
    fetchHoldings(pager: Pager): Observable<any> {
        if (!this.recordId || this.recordId === -1) { return of([]); }

        return new Observable<any>(observer => {

            if (!this.refreshHoldings) {
                this.flattenHoldingsTree(observer);
                return;
            }

            this.itemCircsNeeded = [];
            // Track vol IDs for the current fetch so we can prune
            // any that were deleted in an out-of-band update.
            const volsFetched: number[] = [];

            return this.net.request(
                'open-ils.search',
                'open-ils.search.biblio.record.copy_counts.global.staff',
                this.recordId
            ).pipe(
                tap(counts => this.copyCounts = counts),
                concatMap(_ => {

                    return this.pcrud.search('acn',
                        {   record: this.recordId,
                            owning_lib: this.org.fullPath(this.contextOrg, true),
                            deleted: 'f',
                            label: {'!=' : '##URI##'}
                        }, {
                            flesh: 3,
                            flesh_fields: {
                                acp: ['status', 'location', 'circ_lib', 'parts', 'notes',
                                    'tags', 'age_protect', 'copy_alerts', 'latest_inventory',
                                    'total_circ_count', 'last_circ'],
                                acn: ['prefix', 'suffix', 'copies'],
                                acli: ['inventory_workstation']
                            }
                        },
                        {authoritative: true}
                    );
                })
            ).subscribe(
                callNum => {
                    this.appendCallNum(callNum);
                    volsFetched.push(callNum.id());
                },
                (err: unknown) => {},
                ()  => {
                    this.refreshHoldings = false;
                    this.pruneVols(volsFetched);
                    this.fetchCircs().then(
                        ok => this.flattenHoldingsTree(observer)
                    );
                }
            );
        });
    }

    // Remove vols that were deleted out-of-band, via edit, merge, etc.
    pruneVols(volsFetched: number[]) {

        const toRemove: number[] = []; // avoid modifying mid-loop
        Object.keys(this.treeNodeCache.callNum).forEach(volId => {
            const id = Number(volId);
            if (!volsFetched.includes(id)) {
                toRemove.push(id);
            }
        });

        if (toRemove.length === 0) { return; }

        const pruneNodes = (node: HoldingsTreeNode) => {
            if (node.nodeType === 'callNum' &&
                toRemove.includes(node.target.id())) {

                console.debug('pruning deleted vol:', node.target.id());

                // Remove this node from the parents list of children
                node.parentNode.children =
                    node.parentNode.children.filter(
                        c => c.target.id() !== node.target.id());

            } else {
                node.children.forEach(c => pruneNodes(c));
            }
        };

        // remove from cache
        toRemove.forEach(volId => delete this.treeNodeCache.callNum[volId]);

        // remove from tree
        pruneNodes(this.holdingsTree.root);

        // refresh tree / grid
        this.holdingsGrid.reload();
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

    // Compile prefix + label + suffix into field callNum._label;
    setCallNumLabel(callNum: IdlObject) {
        const pfx = callNum.prefix() ? callNum.prefix().label() : '';
        const sfx = callNum.suffix() ? callNum.suffix().label() : '';
        callNum._label = pfx ? pfx + ' ' : '';
        callNum._label += callNum.label();
        callNum._label += sfx ? ' ' + sfx : '';
    }

    // Create the tree node for the call number if it doesn't already exist.
    // Do the same for its linked copies.
    appendCallNum(callNum: IdlObject) {
        let callNumNode = this.treeNodeCache.callNum[callNum.id()];
        this.setCallNumLabel(callNum);

        if (callNumNode) {
            const pNode = this.treeNodeCache.org[callNum.owning_lib()];
            if (callNumNode.parentNode.target.id() !== pNode.target.id()) {
                callNumNode.parentNode = pNode;
                callNumNode.parentNode.children.push(callNumNode);
            }
        } else {
            callNumNode = new HoldingsTreeNode();
            callNumNode.nodeType = 'callNum';
            callNumNode.parentNode = this.treeNodeCache.org[callNum.owning_lib()];
            callNumNode.parentNode.children.push(callNumNode);
            this.treeNodeCache.callNum[callNum.id()] = callNumNode;
        }

        callNumNode.target = callNum;

        callNum.copies()
            .filter((copy: IdlObject) => (copy.deleted() !== 't'))
            .sort((a: IdlObject, b: IdlObject) => a.barcode() < b.barcode() ? -1 : 1)
            .forEach((copy: IdlObject) => this.appendCopy(callNumNode, copy));
    }

    // Find or create a copy node.
    appendCopy(callNumNode: HoldingsTreeNode, copy: IdlObject) {
        let copyNode = this.treeNodeCache.copy[copy.id()];

        if (copyNode) {
            const oldParent = copyNode.parentNode;
            if (oldParent.target.id() !== callNumNode.target.id()) {
                // TODO: copy changed owning call number.  Remove it from
                // the previous call number before adding to the new call number.
                copyNode.parentNode = callNumNode;
                callNumNode.children.push(copyNode);
            }
        } else {
            // New node required
            copyNode = new HoldingsTreeNode();
            copyNode.nodeType = 'copy';
            callNumNode.children.push(copyNode);
            copyNode.parentNode = callNumNode;
            this.treeNodeCache.copy[copy.id()] = copyNode;
        }

        copyNode.target = copy;
        const stat = Number(copy.status().id());
        copy._monograph_parts = '';
        if (copy.parts().length > 0) {
            copy._monograph_parts =
                copy.parts().map(p => p.label()).join(',');
        }

        // Ignore alerts that have already been ACK'ed
        // Over a long enough time, this list could grow large, so
        // consider fetching non-ack'ed copy alerts separately.
        copy.copy_alerts(copy.copy_alerts().filter(a => !a.ack_time()));

        // eslint-disable-next-line no-magic-numbers
        if (stat === 1 /* checked out */ || stat === 16 /* long overdue */) {
            // Avoid looking up circs on items that are not checked out.
            this.itemCircsNeeded.push(copy);
        }
    }

    // Which copies in the grid are selected.
    selectedCopyIds(rows: HoldingsEntry[], skipStatus?: number): number[] {
        const result = this.selectedCopies(rows, skipStatus).map(c => Number(c.id()));
        // console.debug('Holdings: selectedCopyIds; rows, result', rows, result);
        return result;
    }

    selectedVolIds(rows: HoldingsEntry[]): number[] {
        return rows
            .filter(r => Boolean(r.callNum))
            .map(r => Number(r.callNum.id()));
    }

    selectedCopies(rows: HoldingsEntry[], skipStatus?: number): IdlObject[] {
        let copyRows = rows.filter(r => Boolean(r.copy)).map(r => r.copy);
        // console.debug('Holdings: selectedCopies(); rows, copyRows pre-status filter', rows, copyRows);
        if (skipStatus) {
            copyRows = copyRows.filter(
                c => Number(c.status().id()) !== Number(skipStatus));
        }
        // console.debug('Holdings: selectedCopies(); rows, copyRows post-status filter', rows, copyRows);
        return copyRows;
    }

    selectedCallNumIds(rows: HoldingsEntry[]): number[] {
        return this.selectedCallNums(rows).map(cn => cn.id());
    }

    selectedCallNums(rows: HoldingsEntry[]): IdlObject[] {
        return rows
            .filter(r => r.treeNode.nodeType === 'callNum')
            .map(r => r.callNum);
    }


    async showMarkDamagedDialog(rows: HoldingsEntry[]) {
        // eslint-disable-next-line no-magic-numbers
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
                (dismiss: unknown) => markNext(ids)
            );
        };

        await markNext(copyIds);
        if (rowsModified) {
            this.refreshHoldings = true;
            this.holdingsGrid.reload();
        }
    }

    showMarkMissingDialog(rows: any[]) {
        // eslint-disable-next-line no-magic-numbers
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
                (dismissed: unknown) => {} // avoid console errors
            );
        }
    }

    // Mark record, library, and potentially the selected call number
    // as the current transfer target.
    markLibCnForTransfer(rows: HoldingsEntry[]) {
        if (rows.length === 0) {
            return;
        }

        // Action may only apply to a single org or call number row.
        const node = rows[0].treeNode;
        if (node.nodeType === 'copy') { return; }

        let orgId: number;

        if (node.nodeType === 'org') {
            orgId = node.target.id();

            // Clear call number target when performed on an org unit row
            this.localStore.removeLocalItem('eg.cat.transfer_target_vol');

        } else if (node.nodeType === 'callNum') {

            // All call number nodes are children of org nodes.
            orgId = node.parentNode.target.id();

            // Add call number target when performed on a call number row.
            this.localStore.setLocalItem(
                'eg.cat.transfer_target_vol', node.target.id());
        }

        // Track lib and record to support transfering items from
        // a different bib record to this record at the selected
        // owning lib.
        this.localStore.setLocalItem('eg.cat.transfer_target_lib', orgId);
        this.localStore.setLocalItem('eg.cat.transfer_target_record', this.recordId);
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

    openHoldingEdit(rows: HoldingsEntry[], hideVols: boolean, hideCopies: boolean) {

        // Avoid adding call number edit entries for call numbers
        // that are already represented by selected items.

        const copies = this.selectedCopies(rows);
        const copyVols = copies.map(c => Number(c.call_number()));

        const volIds = [];
        this.selectedVolIds(rows).forEach(id => {
            if (!copyVols.includes(id)) {
                volIds.push(id);
            }
        });

        this.holdings.spawnAddHoldingsUi(
            this.recordId,
            volIds,
            null,
            copies.map(c => Number(c.id())),
            hideCopies,
            hideVols
        );
    }

    openHoldingAdd(rows: HoldingsEntry[], addCallNums: boolean, addCopies: boolean) {

        // The user may select a set of call numbers by selecting call
        // number and/or item rows.  Owning libs for new call numbers may
        // also come from org unit row selection.
        const orgs = {};
        const callNums = [];
        rows.forEach(r => {
            if (r.treeNode.nodeType === 'callNum') {
                callNums.push(r.callNum);

            } else if (r.treeNode.nodeType === 'copy') {
                callNums.push(r.treeNode.parentNode.target);

            } else if (r.treeNode.nodeType === 'org') {
                const org = r.treeNode.target;
                if (org.ou_type().can_have_vols() === 't') {
                    orgs[org.id()] = true;
                }
            }
        });

        if (addCopies && !addCallNums) {
            // Adding copies to an existing set of call numbers.
            if (callNums.length > 0) {
                const callNumIds = callNums.map(v => Number(v.id()));
                this.holdings.spawnAddHoldingsUi(this.recordId, callNumIds);
            }

        } else if (addCallNums) {
            const entries = [];

            // Use selected call numbers as basis for new call numbers.
            callNums.forEach(v =>
                entries.push({label: v.label(), owner: v.owning_lib()}));

            // Use selected org units as owning libs for new call numbers
            Object.keys(orgs).forEach(id => entries.push({owner: id}));

            if (entries.length === 0) {
                // Otherwise create new call numbers for "here"
                entries.push({owner: this.auth.user().ws_ou()});
            }

            this.holdings.spawnAddHoldingsUi(
                this.recordId, null, entries, null, !addCopies);
        }
    }

    openItemAlerts(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        // console.debug('Holdings: openItemAlerts; rows, copyIds', rows, copyIds);
        if (copyIds.length === 0) { return; }

        this.copyAlertsDialog.copyIds = copyIds;
        this.copyAlertsDialog.copies = [];
        this.copyAlertsDialog.clearPending();
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(
            changes => {
                // console.debug('HoldingsComponent: copyAlertsDialog, changes?', changes);
                this.hardRefresh();
            }
        );
    }

    openItemTags(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyTagsDialog.copyIds = copyIds;
        this.copyTagsDialog.copies = [];
        this.copyTagsDialog.clearPending();
        this.copyTagsDialog.open({size: 'lg'}).subscribe(
            changes => {
                // console.debug('HoldingsComponent: copyTagsDialog, changes?', changes);
                this.hardRefresh();
            }
        );
    }

    openItemNotes(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length === 0) { return; }

        this.copyNotesDialog.copyIds = copyIds;
        this.copyNotesDialog.copies = [];
        this.copyNotesDialog.clearPending();
        this.copyNotesDialog.open({size: 'lg'}).subscribe(
            changes => {
                // console.debug('HoldingsComponent: copyNotesDialog, changes?', changes);
                this.hardRefresh();
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

    // mode 'callNums' -- only delete empty call numbers
    // mode 'copies' -- only delete selected copies
    // mode 'both' -- delete selected copies and selected call numbers, plus all
    // copies linked to selected call numbers, regardless of whether they are selected.
    deleteHoldings(rows: HoldingsEntry[], mode: 'callNums' | 'copies' | 'both') {
        const callNumHash: any = {};

        if (mode === 'callNums' || mode === 'both') {
            // Collect the call numbers to be deleted.
            rows.filter(r => r.treeNode.nodeType === 'callNum').forEach(r => {
                const callNum = this.idl.clone(r.callNum);
                if (mode === 'callNums') {
                    if (callNum.copies().length > 0) {
                        // cannot delete non-empty call number in this mode.
                        return;
                    }
                } else {
                    callNum.copies().forEach(c => c.isdeleted(true));
                }
                callNum.isdeleted(true);
                callNumHash[callNum.id()] = callNum;
            });
        }

        if (mode === 'copies' || mode === 'both') {
            // Collect the copies to be deleted, including their call numbers
            // since the API expects fleshed call number objects.
            rows.filter(r => r.treeNode.nodeType === 'copy').forEach(r => {
                const callNum = r.treeNode.parentNode.target;
                if (!callNumHash[callNum.id()]) {
                    callNumHash[callNum.id()] = this.idl.clone(callNum);
                    callNumHash[callNum.id()].copies([]);
                }
                const copy = this.idl.clone(r.copy);
                copy.isdeleted(true);
                callNumHash[callNum.id()].copies().push(copy);
            });
        }

        if (Object.keys(callNumHash).length === 0) {
            // No data to process.
            return;
        }

        // Note forceDeleteCopies should not be necessary here, since we
        // manually marked all copies as deleted on deleted call numbers in
        // "both" mode.
        this.deleteHolding.forceDeleteCopies = mode === 'both';
        this.deleteHolding.callNums = Object.values(callNumHash);
        this.deleteHolding.open({size: 'sm'}).subscribe(
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
            this.router.navigate(
                ['staff', 'booking', 'create_reservation', 'for_resource', rows.filter(r => Boolean(r.copy))[0].copy.barcode()]
            );
        }
    }

    makeBookable(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            this.makeBookableDialog.copyIds = copyIds;
            this.makeBookableDialog.open({});
        }
    }

    manageReservations(rows: HoldingsEntry[]) {
        const copyIds = this.selectedCopyIds(rows);
        if (copyIds.length > 0) {
            this.router.navigate(
                ['staff', 'booking', 'manage_reservations', 'by_resource', rows.filter(r => Boolean(r.copy))[0].copy.barcode()]
            );
        }
    }

    transferSelectedItems(rows: HoldingsEntry[]) {
        if (rows.length === 0) { return; }

        const cnId =
            this.localStore.getLocalItem('eg.cat.transfer_target_vol');

        const orgId =
            this.localStore.getLocalItem('eg.cat.transfer_target_lib');

        const recId =
            this.localStore.getLocalItem('eg.cat.transfer_target_record');

        let promise;

        if (cnId) { // Direct call number transfer

            const itemIds = this.selectedCopyIds(rows);
            promise = this.transferItems.transferItems(itemIds, cnId);

        } else if (orgId && recId) { // "Auto" transfer

            // Clone the items to be modified to avoid any unexpected
            // modifications and fesh the call numbers.
            const items = this.idl.clone(this.selectedCopies(rows));
            items.forEach(i => i.call_number(
                this.treeNodeCache.callNum[i.call_number()].target));

            console.log(items);
            promise = this.transferItems.autoTransferItems(items, recId, orgId);

        } else {
            promise = this.transferAlert.open().toPromise();
        }

        promise.then(success => success ?  this.hardRefresh() : null);
    }

    transferSelectedHoldings(rows: HoldingsEntry[]) {
        const callNums = this.selectedCallNums(rows);
        if (callNums.length === 0) { return; }

        const orgId =
            this.localStore.getLocalItem('eg.cat.transfer_target_lib');

        let recId =
            this.localStore.getLocalItem('eg.cat.transfer_target_record');

        if (orgId) {
            // When transferring holdings (call numbers) between org units,
            // limit transfers to within the current record.
            recId = this.recordId;

        } else if (!recId) {
            // No destinations applied.
            return this.transferAlert.open();
        }

        this.transferHoldings.targetRecId = recId;
        this.transferHoldings.targetOrgId = orgId;
        this.transferHoldings.callNums = callNums;

        this.transferHoldings.transferHoldings()
            .then(success => success ?  this.hardRefresh() : null);
    }
}

