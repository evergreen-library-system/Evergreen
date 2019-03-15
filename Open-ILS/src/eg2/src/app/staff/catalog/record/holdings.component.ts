import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {StaffCatalogService} from '../catalog.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridToolbarCheckboxComponent} from '@eg/share/grid/grid-toolbar-checkbox.component';
import {ServerStoreService} from '@eg/core/server-store.service';


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
  templateUrl: 'holdings.component.html'
})
export class HoldingsMaintenanceComponent implements OnInit {

    recId: number;
    initDone = false;
    gridDataSource: GridDataSource;
    gridTemplateContext: any;
    @ViewChild('holdingsGrid') holdingsGrid: GridComponent;

    // Manage visibility of various sub-sections
    @ViewChild('volsCheckbox') volsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('copiesCheckbox') copiesCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyVolsCheckbox') emptyVolsCheckbox: GridToolbarCheckboxComponent;
    @ViewChild('emptyLibsCheckbox') emptyLibsCheckbox: GridToolbarCheckboxComponent;

    contextOrg: IdlObject;
    holdingsTree: HoldingsTree;
    holdingsTreeOrgCache: {[id: number]: HoldingsTreeNode};
    refreshHoldings: boolean;
    gridIndex: number;

    // List of copies whose due date we need to retrieve.
    itemCircsNeeded: IdlObject[];

    // When true draw the grid based on the stored preferences.
    // When not true, render based on the current "expanded" state of each node.
    // Rendering from prefs happens on initial load and when any prefs change.
    renderFromPrefs: boolean;
    rowClassCallback: (row: any) => string;

    @Input() set recordId(id: number) {
        this.recId = id;
        // Only force new data collection when recordId()
        // is invoked after ngInit() has already run.
        if (this.initDone) {
            this.refreshHoldings = true;
            this.holdingsGrid.reload();
        }
    }

    constructor(
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private staffCat: StaffCatalogService,
        private store: ServerStoreService
    ) {
        // Set some sane defaults before settings are loaded.
        this.contextOrg = this.org.get(this.auth.user().ws_ou());
        this.gridDataSource = new GridDataSource();
        this.refreshHoldings = true;
        this.renderFromPrefs = true;

        this.rowClassCallback = (row: any): string => {
             if (row.volume && !row.copy) {
                return 'bg-info';
            }
        }

        this.gridTemplateContext = {
            toggleExpandRow: (row: HoldingsEntry) => {
                row.treeNode.expanded = !row.treeNode.expanded;

                if (!row.treeNode.expanded) {
                    // When collapsing a node, all child nodes should be
                    // collapsed as well.
                    const traverse = (node: HoldingsTreeNode) => {
                        node.expanded = false;
                        node.children.forEach(traverse);
                    }
                    traverse(row.treeNode);
                }

                this.holdingsGrid.reload();
            },

            copyIsHoldable: (copy: IdlObject): boolean => {
                return copy.holdable() === 't'
                    && copy.location().holdable() === 't'
                    && copy.status().holdable() === 't';
            }
        }
    }

    ngOnInit() {
        this.initDone = true;

        // These are pre-cached via the resolver.
        const settings = this.store.getItemBatchCached([
            'cat.holdings_show_empty_org',
            'cat.holdings_show_empty',
            'cat.holdings_show_copies',
            'cat.holdings_show_vols'
        ]);

        this.volsCheckbox.checked(settings['cat.holdings_show_vols']);
        this.copiesCheckbox.checked(settings['cat.holdings_show_copies']);
        this.emptyVolsCheckbox.checked(settings['cat.holdings_show_empty']);
        this.emptyLibsCheckbox.checked(settings['cat.holdings_show_empty_org']);

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchHoldings(pager);
        };
    }

    ngAfterViewInit() {

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

        // The initial tree simply matches the org unit tree
        const traverseOrg = (node: HoldingsTreeNode) => {
            node.expanded = true;
            node.target.children().forEach((org: IdlObject) => {
                const nodeChild = new HoldingsTreeNode();
                nodeChild.nodeType = 'org';
                nodeChild.target = org;
                nodeChild.parentNode = node;
                node.children.push(nodeChild);
                this.holdingsTreeOrgCache[org.id()] = nodeChild;
                traverseOrg(nodeChild);
            });
        }

        this.holdingsTree = new HoldingsTree();
        this.holdingsTree.root.nodeType = 'org';
        this.holdingsTree.root.target = this.org.root();

        this.holdingsTreeOrgCache = {};
        this.holdingsTreeOrgCache[this.org.root().id()] = this.holdingsTree.root;

        traverseOrg(this.holdingsTree.root);
    }

    // Org node children are sorted with any child org nodes pushed to the
    // front, followed by the call number nodes sorted alphabetcially by label.
    // TODO: prefix/suffix
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
                return a.target.label() < b.target.label() ? -1 : 1;
            }
        });
    }

    // Sets call number and copy count sums to nodes that need it.
    // Applies the initial expansed state of each container node.
    setTreeCounts(node: HoldingsTreeNode) {

        if (node.nodeType === 'org') {
            node.copyCount = 0;
            node.volumeCount = 0;
        } else if(node.nodeType === 'volume') {
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

        switch(node.nodeType) {
            case 'org':
                if (this.renderFromPrefs && node.volumeCount === 0
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
                entry.locationLabel = node.target.label(); // TODO prefix/suffix
                entry.locationDepth = node.parentNode.target.ou_type().depth() + 1;
                entry.callNumberLabel = entry.locationLabel;
                entry.volume = node.target;
                entry.copyCount = node.copyCount;
                break;

            case 'copy':
                entry.locationLabel = node.target.barcode();
                entry.locationDepth = node.parentNode.parentNode.target.ou_type().depth() + 2;
                entry.callNumberLabel = node.parentNode.target.label() // TODO
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


    fetchHoldings(pager: Pager): Observable<any> {
        if (!this.recId) { return of([]); }

        return new Observable<any>(observer => {

            if (!this.refreshHoldings) {
                this.flattenHoldingsTree(observer);
                return;
            }

            this.initHoldingsTree();
            this.itemCircsNeeded = [];

            this.pcrud.search('acn',
                {   record: this.recId,
                    owning_lib: this.org.ancestors(this.contextOrg, true),
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
                }
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

    appendVolume(volume: IdlObject) {

        const volNode = new HoldingsTreeNode();
        volNode.parentNode = this.holdingsTreeOrgCache[volume.owning_lib()];
        volNode.parentNode.children.push(volNode);
        volNode.nodeType = 'volume';
        volNode.target = volume;

        volume.copies()
            .sort((a: IdlObject, b: IdlObject) => a.barcode() < b.barcode() ? -1 : 1)
            .forEach((copy: IdlObject) => {
                const copyNode = new HoldingsTreeNode();
                copyNode.parentNode = volNode;
                volNode.children.push(copyNode);
                copyNode.nodeType = 'copy';
                copyNode.target = copy;
                const stat = Number(copy.status().id());
                if (stat === 1 /* checked out */ || stat === 16 /* long overdue */) {
                    this.itemCircsNeeded.push(copy);
                }
            });
    }
}


