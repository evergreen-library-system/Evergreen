import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';

/* Models the holdings tree and manages related data shared
 * volcopy across components. */

export class HoldingsTreeNode {
    children: HoldingsTreeNode[];
    nodeType: 'org' | 'vol' | 'copy';
    target: any;
    parentNode: HoldingsTreeNode;
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

export class VolCopyContext {

    holdings: HoldingsTree = new HoldingsTree();
    org: OrgService; // injected

    sessionType: 'copy' | 'vol' | 'record' | 'mixed';

    // Edit content comes from a cached session
    session: string;

    // Note in multi-record mode this value will be unset.
    recordId: number;

    // Load specific call number by ID.
    volId: number;

    // Load specific copy by ID.
    copyId: number;

    fastAdd: boolean;

    volsToDelete: IdlObject[] = [];
    copiesToDelete: IdlObject[] = [];

    reset() {
        this.holdings = new HoldingsTree();
        this.volsToDelete = [];
        this.copiesToDelete = [];
    }

    orgNodes(): HoldingsTreeNode[] {
        return this.holdings.root.children;
    }

    volNodes(): HoldingsTreeNode[] {
        let vols = [];
        this.orgNodes().forEach(orgNode =>
            vols = vols.concat(orgNode.children));
        return vols;
    }

    copyList(): IdlObject[] {
        let copies = [];
        this.volNodes().forEach(volNode => {
            copies = copies.concat(volNode.children.map(c => c.target));
        });
        return copies;
    }

    // Returns IDs for all bib records represented in our holdings tree.
    getRecordIds(): number[] {
        const idHash: {[id: number]: boolean} = {};

        this.volNodes().forEach(volNode =>
            idHash[volNode.target.record()] = true);

        return Object.keys(idHash).map(id => Number(id));
    }

    // Returns IDs for all volume owning libs represented in our holdings tree.
    getOwningLibIds(): number[] {
        try {
            const idHash: {[id: number]: boolean} = {};

            this.volNodes().forEach(volNode => {
                idHash[volNode.target.owning_lib()] = true;
            });

            return Object.keys(idHash).map(id => Number(id));
        } catch (error) {
            console.error('Error in getOwningLibIds:', error);
            return [];
        }
    }

    // When working on exactly one record, set our recordId value.
    setRecordId() {
        if (!this.recordId) {
            const ids = this.getRecordIds();
            if (ids.length === 1) {
                this.recordId = ids[0];
            }
        }
    }

    // Adds an org unit node; unsorted.
    findOrCreateOrgNode(orgId: number): HoldingsTreeNode {

        const existing: HoldingsTreeNode =
            this.orgNodes().filter(n => n.target.id() === orgId)[0];

        if (existing) { return existing; }

        const node: HoldingsTreeNode = new HoldingsTreeNode();
        node.nodeType = 'org';
        node.target = this.org.get(orgId);
        node.parentNode = this.holdings.root;

        this.orgNodes().push(node);

        return node;
    }

    findOrCreateVolNode(vol: IdlObject): HoldingsTreeNode {
        const orgId = vol.owning_lib();
        const orgNode = this.findOrCreateOrgNode(orgId);

        const existing = orgNode.children.filter(
            n => n.target.id() === vol.id())[0];

        if (existing) { return existing; }

        const node: HoldingsTreeNode = new HoldingsTreeNode();
        node.nodeType = 'vol';
        node.target = vol;
        node.parentNode = orgNode;

        orgNode.children.push(node);

        return node;
    }


    findOrCreateCopyNode(copy: IdlObject): HoldingsTreeNode {
        const volNode = this.findOrCreateVolNode(copy.call_number());

        const existing = volNode.children.filter(
            c => c.target.id() === copy.id())[0];

        if (existing) { return existing; }

        const node: HoldingsTreeNode = new HoldingsTreeNode();
        node.nodeType = 'copy';
        node.target = copy;
        node.parentNode = volNode;

        volNode.children.push(node);

        return node;
    }

    removeVolNode(volId: number) {
        this.orgNodes().forEach(orgNode => {
            for (let idx = 0; idx < orgNode.children.length; idx++) {
                if (orgNode.children[idx].target.id() === volId) {
                    orgNode.children.splice(idx, 1);
                    break;
                }
            }
        });
    }

    removeCopyNode(copyId: number) {
        this.volNodes().forEach(volNode => {
            for (let idx = 0; idx < volNode.children.length; idx++) {
                if (volNode.children[idx].target.id() === copyId) {
                    volNode.children.splice(idx, 1);
                    break;
                }
            }
        });
    }

    sortHoldings() {

        this.orgNodes().forEach(orgNode => {
            orgNode.children.forEach(volNode => {

                // Sort copys by barcode code
                volNode.children = volNode.children.sort((c1, c2) =>
                    c1.target.barcode() < c2.target.barcode() ? -1 : 1);

            });

            // Sort call numbers by label
            orgNode.children = orgNode.children.sort((c1, c2) =>
                c1.target.label() < c2.target.label() ? -1 : 1);
        });

        // sort org units by shortname
        this.holdings.root.children = this.orgNodes().sort((o1, o2) =>
            o1.target.shortname() < o2.target.shortname() ? -1 : 1);
    }

    changesPending(): boolean {
        const modified = (o: IdlObject): boolean => {
            return o.isnew() || o.ischanged() || o.isdeleted();
        };

        if (this.volNodes().filter(n => modified(n.target)).length > 0) {
            return true;
        }

        if (this.copyList().filter(c => modified(c)).length > 0) {
            return true;
        }

        return false;
    }
}
