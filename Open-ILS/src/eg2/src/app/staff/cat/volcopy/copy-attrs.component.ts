/* eslint-disable no-case-declarations, no-magic-numbers, no-shadow */
import {Component, Input, OnInit, OnDestroy, AfterViewInit, ViewChild,
    EventEmitter, Output, QueryList, ViewChildren} from '@angular/core';
import {Subscription,Observable} from 'rxjs';
import {SafeUrl} from '@angular/platform-browser';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {StoreService} from '@eg/core/store.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';
import {FormatService} from '@eg/core/format.service';
import {StringComponent} from '@eg/share/string/string.component';
import {CopyAlertsDialogComponent
} from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {CopyTagsDialogComponent
} from '@eg/staff/share/holdings/copy-tags-dialog.component';
import {CopyNotesDialogComponent
} from '@eg/staff/share/holdings/copy-notes-dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {BatchItemAttrComponent, BatchChangeSelection
} from '@eg/staff/share/holdings/batch-item-attr.component';
import {FileExportService} from '@eg/share/util/file-export.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    selector: 'eg-copy-attrs',
    templateUrl: 'copy-attrs.component.html',

    // Match the header of the batch attrs component
    styles: [
        '.batch-header {background-color: #EBF4FA;}',
        '.template-row {background-color: #EBF4FA;}'
    ]
})
export class CopyAttrsComponent implements OnInit, OnDestroy, AfterViewInit {

    @Input() context: VolCopyContext;
    @Input() contextChanged: Observable<VolCopyContext>;
    private contextSubscription: Subscription;

    // Batch values applied from the form.
    // Some values are scalar, some IdlObjects depending on copy fleshyness.
    values: {[field: string]: any} = {};

    // Map of stat ID to entry ID.
    statCatValues: {[statId: number]: number} = {};

    loanDurationLabelMap: {[level: number]: string} = {};
    fineLevelLabelMap: {[level: number]: string} = {};

    statCatFilter: number;

    @ViewChild('loanDurationShort', {static: false})
        loanDurationShort: StringComponent;
    @ViewChild('loanDurationNormal', {static: false})
        loanDurationNormal: StringComponent;
    @ViewChild('loanDurationLong', {static: false})
        loanDurationLong: StringComponent;

    @ViewChild('fineLevelLow', {static: false})
        fineLevelLow: StringComponent;
    @ViewChild('fineLevelNormal', {static: false})
        fineLevelNormal: StringComponent;
    @ViewChild('fineLevelHigh', {static: false})
        fineLevelHigh: StringComponent;

    @ViewChild('mintConditionYes', {static: false})
        mintConditionYes: StringComponent;
    @ViewChild('mintConditionNo', {static: false})
        mintConditionNo: StringComponent;

    @ViewChild('savedHoldingsTemplates', {static: false})
        savedHoldingsTemplates: StringComponent;
    @ViewChild('deletedHoldingsTemplate', {static: false})
        deletedHoldingsTemplate: StringComponent;

    @ViewChild('copyAlertsDialog', {static: false})
    private copyAlertsDialog: CopyAlertsDialogComponent;

    @ViewChild('copyTagsDialog', {static: false})
    private copyTagsDialog: CopyTagsDialogComponent;

    @ViewChild('copyNotesDialog', {static: false})
    private copyNotesDialog: CopyNotesDialogComponent;

    @ViewChild('copyTemplateCbox', {static: false})
        copyTemplateCbox: ComboboxComponent;

    @ViewChildren(BatchItemAttrComponent)
        batchAttrs: QueryList<BatchItemAttrComponent>;

    // Emitted when the save-ability of this form changes.
    @Output() canSaveChange: EventEmitter<boolean> = new EventEmitter<boolean>();

