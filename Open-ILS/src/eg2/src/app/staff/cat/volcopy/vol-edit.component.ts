import {Component, OnInit, ViewChild, Input, Renderer2, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {VolCopyContext, HoldingsTreeNode} from './volcopy';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {VolCopyService} from './volcopy.service';

@Component({
    selector: 'eg-vol-edit',
    templateUrl: 'vol-edit.component.html',
    styleUrls: ['vol-edit.component.css']
})


export class VolEditComponent implements OnInit {

    @Input() context: VolCopyContext;

    // There are 10 columns in the editor form.  Set the flex values
    // here so they don't have to be hard-coded and repeated in the
    // markup.  Changing a flex value here will propagate to all
    // rows in the form.  Column numbers are 1-based.
    flexSettings: {[column: number]: number} = {
        1: 2, 2: 1, 3: 2, 4: 1, 5: 2, 6: 1, 7: 1, 8: 2, 9: 1, 10: 1, 11: 1};

    // Since visibility of some columns is configurable, we need a
    // map of configured column name to column index.
    flexColMap = {
        3: 'classification',
        4: 'prefix',
        6: 'suffix',
        9: 'copy_number_vc',
        10: 'copy_part'
    };

    // If a column is specified as the expand field, its flex value
    // will magically grow.
    expand: number;

    batchVolClass: ComboboxEntry;
    batchVolPrefix: ComboboxEntry;
    batchVolSuffix: ComboboxEntry;
    batchVolLabel: ComboboxEntry;

    autoBarcodeInProgress = false;

    deleteVolCount: number = null;
    deleteCopyCount: number = null;

    // Set default for Call Number Label requirement
    requireCNL = true;

    // When adding multiple vols via add-many popover.
    addVolCount: number = null;

    // When adding multiple copies via add-many popover.
    addCopyCount: number = null;

    recordVolLabels: string[] = [];

    @ViewChild('confirmDelVol', {static: false})
        confirmDelVol: ConfirmDialogComponent;

    @ViewChild('confirmDelCopy', {static: false})
        confirmDelCopy: ConfirmDialogComponent;

    // Emitted when the save-ability of this form changes.
    @Output() canSaveChange: EventEmitter<boolean> = new EventEmitter<boolean>();
    changedCallnumberFields: string[] = [];

    constructor(
        private renderer: Renderer2,
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private net: NetService,
        private auth: AuthService,
        public  volcopy: VolCopyService
    ) {}

    ngOnInit() {

        this.deleteVolCount = null;
        this.deleteCopyCount = null;

        this.volcopy.genBarcodesRequested.subscribe(() => this.generateBarcodes());


        // Check to see if call number label is required
        this.org.settings('cat.require_call_number_labels')
            .then(settings => {
                this.requireCNL =
                Boolean(settings['cat.require_call_number_labels']);
            })
            .then(() => this.volcopy.fetchRecordVolLabels(this.context.recordId))
            .then(labels => this.recordVolLabels = labels)
            .then(_ => this.volcopy.fetchBibParts(this.context.getRecordIds()))
            .then(_ => this.addStubCopies())
        // It's possible the loaded data is not strictly allowed,
        // e.g. empty string call number labels
            .then(_ => this.emitSaveChange(true));
    }

    copyStatLabel(copy: IdlObject): string {
        if (copy) {
            const statId = copy.status();
            if (statId in this.volcopy.copyStatuses) {
                return this.volcopy.copyStatuses[statId].name();
            }
        }
        return '';
    }

    recordHasParts(bibId: number): boolean {
        return this.volcopy.bibParts[bibId] &&
            this.volcopy.bibParts[bibId].length > 0;
    }

    // Column width (flex:x) for column by column number.
    flexAt(column: number): number {
        if (!this.displayColumn(this.flexColMap[column])) {
            // Hidden columsn are still present, but they do not
            // flex and the contain no data to display
            return 0;
        }
        let value = this.flexSettings[column];
        // eslint-disable-next-line no-magic-numbers
        if (this.expand === column) { value = value * 3; }
        return value;
    }

    addVol(org: IdlObject) {
        if (!org) { return; }
        const orgNode = this.context.findOrCreateOrgNode(org.id());
        this.createVols(orgNode, 1);
        this.context.sortHoldings();
    }

    // This only removes copies that were created during the
    // current editing session and have not yet been saved in the DB.
    deleteCopies(volNode: HoldingsTreeNode, count: number) {
        for (let i = 0;  i < count; i++) {
            const copyNode = volNode.children[volNode.children.length - 1];
            if (copyNode && copyNode.target.isnew()) {
                volNode.children.pop();
            } else {
                break;
            }
        }
    }

    createCopies(volNode: HoldingsTreeNode, count: number) {
        const copies = [];
        for (let i = 0; i < count; i++) {

            // Our context assumes copies are fleshed with volumes
            const vol = volNode.target;
            const copy = this.volcopy.createStubCopy(vol);
            copy.call_number(vol);
            this.context.findOrCreateCopyNode(copy);
            copies.push(copy);
        }

        this.volcopy.setCopyStatus(copies);
    }

    createCopiesFromPopover(volNode: HoldingsTreeNode, popover: any) {
        this.createCopies(volNode, this.addCopyCount);
        popover.close();
        this.addCopyCount = null;
    }

    createVolsFromPopover(orgNode: HoldingsTreeNode, popover: any) {
        this.createVols(orgNode, this.addVolCount);
        popover.close();
        this.addVolCount = null;
    }

    createVols(orgNode: HoldingsTreeNode, count: number) {
        const vols = [];
        const copies = [];
        for (let i = 0; i < count; i++) {

            // This will vivify the volNode if needed.
            const vol = this.volcopy.createStubVol(
                this.context.recordId, orgNode.target.id());

            vols.push(vol);

            // Our context assumes copies are fleshed with volumes
            const copy = this.volcopy.createStubCopy(vol);
            copy.call_number(vol);
            copies.push(copy);
            this.context.findOrCreateCopyNode(copy);
        }

        this.volcopy.setCopyStatus(copies);
        this.volcopy.setVolClassLabels(vols);
    }

    // This only removes vols that were created during the
    // current editing session and have not yet been saved in the DB.
    deleteVols(orgNode: HoldingsTreeNode, count: number) {
        for (let i = 0;  i < count; i++) {
            const volNode = orgNode.children[orgNode.children.length - 1];
            if (volNode && volNode.target.isnew()) {
                orgNode.children.pop();
            } else {
                break;
            }
        }
    }

    // When editing existing vols, be sure each has at least one copy.
    addStubCopies(volNode?: HoldingsTreeNode) {
        const nodes = volNode ? [volNode] : this.context.volNodes();

        const copies = [];
        nodes.forEach(vNode => {
            if (vNode.children.length === 0) {
                const vol = vNode.target;
                const copy = this.volcopy.createStubCopy(vol);
                copy.call_number(vol);
                copies.push(copy);
                this.context.findOrCreateCopyNode(copy);
            }
        });

        this.volcopy.setCopyStatus(copies);
    }

    applyVolValue(vol: IdlObject, key: string, value: any) {

        if (value === null && (key === 'prefix' || key === 'suffix')) {
            // -1 is the empty prefix/suffix value.
            value = -1;
        }

        if (vol[key]() !== value) {
            this.changedCallnumberFields.push(key);
            vol[key](value);
            vol.ischanged(this.changedCallnumberFields);
        }

        this.emitSaveChange();
    }

    applyCopyValue(copy: IdlObject, key: string, value: any) {
        if (copy[key]() !== value) {
            copy[key](value);
            copy.ischanged(true);
        }
    }

    copyPartChanged(copyNode: HoldingsTreeNode, entry: ComboboxEntry) {
        const copy = copyNode.target;
        const part = copyNode.target.parts()[0];

        if (entry) {

            let newPart;
            if (entry.freetext) {
                newPart = this.idl.create('bmp');
                newPart.isnew(true);
                newPart.record(copy.call_number().record());
                newPart.label(entry.label);

            } else {

                newPart =
                    this.volcopy.bibParts[copy.call_number().record()]
                        .filter(p => p.id() === entry.id)[0];

                // Nothing to change?
                if (part && part.id() === newPart.id()) { return; }
            }

            copy.parts([newPart]);
            copy.ischanged(true);

        } else if (part) { // Part map no longer needed.

            copy.parts([]);
            copy.ischanged(true);
        }
    }

    batchVolApply() {
        this.context.volNodes().forEach(volNode => {
            const vol = volNode.target;
            if (this.batchVolClass) {
                this.applyVolValue(vol, 'label_class', this.batchVolClass.id);
            }
            if (this.batchVolPrefix) {
                this.applyVolValue(vol, 'prefix', this.batchVolPrefix.id);
            }
            if (this.batchVolSuffix) {
                this.applyVolValue(vol, 'suffix', this.batchVolSuffix.id);
            }
            if (this.batchVolLabel) {
                // Use label; could be freetext.
                this.applyVolValue(vol, 'label', this.batchVolLabel.label);
            }
        });
    }

    // Focus and select the next editable barcode.
    selectNextBarcode(id: number, previous?: boolean) {
        let found = false;
        let nextId: number = null;
        let firstId: number = null;

        let copies = this.context.copyList();
        if (previous) { copies = copies.reverse(); }

        // Find the ID of the next item.  If this is the last item,
        // loop back to the first item.
        copies.forEach(copy => {
            if (nextId !== null) { return; }

            // In case we have to loop back to the first copy.
            if (firstId === null && this.barcodeCanChange(copy)) {
                firstId = copy.id();
            }

            if (found) {
                if (nextId === null && this.barcodeCanChange(copy)) {
                    nextId = copy.id();
                }
            } else if (copy.id() === id) {
                found = true;
            }
        });

        this.renderer.selectRootElement(
            '#barcode-input-' + (nextId || firstId)).select();
    }

    barcodeCanChange(copy: IdlObject): boolean {
        return !this.volcopy.copyStatIsMagic(copy.status());
    }

    generateBarcodes() {
        this.autoBarcodeInProgress = true;

        // Autogen only replaces barcodes for items which are in
        // certain statuses.
        const copies = this.context.copyList()
            .filter((copy, idx) => {
            // During autogen we do not replace the first item,
            // so it's status is not relevant.
                return idx === 0 || this.barcodeCanChange(copy);
            });

        if (copies.length > 1) { // seed barcode will always be present
            this.proceedWithAutogen(copies)
                .then(_ => this.autoBarcodeInProgress = false);
        }
    }

    proceedWithAutogen(copyList: IdlObject[]): Promise<any> {

        const seedBarcode: string = copyList[0].barcode();
        copyList.shift(); // Avoid replacing the seed barcode

        const count = copyList.length;

        return this.net.request('open-ils.cat',
            'open-ils.cat.item.barcode.autogen',
            this.auth.token(), seedBarcode, count, {
                checkdigit: this.volcopy.defaults.values.use_checkdigit,
                skip_dupes: true
            }
        ).pipe(tap(barcodes => {

            copyList.forEach(copy => {
                if (copy.barcode() !== barcodes[0]) {
                    copy.barcode(barcodes[0]);
                    copy.ischanged(true);
                }
                barcodes.shift();
            });

        })).toPromise();
    }

    barcodeChanged(copy: IdlObject, barcode: string) {

        if (barcode) {
            // Scrub leading/trailing spaces from barcodes
            barcode = barcode.trim();
            copy.barcode(barcode);
        }

        copy.ischanged(true);
        copy._dupe_barcode = false;

        if (!barcode) {
            this.emitSaveChange();
            return;
        }

        if (!this.autoBarcodeInProgress) {
            // Manual barcode entry requires dupe check

            copy._dupe_barcode = false;
            this.pcrud.search('acp', {
                deleted: 'f',
                barcode: barcode,
                id: {'!=': copy.id()}
            }).subscribe(
                resp => {
                    if (resp) { copy._dupe_barcode = true; }
                },
                (err: unknown) => {},
                () => this.emitSaveChange()
            );
        }
    }

    deleteCopy(copyNode: HoldingsTreeNode) {

        if (copyNode.target.isnew()) {
            // Confirmation not required when deleting brand new copies.
            this.deleteOneCopy(copyNode);
            return;
        }

        this.deleteCopyCount = 1;
        this.confirmDelCopy.open().toPromise().then(confirmed => {
            if (confirmed) { this.deleteOneCopy(copyNode); }
        });
    }

    deleteOneCopy(copyNode: HoldingsTreeNode) {
        const targetCopy = copyNode.target;

        const orgNodes = this.context.orgNodes();
        for (let orgIdx = 0; orgIdx < orgNodes.length; orgIdx++) {
            const orgNode = orgNodes[orgIdx];

            for (let volIdx = 0; volIdx < orgNode.children.length; volIdx++) {
                const volNode = orgNode.children[volIdx];

                for (let copyIdx = 0; copyIdx < volNode.children.length; copyIdx++) {
                    const copy = volNode.children[copyIdx].target;

                    if (copy.id() === targetCopy.id()) {
                        volNode.children.splice(copyIdx, 1);
                        if (!copy.isnew()) {
                            copy.isdeleted(true);
                            this.context.copiesToDelete.push(copy);
                        }

                        if (volNode.children.length === 0) {
                            // When removing the last copy, add a stub copy.
                            this.addStubCopies();
                        }

                        return;
                    }
                }
            }
        }
    }


    deleteVol(volNode: HoldingsTreeNode) {

        if (volNode.target.isnew()) {
            // Confirmation not required when deleting brand new vols.
            this.deleteOneVol(volNode);
            return;
        }

        this.deleteVolCount = 1;
        this.deleteCopyCount = volNode.children.length;

        this.confirmDelVol.open().toPromise().then(confirmed => {
            if (confirmed) { this.deleteOneVol(volNode); }
        });
    }

    deleteOneVol(volNode: HoldingsTreeNode) {

        let deleteVolIdx = null;
        const targetVol = volNode.target;

        // FOR loops allow for early exit
        const orgNodes = this.context.orgNodes();
        for (let orgIdx = 0; orgIdx < orgNodes.length; orgIdx++) {
            const orgNode = orgNodes[orgIdx];

            for (let volIdx = 0; volIdx < orgNode.children.length; volIdx++) {
                const vol = orgNode.children[volIdx].target;

                if (vol.id() === targetVol.id()) {
                    deleteVolIdx = volIdx;

                    if (vol.isnew()) {
                        // New volumes, which can only have new copies
                        // may simply be removed from the holdings
                        // tree to delete them.
                        break;
                    }

                    // Mark volume and attached copies as deleted
                    // and track for later deletion.
                    targetVol.isdeleted(true);
                    this.context.volsToDelete.push(targetVol);

                    // When deleting vols, no need to delete the linked
                    // copies.  They'll be force deleted via the API.
                }

                if (deleteVolIdx !== null) { break; }
            }

            if (deleteVolIdx !== null) {
                orgNode.children.splice(deleteVolIdx, 1);
                break;
            }
        }
    }

    editVolOwner(volNode: HoldingsTreeNode, org: IdlObject) {
        if (!org) { return; }

        const orgId = org.id();
        const vol = volNode.target;

        vol.owning_lib(orgId);
        vol.ischanged(true);

        // Move the vol node away from its previous org node and append
        // it to the children list of the target node.
        let targetOrgNode: HoldingsTreeNode;
        this.context.orgNodes().forEach(orgNode => {

            if (orgNode.target.id() === orgId) {
                targetOrgNode = orgNode;
                return;
            }

            orgNode.children.forEach((vNode, volIdx) => {
                if (vol.id() === vNode.target.id()) {
                    orgNode.children.splice(volIdx, 1);
                }
            });
        });

        if (!targetOrgNode) {
            targetOrgNode = this.context.findOrCreateOrgNode(orgId);
        }

        targetOrgNode.children.push(volNode);

        // If configured to do so, also update the circ_lib for any
        // copies linked to this call number in this edit session.
        if (this.volcopy.defaults.values.circ_lib_mod_with_owning_lib) {
            volNode.children.forEach(copyNode => {
                const copy = copyNode.target;
                if (copy.circ_lib() !== orgId) {
                    copy.circ_lib(orgId);
                    copy.ischanged(true);
                }
            });
        }

        this.emitSaveChange();
    }


    displayColumn(field: string): boolean {
        return this.volcopy.defaults.hidden[field] !== true;
    }

    canSave(): boolean {

        const copies = this.context.copyList();

        const badCopies = copies.filter(copy => {
            return copy._dupe_barcode || (!copy.isnew() && !copy.barcode());
        }).length > 0;

        if (badCopies) { return false; }

        const badVols = this.context.volNodes().filter(volNode => {
            const vol = volNode.target;

            // If call number label is not required, then require prefix
            if (!vol.label()) {
                // eslint-disable-next-line eqeqeq
                if (this.requireCNL == true) {
                    return !(
                        vol.label()
                    );
                } else {
                    return (
                        vol.prefix() < 0
                    );
                }
            }
        }).length > 0;

        return !badVols;
    }

    // Called any time a change occurs that could affect the
    // save-ability of the form.
    emitSaveChange(initialLoad?: boolean) {
        const saveable = this.canSave();

        // Avoid emitting a save change event when this was called
        // during page load and the resulting data is saveable.
        if (initialLoad && saveable) { return; }

        setTimeout(() => {
            this.canSaveChange.emit(saveable);
        });
    }

    // Given a DOM ID, focus the element after a 0 timeout.
    focusElement(domId: string) {
        setTimeout(() => {
            const node = document.getElementById(domId);
            if (node) { node.focus(); }
        });
    }


    toggleBatchVisibility() {
        this.volcopy.defaults.visible.batch_actions =
            !this.volcopy.defaults.visible.batch_actions;
        this.volcopy.saveDefaults();
    }
}

