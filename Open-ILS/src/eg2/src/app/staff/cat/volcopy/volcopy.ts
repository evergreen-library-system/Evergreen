import {IdlObject, IdlService} from '@eg/core/idl.service';
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
    idl: IdlService; // why are these not in a constructor?

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

    newAlerts: IdlObject[] = [];
    changedAlerts: IdlObject[] = [];
    deletedAlerts: IdlObject[] = [];
    newNotes: IdlObject[] = [];
    deletedNotes: IdlObject[] = [];
    changedNotes: IdlObject[] = [];
    newTagMaps: IdlObject[] = [];
    changedTagMaps: IdlObject[] = [];
    deletedTagMaps: IdlObject[] = [];
    volsToDelete: IdlObject[] = [];
    copiesToDelete: IdlObject[] = [];

    reset() {
        this.holdings = new HoldingsTree();
        this.newAlerts = [];
        this.changedAlerts = [];
        this.newNotes = [];
        this.deletedNotes = [];
        this.changedNotes = [];
        this.newTagMaps = [];
        this.changedTagMaps = [];
        this.deletedTagMaps = [];
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

    updateInMemoryCopies() {
        console.debug('updateInMemoryCopies', this);
        this.updateInMemoryCopiesWithAlerts();
        this.updateInMemoryCopiesWithNotes();
        this.updateInMemoryCopiesWithTags();
    }

    updateInMemoryCopiesWithAlerts() {
        console.debug('updateInMemoryCopiesWithAlerts', this);
        this.copyList().forEach(copy => {
            this.updateInMemoryCopyWithAlerts(copy);
        });
    }

    updateInMemoryCopyWithAlerts(copy) {
        console.debug('updateInMemoryCopyWithAlerts, considering copy', copy.id(), copy);
        console.debug('with this.newAlerts', this.newAlerts.length, this.newAlerts);
        console.debug('with this.changedAlerts', this.changedAlerts.length, this.changedAlerts);
        console.debug('with this.deletedAlerts', this.deletedAlerts.length, this.deletedAlerts);

        // Initialize array if needed
        if (!copy.copy_alerts()) { copy.copy_alerts([]); }

        // -------------- Alerts

        this.newAlerts.forEach(alert => {
            if (alert === undefined) {
                console.error('Why?? alert = ', alert);
                return;
            }
            console.debug('considering newAlert', alert);
            const existingAlert = copy.copy_alerts().find(existing => alert.id() === existing.id());
            if (existingAlert) {
                console.debug('updating pending newAlert', existingAlert);
                existingAlert.isnew(true);
                existingAlert.copy(copy.id());
            } else {
                const newAlert = this.idl.clone(alert);
                newAlert.id(null);
                newAlert.isnew(true);
                newAlert.copy(copy.id());
                copy.copy_alerts(
                    copy.copy_alerts().concat(newAlert)
                );
            }
            copy.ischanged(true);
        });

        this.changedAlerts.forEach(changedAlert => {
            if (changedAlert === undefined) {
                console.error('Why?? changedAlert = ', changedAlert);
                return;
            }
            console.debug('considering changedAlert', changedAlert);
            let existingAlert = null;
            if ('originalAlertIds' in changedAlert) { // ProxyAlert
                console.debug('batch mode proxy');
                existingAlert = copy.copy_alerts().find(existing => changedAlert.originalAlertIds.includes(existing.id()));
            } else {
                console.debug('single-item mode not-a-proxy');
                existingAlert = copy.copy_alerts().find(existing => changedAlert.id() === existing.id());
            }
            if (existingAlert) {
                existingAlert.alert_type(changedAlert.alert_type());
                existingAlert.temp(changedAlert.temp());
                existingAlert.note(changedAlert.note());
                existingAlert.ack_time(changedAlert.ack_time());
                existingAlert.ack_staff(changedAlert.ack_staff());
                if (! (existingAlert.isnew() ?? false)) { existingAlert.ischanged(true); }
                console.debug('changing existing', existingAlert);
            } else {
                // I forget how this might happen, but just in case
                console.error('converting changedAlert to newAlert', changedAlert);
                const newAlert = this.idl.clone(changedAlert);
                // newAlert.id(null);
                newAlert.isnew(true);
                newAlert.copy(copy.id());
                copy.copy_alerts(
                    copy.copy_alerts().concat(newAlert)
                );
            }
            copy.ischanged(true);
        });

        copy.copy_alerts().forEach( c => c.isdeleted(false) ); // to accommodate undeletes
        this.deletedAlerts.forEach(deletedAlert => {
            if (deletedAlert === undefined) {
                console.error('Why?? deletedAlert = ', deletedAlert);
                return;
            }
            console.debug('considering deletedAlert', deletedAlert);
            let existingAlert = null;
            if ('originalAlertIds' in deletedAlert) { // ProxyAlert
                existingAlert = copy.copy_alerts().find(existing => deletedAlert.originalAlertIds.includes(existing.id()));
            } else {
                existingAlert = copy.copy_alerts().find(existing => deletedAlert.id() === existing.id());
            }
            if (existingAlert) {
                existingAlert.isdeleted(true);
            } else {
                console.warn('Could not find existing alert to match deleted alert');
            }
            copy.ischanged(true);
        });

        // what are we doing here?
        const counts = { 'new': 0, 'changed': 0, 'deleted': 0 };
        copy.copy_alerts().forEach(a => {
            counts.new += Number( a.isnew() ?? false); // who knew you could cast bools into numbers?
            counts.changed += Number( a.ischanged() ?? false); // but why do our methods here sometime return undefined? bleh
            counts.deleted += Number( a.isdeleted() ?? false);
        });
        console.debug('breakdown: ', { new: counts.new, changed: counts.changed, deleted: counts.deleted });
    }

    updateInMemoryCopiesWithNotes() {
        console.debug('updateInMemoryCopiesWithNotes', this);
        this.copyList().forEach(copy => {
            this.updateInMemoryCopyWithNotes(copy);
        });
    }

    updateInMemoryCopyWithNotes(copy) {
        console.debug('updateInMemoryCopyWithNotes, considering copy', copy.id(), copy);
        console.debug('with this.newNotes', this.newNotes.length, this.newNotes);
        console.debug('with this.changedNotes', this.changedNotes.length, this.changedNotes);
        console.debug('with this.deletedNotes', this.deletedNotes.length, this.deletedNotes);

        // Initialize array if needed
        if (!copy.notes()) { copy.notes([]); }

        // -------------- Notes

        this.newNotes.forEach(note => {
            if (note === undefined) {
                console.error('Why?? note = ', note);
                return;
            }
            console.debug('considering newNote', note);
            const existingNote = copy.notes().find(existing => note.id() === existing.id());
            if (existingNote) {
                console.debug('updating pending newNote', existingNote);
                existingNote.isnew(true);
                existingNote.owning_copy(copy.id());
            } else {
                const newNote = this.idl.clone(note);
                newNote.id(null);
                newNote.isnew(true);
                newNote.owning_copy(copy.id());
                copy.notes(
                    copy.notes().concat(newNote)
                );
            }
            copy.ischanged(true);
        });

        this.changedNotes.forEach(changedNote => {
            if (changedNote === undefined) {
                console.error('Why?? changedNote = ', changedNote);
                return;
            }
            console.debug('considering changedNote', changedNote);
            let existingNote = null;
            if ('originalNoteIds' in changedNote) { // ProxyNote
                console.debug('batch mode proxy');
                existingNote = copy.notes().find(existing => changedNote.originalNoteIds.includes(existing.id()));
            } else {
                console.debug('single-item mode not-a-proxy');
                existingNote = copy.notes().find(existing => changedNote.id() === existing.id());
            }
            if (existingNote) {
                existingNote.pub(changedNote.pub());
                existingNote.title(changedNote.title());
                existingNote.value(changedNote.value());
                if (! (existingNote.isnew() ?? false)) { existingNote.ischanged(true); }
                console.debug('changing existing', existingNote);
            } else {
                // I forget how this might happen, but just in case
                console.error('converting changedNote to newNote', changedNote);
                const newNote = this.idl.clone(changedNote);
                // newNote.id(null);
                newNote.isnew(true);
                newNote.owning_copy(copy.id());
                copy.notes(
                    copy.notes().concat(newNote)
                );
            }
            copy.ischanged(true);
        });

        copy.notes().forEach( c => c.isdeleted(false) ); // to accommodate undeletes
        this.deletedNotes.forEach(deletedNote => {
            if (deletedNote === undefined) {
                console.error('Why?? deletedNote = ', deletedNote);
                return;
            }
            console.debug('considering deletedNote', deletedNote);
            let existingNote = null;
            if ('originalNoteIds' in deletedNote) { // ProxyNote
                existingNote = copy.notes().find(existing => deletedNote.originalNoteIds.includes(existing.id()));
            } else {
                existingNote = copy.notes().find(existing => deletedNote.id() === existing.id());
            }
            if (existingNote) {
                existingNote.isdeleted(true);
            } else {
                console.warn('Could not find existing note to match deleted note');
            }
            copy.ischanged(true);
        });

        // what are we doing here?
        const counts = { 'new': 0, 'changed': 0, 'deleted': 0 };
        copy.notes().forEach(a => {
            counts.new += Number( a.isnew() ?? false); // who knew you could cast bools into numbers?
            counts.changed += Number( a.ischanged() ?? false); // but why do our methods here sometime return undefined? bleh
            counts.deleted += Number( a.isdeleted() ?? false);
        });
        console.debug('breakdown: ', { new: counts.new, changed: counts.changed, deleted: counts.deleted });
    }

    updateInMemoryCopiesWithTags() {
        console.debug('updateInMemoryCopiesWithTags', this);
        this.copyList().forEach(copy => {
            this.updateInMemoryCopyWithTags(copy);
        });
    }

    updateInMemoryCopyWithTags(copy) {
        console.debug('considering copy', copy.id(), copy);
        console.debug('with this.newTagMaps', this.newTagMaps.length, this.newTagMaps);
        console.debug('with this.changedTagMaps', this.changedTagMaps.length, this.changedTagMaps);
        console.debug('with this.deletedTagMaps', this.deletedTagMaps.length, this.deletedTagMaps);

        // Initialize array if needed
        if (!copy.tags()) { copy.tags([]); }

        // -------------- Tag Maps

        this.newTagMaps.forEach(tagMap => {
            if (tagMap === undefined) {
                console.error('Why?? tagMap = ', tagMap);
                return;
            }
            console.debug('considering newTagMap', tagMap);
            const existingTagMap = copy.tags().find(existing => tagMap.id() === existing.id());
            const collidingTagMaps = copy.tags().filter(
                colliding => this.idl.pkeyValue(tagMap.tag()) === this.idl.pkeyValue(colliding.tag())
            );
            if (existingTagMap) {
                console.debug('updating pending newTagMap', existingTagMap);
                existingTagMap.isnew(true);
                existingTagMap.copy(copy.id());
                copy.ischanged(true);
            } else if (collidingTagMaps.length > 0) {
                console.log(`Copy with ID ${ copy.id() }, already has a tag map for this tag; keeping it.`);
            } else {
                const newTagMap = this.idl.clone(tagMap);
                newTagMap.id(null);
                newTagMap.isnew(true);
                newTagMap.copy(copy.id());
                copy.tags(
                    copy.tags().concat(newTagMap)
                );
                copy.ischanged(true);
            }
        });

        this.changedTagMaps.forEach(changedTagMap => {
            if (changedTagMap === undefined) {
                console.error('Why?? changedTagMap = ', changedTagMap);
                return;
            }
            console.debug('considering changedTagMap', changedTagMap);
            let existingTagMap = null;
            if ('originalTagMapIds' in changedTagMap) { // ProxyTagMap
                console.debug('batch mode proxy');
                existingTagMap = copy.tags().find(existing => changedTagMap.originalTagMapIds.includes(existing.id()));
            } else {
                console.debug('single-item mode not-a-proxy');
                existingTagMap = copy.tags().find(existing => changedTagMap.id() === existing.id());
            }
            if (existingTagMap) {
                existingTagMap.tag(changedTagMap.tag());
                if (! (existingTagMap.isnew() ?? false)) { existingTagMap.ischanged(true); }
                console.debug('changing existing', existingTagMap);
            } else {
                // I forget how this might happen, but just in case
                console.error('converting changedTagMap to newTagMap', changedTagMap);
                const newTagMap = this.idl.clone(changedTagMap);
                // newTagMap.id(null);
                newTagMap.isnew(true);
                newTagMap.copy(copy.id());
                copy.tags(
                    copy.tags().concat(newTagMap)
                );
            }
            copy.ischanged(true);
        });

        copy.tags().forEach( c => c.isdeleted(false) ); // to accommodate undeletes
        this.deletedTagMaps.forEach(deletedTagMap => {
            if (deletedTagMap === undefined) {
                console.error('Why?? deletedTagMap = ', deletedTagMap);
                return;
            }
            console.debug('considering deletedTagMap', deletedTagMap);
            let existingTagMap = null;
            if ('originalTagMapIds' in deletedTagMap) { // ProxyTagMap
                existingTagMap = copy.tags().find(existing => deletedTagMap.originalTagMapIds.includes(existing.id()));
            } else {
                existingTagMap = copy.tags().find(existing => deletedTagMap.id() === existing.id());
            }
            if (existingTagMap) {
                existingTagMap.isdeleted(true); // should be redundant here, but just in case
                const matchingTagMaps = copy.tags().filter(
                    matching => this.idl.pkeyValue(existingTagMap.tag()) === this.idl.pkeyValue(matching.tag())
                );
                if (matchingTagMaps.length > 1) {
                    console.log('Deleting multiple tag maps with the same tag', matchingTagMaps);
                }
                matchingTagMaps.forEach( tm => {
                    tm.isdeleted(true);
                });
            } else {
                console.warn('Could not find existing tag to match deleted tag');
            }
            copy.ischanged(true);
        });

        // what are we doing here?
        const counts = { 'new': 0, 'changed': 0, 'deleted': 0 };
        copy.tags().forEach(a => {
            counts.new += Number( a.isnew() ?? false); // who knew you could cast bools into numbers?
            counts.changed += Number( a.ischanged() ?? false); // but why do our methods here sometime return undefined? bleh
            counts.deleted += Number( a.isdeleted() ?? false);
        });
        console.debug('breakdown: ', { new: counts.new, changed: counts.changed, deleted: counts.deleted });
    }
}