    userMayEdit = true;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private perm: PermService,
        private format: FormatService,
        private store: StoreService,
        private fileExport: FileExportService,
        private toast: ToastService,
        public  volcopy: VolCopyService
    ) { }

    ngOnInit() {
        this.handleBroadcasts();
        this.setDefaults();
        this.evaluatePermissions();
    }

    ngOnDestroy() {
        if (this.contextSubscription) {
            this.contextSubscription.unsubscribe();
        }
    }

    handleBroadcasts() {
        if (this.context) {
            this.contextSubscription = this.contextChanged.subscribe(updatedContext => {
                this.evaluatePermissions();
            });
        }
    }

    setDefaults() {
        this.statCatFilter = this.volcopy.defaults.values.statcat_filter;
    }

    evaluatePermissions() {
        this.perm.hasWorkPermAt(['UPDATE_COPY'], true)
            .then(orgs => {
                this.userMayEdit = this.context.getOwningLibIds().every(owningLib =>
                    orgs['UPDATE_COPY'].includes(owningLib)
                );
            })
            .catch(error => {
                console.error('Error testing perms & owning libs:',error);
            });
    }

    ngAfterViewInit() {

        const tmpl = this.store.getLocalItem('cat.copy.last_template');
        if (tmpl) {
            // avoid Express Changed warning w/ timeout
            setTimeout(() => this.copyTemplateCbox.selectedId = tmpl);
        }

        this.loanDurationLabelMap[1] = this.loanDurationShort.text;
        this.loanDurationLabelMap[2] = this.loanDurationNormal.text;
        this.loanDurationLabelMap[3] = this.loanDurationLong.text;

        this.fineLevelLabelMap[1] = this.fineLevelLow.text;
        this.fineLevelLabelMap[2] = this.fineLevelNormal.text;
        this.fineLevelLabelMap[3] = this.fineLevelHigh.text;

    }

    statCats(): IdlObject[] {
        if (this.statCatFilter) {
            const orgs = this.org.descendants(this.statCatFilter, true);

            return this.volcopy.commonData.acp_stat_cat.filter(
                sc => orgs.includes(sc.owner()));

        } else {

            return this.volcopy.commonData.acp_stat_cat;
        }
    }


    orgSn(orgId: number): string {
        return orgId ? this.org.get(orgId).shortname() : '';
    }

    statCatCounts(catId: number): {[value: string]: number} {
        catId = Number(catId);
        const counts = {};

        this.context.copyList().forEach(copy => {
            const entry = copy.stat_cat_entries()
                .filter(e => e.stat_cat() === catId)[0];

            let value = '';
            if (entry) {
                if (this.volcopy.statCatEntryMap[entry.id()]) {
                    value = this.volcopy.statCatEntryMap[entry.id()].value();
                } else {
                    // Map to a remote stat cat.  Ignore.
                    return;
                }
            }

            if (counts[value] === undefined) {
                counts[value] = 0;
            }
            counts[value]++;
        });

        return counts;
    }

    itemAttrCounts(field: string): {[value: string]: number} {

        const counts = {};
        this.context.copyList().forEach(copy => {
            const value = this.getFieldDisplayValue(field, copy);

            if (counts[value] === undefined) {
                counts[value] = 0;
            }
            counts[value]++;
        });

        return counts;
    }

    getFieldDisplayValue(field: string, copy: IdlObject): string {

        // Some fields don't live directly on the copy.
        if (field === 'owning_lib') {
            return this.org.get(
                copy.call_number().owning_lib()).shortname() +
                ' : ' + copy.call_number().label();
        }

        const value = copy[field]();

        if (!value && value !== 0) { return ''; }

        switch (field) {

            case 'status':
                return this.volcopy.copyStatuses[value].name();

            case 'location':
                return value.name() +
                    ' (' + this.org.get(value.owning_lib()).shortname() + ')';

            case 'edit_date':
            case 'create_date':
            case 'active_date':
                return this.format.transform(
                    {datatype: 'timestamp', value: value});

            case 'editor':
            case 'creator':
                // VIEW_USER permission may be too narrow.  If so,
                // just display the user ID instead of the username.
                return typeof value === 'object' ? value.usrname() : value;

            case 'circ_lib':
                return this.org.get(value).shortname();

            case 'age_protect':
                const rule = this.volcopy.commonData.acp_age_protect.filter(
                    r => r.id() === Number(value))[0];
                return rule ? rule.name() : '';

            case 'floating':
                const grp = this.volcopy.commonData.acp_floating_group.filter(
                    g => g.id() === Number(value))[0];
                return grp ? grp.name() : '';

            case 'loan_duration':
                return this.loanDurationLabelMap[value];

            case 'fine_level':
                return this.fineLevelLabelMap[value];

            case 'circ_as_type':
                const map = this.volcopy.commonData.acp_item_type_map.filter(
                    m => m.code() === value)[0];
                return map ? map.value() : '';

            case 'circ_modifier':
                const mod = this.volcopy.commonData.acp_circ_modifier.filter(
                    m => m.code() === value)[0];
                return mod ? mod.name() : '';

            case 'mint_condition':
                if (!this.mintConditionYes) { return ''; }
                return value === 't' ?
                    this.mintConditionYes.text : this.mintConditionNo.text;
        }

        return value;
    }

    copyWantsChange(copy: IdlObject, field: string,
        changeSelection: BatchChangeSelection): boolean {
        const disValue = this.getFieldDisplayValue(field, copy);
        return changeSelection[disValue] === true;
    }

    applyCopyValue(field: string, value?: any, changeSelection?: BatchChangeSelection) {
        if (value === undefined) {
            value = this.values[field];
        } else {
            this.values[field] = value;
        }

        if (field === 'owning_lib') {
            this.owningLibChanged(value, changeSelection);

        } else {

            this.context.copyList().forEach(copy => {
                if (!copy[field] || copy[field]() === value) { return; }
                // Don't overwrite magic statuses
                if (field === 'status' && this.volcopy.copyStatIsMagic(copy[field]()) ) { return; }

                // Change selection indicates which items should be modified
                // based on the display value for the selected field at
                // time of editing.
                if (changeSelection &&
                    !this.copyWantsChange(copy, field, changeSelection)) {
                    return;
                }

                copy[field](value);
                copy.ischanged(true);
            });
        }

        this.emitSaveChange();
    }

    owningLibChanged(orgId: number, changeSelection?: BatchChangeSelection) {
        if (!orgId) { return; }

        // Map existing vol IDs to their replacments.
        const newVols: any = {};

        this.context.copyList().forEach(copy => {

            if (changeSelection &&
                !this.copyWantsChange(copy, 'owning_lib', changeSelection)) {
                return;
            }

            // Change the copy circ lib to match the new owning lib
            // if configured to do so.
            if (this.volcopy.defaults.values.circ_lib_mod_with_owning_lib) {
                if (copy.circ_lib() !== orgId) {
                    copy.circ_lib(orgId);
                    copy.ischanged(true);

                    this.batchAttrs
                        .filter(ba => ba.name === 'circ_lib')
                        .forEach(attr => attr.hasChanged = true);
                }
            }

            const vol = copy.call_number();

            if (vol.owning_lib() === orgId) { return; } // No change needed

            let newVol;
            if (newVols[vol.id()]) {
                newVol = newVols[vol.id()];

            } else {

                // The open-ils.cat.asset.volume.fleshed.batch.update API
                // will use the existing volume when trying to create a
                // new volume with the same parameters as an existing volume.
                newVol = this.idl.clone(vol);
                newVol.owning_lib(orgId);
                newVol.id(this.volcopy.autoId--);
                newVol.isnew(true);
                newVols[vol.id()] = newVol;
            }

            copy.call_number(newVol);
            copy.ischanged(true);

            this.context.removeCopyNode(copy.id());
            this.context.findOrCreateCopyNode(copy);
        });

        // If any of the above actions results in an empty volume
        // remove it from the tree.  Note this does not delete the
        // volume at the server, since other items could be attached
        // of which this instance of the editor is not aware.
        Object.keys(newVols).forEach(volId => {

            const volNode = this.context.volNodes().filter(
                node => node.target.id() === +volId)[0];

            if (volNode && volNode.children.length === 0) {
                this.context.removeVolNode(+volId);
            }
        });
    }

    // Create or modify a stat cat entry for each copy that does not
    // already match the new value.
    statCatChanged(catId: number, clear?: boolean) {
        catId = Number(catId);

        const entryId = this.statCatValues[catId];

        if (!clear && (!entryId || !this.volcopy.statCatEntryMap[entryId])) {
            console.warn(
                `Attempt to apply stat cat value which does not exist.
                This is likely the result of a stale copy template.
                stat_cat=${catId} entry=${entryId}`);

            return;
        }

        this.context.copyList().forEach(copy => {

            let entry = copy.stat_cat_entries()
                .filter(e => e.stat_cat() === catId)[0];

            if (clear) {

                if (entry) {
                    // Removing the entry map (and setting copy.ishanged) is
                    // enough to tell the API to delete it.

                    copy.stat_cat_entries(copy.stat_cat_entries()
                        .filter(e => e.stat_cat() !== catId));
                }

            } else {

                if (entry) {
                    if (entry.id() === entryId) {
                        // Requested mapping already exists.
                        return;
                    }
                } else {

                    // Copy has no entry for this stat cat yet.
                    entry = this.idl.create('asce');
                    entry.stat_cat(catId);
                    copy.stat_cat_entries().push(entry);
                }

                entry.id(entryId);
                entry.value(this.volcopy.statCatEntryMap[entryId].value());
            }

            copy.ischanged(true);
        });

        this.emitSaveChange();
    }

    openCopyAlerts() {
        this.copyAlertsDialog.inPlaceCreateMode = true;
        this.copyAlertsDialog.copyIds = this.context.copyList().map(c => c.id());

        this.copyAlertsDialog.open({size: 'lg'}).subscribe(changes => {
            if (!changes) { return; }

            if ((!changes.newAlerts || changes.newAlerts.length === 0) &&
                (!changes.changedAlerts || changes.changedAlerts.length === 0)
            ) {
                return;
            }

            if (changes.newAlerts || changes.changedAlerts) {
                this.emitSaveChange();
            }

            if (changes.newAlerts) {
                this.context.copyList().forEach(copy => {
                    changes.newAlerts.forEach(newAlert => {
                        const a = this.idl.clone(newAlert);
                        a.isnew(true);
                        a.copy(copy.id());
                        if (!copy.copy_alerts()) { copy.copy_alerts([]); }
                        copy.copy_alerts().push(a);
                        copy.ischanged(true);
                    });
                });
            }
            if (changes.changedAlerts) {
                this.context.copyList().forEach(copy => {
                    changes.changedAlerts.forEach(alert => {
                        const matching = copy.copy_alerts().filter(a => a.id() === alert.id());
                        matching.forEach( existing => {
                            existing.ischanged(true);
                            existing.alert_type(alert.alert_type());
                            existing.temp(alert.temp());
                            existing.ack_time(alert.ack_time());
                            existing.ack_staff(alert.ack_staff());
                            existing.note(alert.note());
                            copy.ischanged(true);
                        });
                    });
                });
            }
        });
    }

    openCopyTags() {
        this.copyTagsDialog.inPlaceCreateMode = true;
        this.copyTagsDialog.copyIds = this.context.copyList().map(c => c.id());

        this.copyTagsDialog.open({size: 'lg'}).subscribe(changes => {
            if ((!changes.newTags || changes.newTags.length === 0) &&
                (!changes.deletedMaps || changes.deletedMaps.length === 0)) {
                return;
            }

            changes.newTags.forEach(tag => {
                this.context.copyList().forEach(copy => {

                    if (copy.tags().filter(
                        m => m.tag() === tag.id()).length > 0) {
                        return; // map already exists
                    }

                    const map = this.idl.create('acptcm');
                    map.isnew(true);
                    map.copy(copy.id());
                    map.tag(tag);

                    copy.tags().push(map);
                    copy.ischanged(true);
                });
            });

            if (this.context.copyList().length === 1) {
                const copy = this.context.copyList()[0];
                changes.deletedMaps.forEach(tag => {
                    const existing = copy.tags().filter(t => t.id() === tag.id())[0];
                    if (existing) {
                        existing.isdeleted(true);
                        copy.ischanged(true);
                    }
                });
            }
        });
    }

    openCopyNotes() {
        this.copyNotesDialog.inPlaceCreateMode = true;
        this.copyNotesDialog.copyIds = this.context.copyList().map(c => c.id());

        this.copyNotesDialog.open({size: 'lg'}).subscribe(changes => {
            if (!changes) { return; }

            if ((!changes.newNotes || changes.newNotes.length === 0) &&
                (!changes.delNotes || changes.delNotes.length === 0)
            ) {
                return;
            }

            changes.newNotes.forEach(note => {
                this.context.copyList().forEach(copy => {
                    const n = this.idl.clone(note);
                    n.owning_copy(copy.id());
                    copy.notes().push(n);
                    copy.ischanged(true);
                });
            });
            if (this.context.copyList().length === 1) {
                const copy = this.context.copyList()[0];
                changes.delNotes.forEach(note => {
                    const existing = copy.notes().filter(n => n.id() === note.id())[0];
                    if (existing) {
                        existing.isdeleted(true);
                        copy.ischanged(true);
                    }
                });
            }
        });
    }

    applyTemplate() {
        const entry = this.copyTemplateCbox.selected;
        if (!entry) { return; }

        this.store.setLocalItem('cat.copy.last_template', entry.id);

        const template = this.volcopy.templates[entry.id];

        Object.keys(template).forEach(field => {
            const value = template[field];

            if (value === null || value === undefined) { return; }
            if (field === 'status' && this.volcopy.copyStatIsMagic(value)) { return; }

            // Call number 'value' is a nested object with call number-
            // specific key-value pairs.
            // NOTE: Changed values are visible in the interface, but
            // they are not highlighted the way copy attribute changes are.
            if (field === 'callnumber') {
                // Currently supported fields are prefix, suffix, and
                // classification (label_class).  These all use numeric
                // values as defaults.
                Object.keys(value).forEach(field => {
                    const newVal = value[field];

                    if (field === 'classification') {
                        field = 'label_class';
                    }

                    this.context.volNodes().forEach(volNode => {
                        if (Number(volNode.target[field]())) {
                            volNode.target[field](newVal);
                            volNode.target.ischanged(true);
                        }
                    });
                });
            }

            if (field === 'statcats') {
                Object.keys(value).forEach(catId => {
                    if (value[+catId] !== null) {
                        this.statCatValues[+catId] = value[+catId];
                        this.statCatChanged(+catId);
                        // Indicate this value changed in the form
                        const attr = this.batchAttrs.find(attr =>
                            attr.name?.split('_').pop() === catId
                        );
                        if (attr) { attr.hasChanged = true; }
                    }
                });
                return;
            }

            // Copy alerts are stored as hashes of the bits we need.
            // Templates can be used to create alerts, but not edit them.
            if (field === 'copy_alerts' && Array.isArray(value)) {
                value.forEach(a => {
                    this.context.copyList().forEach(copy => {
                        // Check for existing alert, don't apply duplicates
                        let dupskip = 0;
                        copy.copy_alerts().forEach(curAlert => {
                            if(a.alert_type === curAlert.alert_type() &&
                               a.temp === curAlert.temp() &&
                               a.note === curAlert.note() ) {
                                console.log('Already have this alert',a); // identical alert exists.
                                dupskip = 1;
                            }
                        });
                        if(dupskip) {return;} // skip copy for this new alert

                        const newAlert = this.idl.create('aca');
                        newAlert.isnew(true);
                        newAlert.copy(copy.id());
                        newAlert.alert_type(a.alert_type);
                        newAlert.temp(a.temp);
                        newAlert.note(a.note);
                        newAlert.create_staff(this.auth.user().id());
                        newAlert.create_time('now');

                        if (Array.isArray(copy.copy_alerts())) {
                            copy.copy_alerts().push(newAlert);
                        } else {
                            copy.copy_alerts([newAlert]);
                        }

                        copy.ischanged(true);
                    });
                });

                return;
            }

            // In some cases, we may have to fetch the data since
            // the local code assumes copy field is fleshed.
            let promise = Promise.resolve(value);

            if (field === 'location') {
                // May be a 'remote' location.  Fetch as needed.
                promise = this.volcopy.getLocation(value);
            }

            promise.then(val => {
                this.applyCopyValue(field, val);

                // Indicate in the form these values have changed
                this.batchAttrs
                    .filter(ba => ba.name === field)
                    .forEach(attr => attr.hasChanged = true);
            });
        });
    }

    saveTemplate() {
        const entry: ComboboxEntry = this.copyTemplateCbox.selected;
        if (!entry) { return; }

        let name;
        let template;

        if (entry.freetext) {
            name = entry.label;
            // freetext entries don't have an ID, but we may need one later.
            entry.id = entry.label;
            template = {};
        } else {
            name = entry.id;
            template = this.volcopy.templates[name];
        }

        this.batchAttrs.forEach(comp => {
            if (!comp.hasChanged) { return; }

            const field = comp.name;
            const value = this.values[field];

            if (value === null) {
                delete template[field];
                return;
            }

            if (field.match(/stat_cat_/)) {
                const statId = field.match(/stat_cat_(\d+)/)[1];
                if (!template.statcats) { template.statcats = {}; }

                template.statcats[statId] = this.statCatValues[statId];

            } else {

                // Some values are fleshed. this assumes fleshed objects
                // have an 'id' value, which is true so far.
                template[field] =
                    typeof value === 'object' ?  value.id() : value;
            }
        });

        // Volume attributes that are stored in the template.
        // prefix, suffix and Classification
        // Do we actually want to loop through all volumes for this?
        this.context.volNodes().forEach(volNode => {
            const vol = volNode.target;
            if(vol.ischanged()){ // Something was changed
                template.callnumber = {};
                ['label_class','prefix','suffix'].forEach(field => {

                    template.callnumber[field] = vol[field]();
                });
            }
            console.log('Template:',template);
            // volNode.target.forEach(field=>{
            //    console.log("Saving Volume info to template",field);
            // });
        });

        this.volcopy.templates[name] = template;
        this.volcopy.saveTemplates().then(x => {
            this.savedHoldingsTemplates.current().then(str => this.toast.success(str));
            if (entry.freetext) {
                // once a new template has been added, make it
                // display like any other in the comobox
                this.copyTemplateCbox.selected =
                    this.volcopy.templateNames.filter(_ => _.label === name)[0];
            }
        });
    }

    exportTemplate($event) {
        if (this.fileExport.inProgress()) { return; }

        this.fileExport.exportFile(
            $event, JSON.stringify(this.volcopy.templates), 'text/json');
    }

    importTemplate($event) {
        const file: File = $event.target.files[0];
        if (!file) { return; }

        const reader = new FileReader();

        reader.addEventListener('load', () => {

            try {
                const template = JSON.parse(reader.result as string);
                const theKeys = Object.keys(template);
                for(let i = 0; i < theKeys.length; i++){
                    const name = theKeys[i];
                    this.volcopy.templates[name]=template[name];
                }
            } catch (E) {
                console.error('Invalid Item Attribute template', E);
                return;
            }

            this.volcopy.saveTemplates();
            // Adds the new one to the list and re-sorts the labels.
            this.volcopy.fetchTemplates();
        });

        reader.readAsText(file);
    }

    // Returns null when no export is in progress.
    exportTemplateUrl(): SafeUrl {
        return this.fileExport.safeUrl;
    }

    deleteTemplate() {
        const entry: ComboboxEntry = this.copyTemplateCbox.selected;
        if (!entry) { return; }
        delete this.volcopy.templates[entry.id];
        this.volcopy.saveTemplates().then(
            x => this.deletedHoldingsTemplate.current().then(str => this.toast.success(str))
        );
        this.copyTemplateCbox.selected = null;
    }

    displayAttr(field: string): boolean {
        return this.volcopy.defaults.hidden[field] !== true;
    }

    copyFieldLabel(field: string): string {
        const def = this.idl.classes.acp.field_map[field];
        return def ? def.label : '';
    }

    // Returns false if any items are in magic statuses
    statusEditable(): boolean {
        const copies = this.context.copyList();
        for (let idx = 0; idx < copies.length; idx++) {
            if (this.volcopy.copyStatIsMagic(copies[idx].status())) {
                return false;
            }
        }
        return true;
    }

    // Called any time a change occurs that could affect the
    // save-ability of the form.
    emitSaveChange() {
        setTimeout(() => {
            const canSave = this.batchAttrs.filter(
                attr => attr.warnOnRequired()).length === 0;

            this.canSaveChange.emit(canSave);
        });
    }

    // True if one of our batch editors has been put into edit
    // mode and left there without an Apply, Cancel, or Clear
    hasActiveInput(): boolean {
        return this.batchAttrs.filter(attr => attr.editing).length > 0;
    }

    applyPendingChanges() {
        // If a user has left any changes in the 'editing' state, this
        // will go through and apply the values so they do not have to
        // click Apply for every one.
        this.batchAttrs.filter(attr => attr.editing).forEach(attr => attr.save());
    }

    copyLocationOrgs(): number[] {
        if (!this.context) { return []; }

        // Make sure every org unit represented by the edit batch
        // is represented.
        const ids = this.context.orgNodes().map(n => n.target.id());

        // Make sure all locations within the "full path" of our
        // workstation org unit are included.
        return ids.concat(this.org.fullPath(this.auth.user().ws_ou()));
    }
}



