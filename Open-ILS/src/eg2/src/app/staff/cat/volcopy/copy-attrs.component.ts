/* eslint-disable no-case-declarations, no-magic-numbers, no-shadow */
/* eslint-disable max-len, no-prototype-builtins */
import {Component, Input, OnInit, OnDestroy, AfterViewInit, ViewChild,
    EventEmitter, Output, QueryList, ViewChildren} from '@angular/core';
import {firstValueFrom,BehaviorSubject,Subject,Subscription,Observable} from 'rxjs';
import {take,takeUntil,filter} from 'rxjs/operators';
import {SafeUrl} from '@angular/platform-browser';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {StoreService} from '@eg/core/store.service';
import {AuthService} from '@eg/core/auth.service';
import {PermService} from '@eg/core/perm.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {VolCopyContext} from './volcopy';
import {VolCopyService} from './volcopy.service';
import {FormatService} from '@eg/core/format.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ICopyAlert,CopyAlertsDialogComponent
} from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {ICopyTagMap, CopyTagsDialogComponent
} from '@eg/staff/share/holdings/copy-tags-dialog.component';
import {ICopyNote, CopyNotesDialogComponent
} from '@eg/staff/share/holdings/copy-notes-dialog.component';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {BatchItemAttrComponent, BatchChangeSelection
} from '@eg/staff/share/holdings/batch-item-attr.component';
import {FileExportService} from '@eg/share/util/file-export.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    selector: 'eg-copy-attrs',
    templateUrl: 'copy-attrs.component.html',
    styleUrls: ['copy-attrs.component.css']
})
export class CopyAttrsComponent implements OnInit, OnDestroy, AfterViewInit {

    @Input() context: VolCopyContext;
    @Input() contextChanged: Observable<VolCopyContext>;
    @Input() templateOnlyMode = false; // expect to use this for styling
    @Input() template: string; // in templateOnlyMode, the name of the template we're editing
    showSaveInEditor = false; // overriden by an org setting
    hideTemplateBar = false;
    yesNoOptions = [
        { label: $localize`Yes`, value: 't' },
        { label: $localize`No`, value: 'f' },
    ];

    private _initialized$ = new BehaviorSubject<boolean>(false);
    public initialized$ = new BehaviorSubject<boolean>(false);
    private destroy$ = new Subject<void>();
    private originalCopies: {[id: number]: IdlObject} = {};
    private originalVols: {[id: number]: IdlObject} = {};

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

    // Emitted when the Clear Changes action is used.
    @Output() clearChanges: EventEmitter<boolean> = new EventEmitter<boolean>();

    userMayEdit = true;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private perm: PermService,
        private pcrud: PcrudService,
        private format: FormatService,
        private store: StoreService,
        private toast: ToastService,
        public  volcopy: VolCopyService
    ) { }

    ngOnInit() {
        // console.debug('CopyAttrsComponent, ngOnInit, this', this);

        this.org.settings([
            'ui.cat.volume_copy_editor.template_bar.show_save_template',
            'ui.cat.volume_copy_editor.hide_template_bar'
        ], this.auth.user().ws_ou())
            .then(settings => {
                this.showSaveInEditor = Boolean(settings['ui.cat.volume_copy_editor.template_bar.show_save_template']);
                this.hideTemplateBar = Boolean(settings['ui.cat.volume_copy_editor.hide_template_bar']);
            });

        // Wait for volcopy service to be ready
        if (this.volcopy.defaults) {
            this.initialize();
        } else {
            // Wait for the parent's load() to complete
            this.contextChanged.pipe(
                filter(() => !!this.volcopy.defaults), // Only proceed when defaults exist
                takeUntil(this.destroy$)
            ).subscribe(() => {
                if (!this._initialized$.value) {
                    this.initialize();
                }
            });
        }
    }

    private initialize() {
        this.handleBroadcasts();
        this.setDefaults();
        this.evaluatePermissions();

        // this.presetWidgetsInNonBatchMode();
        this.backupOriginalState();
        this._initialized$.next(true);
    }

    public presetWidgets() {
        if (this.templateOnlyMode) {
            this.values = this.context.copyList().length ? this.idl.toHash( this.context.copyList()[0] ) : {};
            // console.debug('CopyAttrsComponent, leaving presetWidgets as template with values:', this.values);
            return;
        }

        // don't fetch values for hidden fields or anything we can't edit here
        const hidden = this.volcopy.defaults?.hidden;
        const editable = Array('age_protect', 'barcode', 'call_number', 'circ_as_type',
            'circ_lib', 'circ_modifier', 'circulate', 'cost', 'deposit', 'deposit_amount',
            'fine_level', 'floating', 'holdable', 'loan_duration', 'location', 'mint_condition',
            'opac_visible', 'price', 'ref', 'status');
        const callNumberPieces = Array();
        Array('label_class','owning_lib','prefix','suffix').forEach(key => {
            if (this.displayAttr(key)) {callNumberPieces.push(key);}
        });

        // console.debug('CopyAttrsComponent, entering presetWidgets, template only mode?', this.templateOnlyMode);
        const multiValueFields = Array();
        const copies = this.context.copyList();
        copies.forEach(copy => {
            if (copy.ischanged() && copy.ischanged !== 'f') {
                // console.debug('CopyAttrsComponent, presetWidgets, copy marked as changed, aborting', copy);
                return;
            }
            editable.forEach(field => {
                if (copy[field] && !hidden[field] && !multiValueFields.includes(field)) {
                    let newval;
                    switch (field) {
                        case 'call_number':
                            newval = Object.fromEntries(callNumberPieces
                                .filter(key => key in copy.call_number())
                                .map(key => [key, copy.call_number()[key]()])
                            );
                            // console.debug("Call number: ", newval);
                            break;
                        case 'location':
                            newval = this.getLocationId(copy[field]());
                            // console.debug('Location: ', newval);
                            break;
                        default:
                            newval = copy[field]();
                    }

                    // console.debug("CopyAttrsComponent, presetWidgets, loaded value:", field, newval);
                    // do we have multiple values?
                    if (field !== 'call_number' && this.values[field] && this.values[field] !== newval) {
                        this.values[field] = null;
                        multiValueFields.push(field);
                    } else {
                        if (field === 'call_number' && this.values[field] && !this.compareCallNumbers(this.values[field], newval)) {
                            this.values[field] = null;
                            multiValueFields.push(field);
                        } else {
                            this.values[field] = newval;
                            // console.debug("CopyAttrsComponent, presetWidgets, values['" + field + "'] set to: ", newval);
                        }
                    }
                }
            });

            // set up defaults only if we are not in templates
            const defaults = this.templateOnlyMode ? this.volcopy.defaults?.values : [];

            // start with defaults, add values, promote call number pieces into the parent object
            this.values = { ...defaults, ...this.values, ...this.values['call_number'] };
            // fix name mismatch in call number label classification
            if (!this.values['label_class'] && defaults['classification']) {
                this.values['label_class'] = defaults['classification'];
            }
        });

        // console.debug('CopyAttrsComponent, leaving presetWidgets with values:', this.values);
        // console.debug('CopyAttrsComponent, leaving presetWidgets with multiValueFields:', multiValueFields);
    }

    public compareCallNumbers(cn1, cn2) {
        if (typeof cn1 !== 'object' || typeof cn2 !== 'object') {return false;}

        if (Object.keys(cn1).length === Object.keys(cn2).length && Object.values(cn1).toString() === Object.values(cn2).toString()) {return true;}

        return false;
    }

    public presetWidgetsInNonBatchMode() {
        // console.debug('CopyAttrsComponent, entering presetWidgetsInNonBatchMode');
        const copies = this.context.copyList();
        if (copies.length === 1) {
            const copy = this.context.copyList()[0];
            // console.debug('CopyAttrsComponent, presetWidgetsInNonBatchMode, found single copy:', copy);
            if (copy.ischanged() && copy.ischanged !== 'f') {
                // console.debug('CopyAttrsComponent, presetWidgetsInNonBatchMode, copy marked as changed, aborting', copy);
                return;
            }
            this.idl.classes.acp.fields.forEach(field => {
                if (copy[field.name]) {
                    this.values[field.name] = copy[field.name]();
                    // console.debug("CopyAttrsComponent, presetWidgetsInNonBatchMode, values['" + field.name + "'] set to: ", this.values[field.name]);
                }
            });
            // get call number pieces out of the object
            ['label','label_class','owning_lib','prefix','suffix'].forEach(field =>{
                if (this.values['call_number'][field]()) {
                    this.values[field] = this.values['call_number'][field]();
                }
            });
            // we need the shelving location ID, not the whole object
            this.values['location'] = this.values['location']?.id() || 1;
        } else {
            console.debug('CopyAttrsComponent, presetWidgetsInNonBatchMode, found ' + copies.length + ' copies:', copies);
        }
        console.debug('CopyAttrsComponent, leaving presetWidgetsInNonBatchMode with values:', this.values);
    }

    private backupOriginalState() {
        if (!this.context) {return;}

        // Backup copies
        this.context.copyList().forEach(copy => {
            const copyClone = this.idl.clone(copy);
            const copyId = copy.id();
            this.originalCopies[copyId] = copyClone;
            // console.debug('originalCopies['+copyId+'] = ',copyClone);
        });

        // Backup volumes
        this.context.volNodes().forEach(volNode => {
            const volClone = this.idl.clone(volNode.target); // acn
            const volId = volNode.target.id();
            this.originalVols[volId] = volClone;
            // console.debug('originalVols['+volId+'] = ',volClone);
        });
    }

    ngOnDestroy() {
        this.destroy$.next();
        this.destroy$.complete();
    }

    handleBroadcasts() {
        if (this.context) {
            this.contextChanged.pipe( takeUntil(this.destroy$) ).subscribe(updatedContext => {
                this.evaluatePermissions();
            });
        }
    }

    setDefaults() {
        if (this.volcopy.defaults?.values) {
            this.statCatFilter = this.volcopy.defaults?.values.statcat_filter;
        }
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

    saveTemplateCboxSelection(entry) {
        // console.debug('saveTemplateCboxSelection', entry);
        if (entry && !entry.freetext) {
            this.store.setLocalItem('cat.copy.last_template_selected',
                entry ? (entry.freetext ? entry.label : entry.id) : null);
            this.resetTemplateCboxSelection(); // make sure UI and model are in sync
        }
    }

    resetTemplateCboxSelection() {
        const tmpl = this.store.getLocalItem('cat.copy.last_template_selected');
        // console.debug('resetTemplateCboxSelection', tmpl);
        // avoid Express Changed warning w/ timeout
        setTimeout(() => {
            this.copyTemplateCbox.selectedId = tmpl;
            /*
            console.debug('CopyAttrsComponent, copyTemplateCbox.selected is now',
                this.copyTemplateCbox, this.copyTemplateCbox.selected);
            /** */
        });
    }

    ngAfterViewInit() {
        // console.debug('CopyAttrsComponent, ngAfterViewInit, this', this);

        if (this.template !== null) {this.resetTemplateCboxSelection();}

        this.loanDurationLabelMap[1] = this.loanDurationShort.text;
        this.loanDurationLabelMap[2] = this.loanDurationNormal.text;
        this.loanDurationLabelMap[3] = this.loanDurationLong.text;

        this.fineLevelLabelMap[1] = this.fineLevelLow.text;
        this.fineLevelLabelMap[2] = this.fineLevelNormal.text;
        this.fineLevelLabelMap[3] = this.fineLevelHigh.text;

        this.presetWidgets();
        this.initCopyAlerts();
        this.initCopyTags();
        this.initCopyNotes();

        this._initialized$.pipe(
            filter(initialized => initialized),
            take(1)
        ).subscribe( () => {
            // console.debug('CopyAttrsComponent, emitting initialized$ to the outside world');
            this.initialized$.next(true);
        });
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
            const entry = (copy.stat_cat_entries() || [])
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

    multiValue(field: string): boolean {
        return Object.keys(this.itemAttrCounts(field)).length > 1;
    }

    // sometimes we get the whole location object from the template. This is bad.
    getLocationId(value: any): number {
        // console.debug('location ID ', value);
        if (typeof value === 'object') {
            return Number(this.idl.pkeyValue(value));
        }

        return Number(value);
    }

    getFieldDisplayValue(field: string, _copy: IdlObject): string {

        try {
            const copy = this.idl.fromHash( _copy, 'acp' ); // "defensive" coding, aka, look into why later
            // console.debug('getFieldDisplayValue',this.volcopy,field,copy);

            // Some fields don't live directly on the copy.
            switch (field) {
                case 'owning_lib':
                    // the IDL-generated copy sets a blank owning_lib to the workstation
                    // we don't want that in templates; only owning_lib actually saved in the template
                    if (this.templateOnlyMode && !this.values['owning_lib']) {
                        return '';
                    }

                    let lib = this.org.get(copy.call_number().owning_lib()).shortname();
                    // call number labels can be blank in templates
                    if (copy.call_number().label()) {
                        lib = lib + ' : ' + copy.call_number().label();
                    }
                    return lib;
                case 'prefix':
                    const actual_prefix = copy.call_number().prefix();
                    const fleshed_prefix = this.volcopy.acnPrefixes[ actual_prefix ];
                    const stringified_prefix = fleshed_prefix?.label() || '';
                    return stringified_prefix;
                case 'suffix':
                    const actual_suffix = copy.call_number().suffix();
                    const fleshed_suffix = this.volcopy.acnSuffixes[ actual_suffix ];
                    const stringified_suffix = fleshed_suffix?.label() || '';
                    return stringified_suffix;
                case 'label_class':
                    const actual_label_class = copy.call_number().label_class();
                    const fleshed_label_class = this.volcopy.acnLabelClasses[ actual_label_class ];
                    const stringified_label_class = fleshed_label_class?.name() || '';
                    return stringified_label_class;
            }

            const value = copy[field]();
            let v = this.idl.toHash( value ); // offside?

            if (!value && value !== 0) { return ''; }

            switch (field) {

                case 'status':
                    return this.volcopy.copyStatuses[value].name();

                case 'location':
                    // console.debug('Location value, v: ', value, v);
                    // console.debug('Field display value, starting with location: ', value, v);
                    let owning;
                    let name;
                    if (typeof value === 'number') {
                        if (typeof v !== 'object') {
                            v = this.volcopy.getLocation(value).then(
                                loc => {
                                    name = loc.name();
                                    owning = loc.owning_lib();
                                }
                            );
                        } else {
                            name = v.name;
                            owning = v.owning_lib;
                        }
                        // console.debug('Field display value, owning from first if: ', owning, name);
                    } else {
                        // if value is an object, we should have everything we need
                        owning = value.owning_lib();
                        name = value.name();
                        // console.debug('Field display value, owning from value: ', owning, name);
                    }

                    const shortname = this.org.get(owning)?.shortname();
                    if (shortname) {
                        return name + ` (${shortname})`;
                    }

                    return name;
                case 'edit_date':
                case 'create_date':
                case 'active_date':
                    return this.format.transform(
                        {datatype: 'timestamp', value: value});

                case 'editor':
                case 'creator':
                    // VIEW_USER permission may be too narrow.  If so,
                    // just display the user ID instead of the username.
                    if (typeof value === 'string' || typeof value === 'number') { return value.toString(); }
                    return v.usrname;

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
        } catch(E) {
            console.debug(`Invalid value for field ${field}`, E);
            return null;
        }
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

        if (field === 'owning_lib' || field === 'prefix' || field === 'suffix' || field === 'label_class') {
            this.somethingOnCallNumberChanged(field, value, changeSelection);

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

    somethingOnCallNumberChanged(field: string, value: any, changeSelection?: BatchChangeSelection) {
        console.debug('somethingOnCallNumberChanged', field, value, changeSelection);
        if (!value && (field === 'prefix' || field === 'suffix')) { value = -1; }
        if (!value) { return; }

        // Map existing vol IDs to their replacments.
        const newVols: any = {};

        this.context.copyList().forEach(copy => {

            if (changeSelection &&
                !this.copyWantsChange(copy, field, changeSelection)) {
                return;
            }

            if (field === 'owning_lib') {
                // Change the copy circ lib to match the new owning lib
                // if configured to do so.
                if (this.volcopy.defaults?.values.circ_lib_mod_with_owning_lib) {
                    if (copy.circ_lib() !== value) {
                        copy.circ_lib(value);
                        copy.ischanged(true);

                        this.batchAttrs
                            .filter(ba => ba.name === 'circ_lib')
                            .forEach(attr => {
                                attr.hasChanged = true;
                                attr.checkValuesForCSS();
                            });
                    }
                }
            }

            const vol = copy.call_number();

            if (field === 'owning_lib' && vol.owning_lib() === value) { return; } // No change needed
            if (field === 'prefix' && vol.prefix() === value) { return; } // No change needed
            if (field === 'suffix' && vol.suffix() === value) { return; } // No change needed
            if (field === 'label_class' && vol.label_class() === value) { return; } // No change needed

            let newVol;
            if (newVols[vol.id()]) {
                newVol = newVols[vol.id()];

            } else {

                // The open-ils.cat.asset.volume.fleshed.batch.update API
                // will use the existing volume when trying to create a
                // new volume with the same parameters as an existing volume.
                newVol = this.idl.clone(vol);
                if (field === 'owning_lib') { newVol.owning_lib(value); }
                if (field === 'prefix') { newVol.prefix(value); }
                if (field === 'suffix') { newVol.suffix(value); }
                if (field === 'label_class') { newVol.label_class(value); }
                newVol.id(this.volcopy.autoId--);
                newVol.isnew(true);
                newVols[vol.id()] = newVol;
            }

            copy.call_number(newVol);
            this.originalVols[newVol.id()] = this.originalVols[vol.id()]; // associate original volume with new volume
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

            let entry = (copy.stat_cat_entries() || [])
                .filter(e => e.stat_cat() === catId)[0];

            if (clear) {

                if (entry) {
                    // Removing the entry map (and setting copy.ishanged) is
                    // enough to tell the API to delete it.

                    copy.stat_cat_entries( (copy.stat_cat_entries() || [])
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
                    if (!copy.stat_cat_entries()) {
                        copy.stat_cat_entries([]);
                    }
                    copy.stat_cat_entries().push(entry);
                }

                entry.id(entryId);
                entry.value(this.volcopy.statCatEntryMap[entryId].value());
            }

            copy.ischanged(true);
        });

        this.emitSaveChange();
    }

    valueCleared(fieldName: string) {
        // Reset all batch attributes
        const attr = this.batchAttrs.find(attr => attr.name === fieldName);
        attr.hasChanged = false;
        attr.editing = false;
        attr.checkValuesForCSS();
        // console.debug('attr ' + attr.name, attr);
        if (this.context) {
            // Restore copies from backup
            this.context.copyList().forEach(copy => {
                const originalCopy = this.originalCopies[copy.id()];
                if (!originalCopy) {
                    console.error(`valueCleared, No original state found for copy ${copy.id()}`);
                    return;
                }

                // Determines if copy ischanged() should change
                let resetCopyIsChanged = true;

                if (fieldName === 'owning_lib' || fieldName === 'prefix' || fieldName === 'suffix' || fieldName === 'label_class') {
                    // Special handling
                    const vol = copy.call_number();
                    const origVol = this.originalVols[ vol.id() ];
                    if (!origVol) {
                        console.error(`valueCleared, No original state found for volume ${vol.id()}`);
                        return;
                    }
                    const volValue = this.idl.pkeyValue(vol[fieldName]());
                    const origVolValue = this.idl.pkeyValue(origVol[fieldName]());
                    // Restore vol field from the original
                    vol[fieldName](origVolValue);

                    // Test to see if vol ischanged() should change
                    let resetVolIsChanged = true;
                    this.idl.classes['acn'].fields.forEach(idlField => {
                        if (idlField.name !== 'call_number') {
                            if (vol[idlField.name]() !== origVol[idlField.name]()) {
                                resetVolIsChanged = false;
                                resetCopyIsChanged = false;
                            }
                        }
                    });
                    if (resetVolIsChanged) {
                        // console.debug(`valueCleared, setting isChanged() to false for volume ${vol.id()}`);
                        vol.ischanged(false);
                    }
                    // console.debug('vol ' + copy.call_number().id(), copy.call_number());
                } else {
                    const copyValue = this.idl.pkeyValue(copy[fieldName]());
                    const origCopyValue = this.idl.pkeyValue(originalCopy[fieldName]());
                    // Restore copy field from the original
                    copy[fieldName](origCopyValue);
                }

                this.idl.classes['acp'].fields.forEach(idlField => {
                    if (idlField.name !== 'call_number' && idlField.name !== 'owning_lib' && idlField.name !== 'prefix' && idlField.name !== 'suffix' && idlField.name !== 'label_class') {
                        if (copy[idlField.name]() !== originalCopy[idlField.name]()) {
                            resetCopyIsChanged = false;
                        }
                    }
                });
                if (resetCopyIsChanged) {
                    // console.debug(`valueCleared, setting isChanged() to false for copy ${copy.id()}`);
                    copy.ischanged(false);
                }
                // console.debug('copy ' + copy.id(), copy);
            });
        }
        // "new" values new conditions
        attr.checkValuesForCSS();
    }

    valueClearedForStatCat(catId: number) {
        const attr = this.batchAttrs.find(attr => attr.name === `stat_cat_${catId}`);
        if (attr) {
            attr.hasChanged = false;
            attr.editing = false;
            attr.checkValuesForCSS();
        } else {
            console.debug(`valueClearedForStatCat, stat_cat_${catId} attr not found`);
        }
        catId = Number(catId);
        // console.debug('valueClearedForStatCat, catId, this.statCatValues', catId, this.statCatValues);
        if (this.context) {
            // Restore copies from backup
            this.context.copyList().forEach(copy => {
                // console.debug('valueClearedForStatCat, considering copy.id, copy', copy.id(), copy);
                const originalCopy = this.originalCopies[copy.id()];
                const entries = copy.stat_cat_entries();
                const originalEntries = originalCopy.stat_cat_entries();

                // Find if there's a matching entry in entries
                const catIdIndex = entries.findIndex(entry => entry.stat_cat() === catId);

                // Handle the case where originalEntries might be null/undefined
                if (!originalEntries) {
                    // console.debug('valueClearedForStatCat, no original entries, at all');
                    // If originalEntries doesn't exist, remove any matching entry from entries
                    if (catIdIndex !== -1) {
                        // console.debug('valueClearedForStatCat, removing current entry');
                        entries.splice(catIdIndex, 1);
                    }
                } else {
                    // Look for a matching entry in originalEntries
                    const orig = originalEntries.find(entry => entry.stat_cat() === catId);

                    if (orig) {
                        // console.debug('valueClearedForStatCat, found original entry');
                        // Clone the original matching entry
                        const clonedOrig = this.idl.clone(orig);

                        if (catIdIndex !== -1) {
                            // Replace the existing entry with the clone
                            // console.debug('valueClearedForStatCat, replacing current entry with original');
                            entries[catIdIndex] = clonedOrig;
                        } else {
                            // Append the clone to entries
                            entries.push(clonedOrig);
                            // console.debug('valueClearedForStatCat, re-adding original');
                        }
                    } else {
                        // console.debug('valueClearedForStatCat, original entry not found');
                        // No matching original entry, remove from entries if it exists
                        if (catIdIndex !== -1) {
                            // console.debug('valueClearedForStatCat, deleting current entry');
                            entries.splice(catIdIndex, 1);
                        }
                    }
                }

                // Do we need to change copy .isChanged()?
                if (copy.call_number().ischanged()) {
                    let resetCopyIsChanged = true;
                    this.idl.classes['acp'].fields.forEach(idlField => {
                        if (idlField.name !== 'call_number' && idlField.name !== 'owning_lib' && idlField.name !== 'prefix' && idlField.name !== 'suffix' && idlField.name !== 'label_class') {
                            if (copy[idlField.name]() !== originalCopy[idlField.name]()) {
                                resetCopyIsChanged = false;
                            }
                        }
                    });
                    if (resetCopyIsChanged) {
                        // console.debug(`valueClearedForStatCat, setting isChanged() to false for copy ${copy.id()}`);
                        copy.ischanged(false);
                    }
                }
            });
        }
        // console.debug('valueClearedForStatCat, deleting catId from this.statCatValues');
        delete this.statCatValues[catId];
        if (attr) {
            attr.checkValuesForCSS();
        }
    }

    hasClearedAlerts(): boolean {
        return this.context.changedAlerts?.some(a => a.ack_time());
    }

    getClearedAlertCount(): number {
        return this.context.changedAlerts?.filter(a => a.ack_time()).length || 0;
    }

    initCopyAlerts() {
        // console.debug('CopyAlertsDialog, initCopyAlerts(), this.copyAlertsDialog', this.copyAlertsDialog);
        if (!this.copyAlertsDialog) {return;}

        // The dialog is already persistent on the template
        this.copyAlertsDialog.copies = this.context.copyList();
        this.copyAlertsDialog.copyIds = [];
        this.copyAlertsDialog.inPlaceCreateMode = true;
        this.copyAlertsDialog.templateOnlyMode = this.templateOnlyMode;
        // console.debug('templateOnlyMode', this.copyAlertsDialog.templateOnlyMode);

        // Pre-populate any existing changes
        this.copyAlertsDialog.newThings = this.context.newAlerts.map( n => this.idl.clone(n) ) as ICopyAlert[];
        this.copyAlertsDialog.changedThings = this.context.changedAlerts.map( c => this.idl.clone(c) ) as ICopyAlert[];
        this.copyAlertsDialog.deletedThings = this.context.deletedAlerts.map( d => this.idl.clone(d) ) as ICopyAlert[];

        this.copyAlertsDialog.initialize();
    }

    openCopyAlerts($event) {
        $event.preventDefault();
        $event.stopPropagation();
        this.initCopyAlerts();
        this.copyAlertsDialog.open({size: 'lg'}).subscribe(changes => {
            if (!changes) { return; }

            const { newThings, changedThings, deletedThings } = changes;
            // console.debug('CopyAlertsDialog, openCopyAlerts(), changes', changes);

            this.context.newAlerts = newThings;
            this.context.changedAlerts = changedThings;
            this.context.deletedAlerts = deletedThings;

            // console.debug('CopyAlertsDialog, openCopyAlerts(), copy before updateInMemory', this.idl.clone(this.context.copyList()[0]));
            this.context.updateInMemoryCopiesWithAlerts();
            // console.debug('CopyAlertsDialog, openCopyAlerts(), copy after updateInMemory', this.idl.clone(this.context.copyList()[0]));
            this.emitSaveChange();

        });
    }

    initCopyTags() {
        // console.debug('CopyTagsDialog, initCopyTags(), this.copyTagsDialog', this.copyTagsDialog);
        if (!this.copyTagsDialog) {return;}

        // The dialog is already persistent on the template
        this.copyTagsDialog.copies = this.context.copyList();
        this.copyTagsDialog.copyIds = [];
        this.copyTagsDialog.inPlaceCreateMode = true;
        this.copyTagsDialog.templateOnlyMode = this.templateOnlyMode;
        // console.debug('templateOnlyMode', this.copyTagsDialog.templateOnlyMode);

        // Pre-populate any existing changes
        this.copyTagsDialog.newThings = this.context.newTagMaps as ICopyTagMap[];
        this.copyTagsDialog.changedThings = this.context.changedTagMaps as ICopyTagMap[];
        this.copyTagsDialog.deletedThings = this.context.deletedTagMaps as ICopyTagMap[];

        this.copyTagsDialog.initialize();
    }

    openCopyTags($event) {
        $event.preventDefault();
        $event.stopPropagation();
        this.initCopyTags();
        this.copyTagsDialog.open({size: 'lg'}).subscribe(changes => {
            if (!changes) { return; }

            const { newThings, changedThings, deletedThings } = changes;

            this.context.newTagMaps = newThings;
            this.context.changedTagMaps = changedThings;
            this.context.deletedTagMaps = deletedThings;

            this.context.updateInMemoryCopiesWithTags();
            this.emitSaveChange();

        });
    }

    initCopyNotes() {
        // console.debug('CopyNotesDialog, initCopyNotes(), this.copyNotesDialog', this.copyNotesDialog);
        if (!this.copyNotesDialog) {return;}

        // The dialog is already persistent on the template
        this.copyNotesDialog.copies = this.context.copyList();
        this.copyNotesDialog.copyIds = [];
        this.copyNotesDialog.inPlaceCreateMode = true;
        this.copyNotesDialog.templateOnlyMode = this.templateOnlyMode;
        // console.debug('templateOnlyMode', this.copyNotesDialog.templateOnlyMode);

        // Pre-populate any existing changes
        this.copyNotesDialog.newThings = this.context.newNotes as ICopyNote[];
        this.copyNotesDialog.changedThings = this.context.changedNotes as ICopyNote[];
        this.copyNotesDialog.deletedThings = this.context.deletedNotes as ICopyNote[];

        this.copyNotesDialog.initialize();
    }

    openCopyNotes($event) {
        $event.preventDefault();
        $event.stopPropagation();
        this.initCopyNotes();
        this.copyNotesDialog.open({size: 'lg'}).subscribe(changes => {
            if (!changes) { return; }

            const { newThings, changedThings, deletedThings } = changes;

            this.context.newNotes = newThings;
            this.context.deletedNotes = deletedThings;
            this.context.changedNotes = changedThings;

            this.context.updateInMemoryCopiesWithNotes();
            this.emitSaveChange();

        });
    }

    async applyTemplate(providedTemplate?: any): Promise<void> {
        const entry = providedTemplate || this.copyTemplateCbox.selected;
        // console.debug('applyTemplate, entry', entry);
        if (!entry) { return; }

        this.saveTemplateCboxSelection(entry);

        const template = this.volcopy.templates[entry.id];
        // console.debug('applyTemplate, template', template);

        Object.keys(template).forEach(field => {
            const value = template[field];
            // console.debug('applyTemplate, field, value', field, value);

            if (value === null || value === undefined) { return; }
            if (field === 'status' && this.volcopy.copyStatIsMagic(value)) { return; }

            // Call number 'value' was nested object with call number-
            // specific key-value pairs. This is being supplanted with
            // prefix, suffix, and label_class as sibling attributes with
            // the copy fields, and they may now be updated independently.
            // Resaving such an applied template will remove the nested
            // structure.
            if (field === 'callnumber') {
                // Currently supported fields are prefix, suffix, and
                // classification (label_class).  These all use numeric
                // values as defaults.
                const changedFields = Object.keys(value).map((templateKey) => {
                    if (templateKey === 'classification') {
                        return 'label_class';
                    } else {
                        return templateKey;
                    }
                });
                Object.keys(value).forEach(field => {
                    const newVal = value[field];

                    if (field === 'classification') {
                        field = 'label_class';
                    }

                    let changeMade = false;
                    this.context.volNodes().forEach(volNode => {
                        if (Number(volNode.target[field]())) {
                            if (newVal !== volNode.target[field]()) {
                                volNode.target[field](newVal);
                                volNode.target.ischanged(true);
                                volNode.target.ischanged(changedFields);
                                changeMade = true;
                            }
                        }
                    });
                    if (changeMade) {
                        this.batchAttrs
                            .filter(ba => ba.name === field)
                            .forEach(attr => {
                                attr.hasChanged = true;
                                attr.checkValuesForCSS();
                            });
                    }
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
                        if (attr) {
                            attr.hasChanged = true;
                            attr.checkValuesForCSS();
                        }
                    }
                });
                return;
            }

            // Copy alerts are stored as hashes of the bits we need.
            // Templates can be used to create alerts, but not edit them.
            if (field === 'copy_alerts' && Array.isArray(value)) {
                value.forEach(a => {
                    // Check for existing alert, don't apply duplicates
                    let dupskip = 0;
                    this.context.newAlerts.forEach(curAlert => {
                        if(a.alert_type === curAlert.alert_type() &&
                           a.temp === curAlert.temp() &&
                           a.note === curAlert.note() ) {
                            const dup_msg = $localize`Already have this alert`;
                            console.warn(dup_msg, a);
                            this.toast.warning(dup_msg);
                            dupskip = 1;
                        }
                    });
                    if(dupskip) {return;} // skip this alert

                    const newAlert = this.idl.create('aca');
                    newAlert.id(this.volcopy.autoId--);
                    newAlert.isnew(true);
                    newAlert.alert_type(a.alert_type);
                    if (this.copyAlertsDialog.disabledAlertTypes.includes(a.alert_type)) {
                        const inactive_msg = $localize`Alert using an inactive alert type. Template needs updating.`;
                        console.warn(inactive_msg, a);
                        this.toast.warning(inactive_msg);
                    }
                    newAlert.temp(a.temp);
                    newAlert.note(a.note);
                    newAlert.create_staff(this.auth.user().id());
                    newAlert.create_time('now');

                    this.context.newAlerts.push(newAlert); // for our pending display
                });
                this.context.updateInMemoryCopiesWithAlerts();

                return;
            }

            // Since there should be no extant tag templates in the wild (none would be working),
            // we'll go ahead and change the representation here. We'll match on the ID here, but
            // include other tag information for troubleshooting. Less portable, but the precedent
            // has already been set, and this dissolves the problem of matching, which would
            // involve org units and tag types, which are already not portable.

            if (field === 'tags' && Array.isArray(value)) {
                value.forEach(async (a) => {
                    let actualTag = null;
                    if (! ('id' in a)) {
                        const err_msg = $localize`Tag in template missing id field`;
                        console.error(err_msg, a);
                        this.toast.danger(err_msg);
                        return;
                    } else {
                        try {
                            const flesh = {
                                flesh: 1,
                                flesh_fields: {
                                    acpt: ['tag_type']
                                }
                            };
                            // TODO: caching
                            actualTag = await firstValueFrom(this.pcrud.retrieve('acpt', a.id, flesh));
                            // console.debug('actualTag', actualTag);
                            if (!actualTag) {
                                const err_msg = $localize`Tag in template not found`;
                                console.error(err_msg, a);
                                this.toast.danger(err_msg);
                                return;
                            }
                        } catch(E) {
                            const err_msg = $localize`Error retrieving tag from template`;
                            console.error(err_msg, E);
                            this.toast.danger(err_msg);
                            return;
                        }
                    }
                    // Check for existing alert, don't apply duplicates
                    let dupskip = 0;
                    this.context.newTagMaps.forEach(curTagMap => {
                        const curTag = curTagMap.tag();
                        if(a.id === this.idl.pkeyValue( curTag ) ) {
                            const dup_msg = $localize`Already have a tagmap pointing to this tag`;
                            console.warn(dup_msg,a);
                            this.toast.warning(dup_msg);
                            dupskip = 1;
                        }
                    });
                    if(dupskip) {return;} // skip this tag map

                    // no longer vivicating tags here, just tag maps
                    const newTagMap = this.idl.create('acptcm');
                    newTagMap.id(this.volcopy.autoId--);
                    newTagMap.isnew(true);
                    const tag = actualTag || this.idl.fromHash(a, 'acpt') ;
                    if (typeof tag.id !== 'function') {
                        // console.debug('tag from hash', tag);
                        const err_msg = $localize`Invalid tag found in template.`;
                        console.error(err_msg);
                        this.toast.danger(err_msg);
                        return;
                    }
                    newTagMap.tag( tag );
                    const tag_type = typeof tag.tag_type().code !== 'function'
                        ? this.idl.fromHash( tag.tag_type(), 'cctt' )
                        : tag.tag_type();
                    if (typeof tag_type.code !== 'function') {
                        // console.debug('tag_type from hash', tag_type);
                        const err_msg = $localize`Invalid tag type found in template.`;
                        console.error(err_msg);
                        this.toast.danger(err_msg);
                        return;
                    }
                    newTagMap.tag().tag_type( tag_type );

                    this.context.newTagMaps.push( newTagMap ); // for our pending display
                    console.debug('applying tags...', this);
                });
                // wait for the async tag calls to finish
                setTimeout(() => {
                    this.context.updateInMemoryCopiesWithTags();
                }, 100);

                return;
            }

            // Copy notes are stored as hashes of the bits we need.
            // Templates can be used to create notes, but not edit them.
            if (field === 'notes' && Array.isArray(value)) {
                value.forEach(a => {
                    // Check for existing alert, don't apply duplicates
                    let dupskip = 0;
                    this.context.newNotes.forEach(curNote => {
                        if(a.pub === curNote.pub() &&
                           a.title === curNote.title() &&
                           a.value === curNote.value() ) {
                            const dup_msg = $localize`Already have this note`;
                            console.warn(dup_msg, a);
                            this.toast.warning(dup_msg);
                            dupskip = 1;
                        }
                    });
                    if(dupskip) {return;} // skip this note

                    const newNote = this.idl.create('acpn');
                    newNote.id(this.volcopy.autoId--);
                    newNote.isnew(true);
                    newNote.pub(a.pub);
                    newNote.title(a.title);
                    newNote.value(a.value);

                    this.context.newNotes.push( newNote ); // for our pending display
                });
                this.context.updateInMemoryCopiesWithNotes();

                return;
            }

            // In some cases, we may have to fetch the data since
            // the local code assumes copy field is fleshed.
            let promise = Promise.resolve(value);

            if (field === 'location' && value !== null) {
                // May be a 'remote' location.  Fetch as needed.
                promise = this.volcopy.getLocation(Number(value));
            }

            promise.then(val => {
                if (value !== null && val === null) {
                    console.debug(`broken value for field ${field}`, value);
                }
                this.applyCopyValue(field, val);

                // Indicate in the form these values have changed
                this.batchAttrs
                    .filter(ba => ba.name === field)
                    .forEach(attr => {
                        attr.hasChanged = true;
                        attr.checkValuesForCSS();
                    });
            });
        });
    }

    saveTemplate(isnew: boolean) {

        let name;
        let template;
        let entry = this.copyTemplateCbox.selected;
        if (isnew || !entry) {
            if (entry) {
                name = this.copyTemplateCbox.selected.label;
            } else {
                name = window.prompt($localize`Enter name for template`);
            }
            if (!name) { return; }
            if (this.volcopy.templateNames.map(t => t.label).includes(name)) {
                window.alert($localize`There is already a template with this name; not saved.`);
                return;
            }
            entry = {label: name, id: name, freetext: false};
        } else {
            name = entry.id;
        }
        // eslint-disable-next-line prefer-const
        template = {}; // never additive

        this.batchAttrs.forEach(comp => {
            if (!comp.hasChanged) { return; }

            const field = comp.name;
            const value = this.values[field];

            console.debug('Building template: found field, value', field, value);

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
            console.debug('Building template: set field, value', field, template[field]);
        });

        // alerts, tags, and notes
        const newAlerts = this.volcopy.currentContext.newAlerts || [];
        console.debug('Building template: found copy alerts',newAlerts);
        template.copy_alerts = [];
        newAlerts.forEach( n_alert => {
            const t_alert = {
                'temp': n_alert.temp(),
                'alert_type': n_alert.alert_type(),
                'note' : n_alert.note()
            };
            console.debug('Building template: pushing t_alert',t_alert);
            template.copy_alerts.push(t_alert);
        } );
        if (!template.copy_alerts.length) {
            delete template.copy_alerts;
        }

        const newTagMaps = this.volcopy.currentContext.newTagMaps || [];
        console.debug('Building template: found copy tags',newTagMaps);
        template.tags = [];
        newTagMaps.forEach( n_tagmap => {
            // See tag comments under applyTemplates
            console.log('n_tagmap', n_tagmap);
            const t_tag = {
                'id': n_tagmap.tag().id(), // the only match point, the rest is for troubleshooting <- not actually true at the moment
                'pub': n_tagmap.tag().pub(),
                'tag_type': this.idl.toHash( n_tagmap.tag().tag_type() ),
                'label': n_tagmap.tag().label(),
                'value': n_tagmap.tag().value(),
                'staff_note' : n_tagmap.tag().staff_note() || ''
            };
            console.debug('Building template: pushing t_tag',t_tag);
            template.tags.push(t_tag);
        } );
        if (!template.tags.length) {
            delete template.tags;
        }

        const newNotes = this.volcopy.currentContext.newNotes || [];
        console.debug('Building template: found copy notes',newNotes);
        template.notes = [];
        newNotes.forEach( n_note => {
            const t_note = {
                'pub': n_note.pub(),
                'title': n_note.title(),
                'value' : n_note.value()
            };
            console.debug('Building template: pushing t_note',t_note);
            template.notes.push(t_note);
        } );
        if (!template.notes.length) {
            delete template.notes;
        }

        // wrap it up
        console.debug('Building template: all together',template);

        let confirmed = true;
        if (! Object.keys(template).length) {
            confirmed = window.confirm($localize`This would save as an empty template. Are you sure?`);
        }
        if (confirmed) {
            this.volcopy.templates[name] = template;
            this.volcopy.saveTemplates().then(x => {
                this.savedHoldingsTemplates.current().then(str => this.toast.success(str + ' ' + name));
                if (isnew) {
                    // give combobox a lil' shove
                    this.copyTemplateCbox.entrylist.unshift(entry);
                }
                this.saveTemplateCboxSelection(entry);
            });
        }
    }

    exportTemplate($event) {
        return this.volcopy.exportTemplate($event, false);
    }

    importTemplate($event) {
        return this.volcopy.importTemplate($event);
    }

    // Returns null when no export is in progress.
    exportTemplateUrl(): SafeUrl {
        return this.volcopy.exportTemplateUrl();
    }

    deleteTemplate() {
        const entry: ComboboxEntry = this.copyTemplateCbox.selected;
        if (!entry) { return; }
        delete this.volcopy.templates[entry.id];
        this.volcopy.saveTemplates().then(
            x => this.deletedHoldingsTemplate.current().then(str => this.toast.success(str + ' ' + name))
        );
        let newId; // prevent null / undefined from causing an expression checked error
        this.copyTemplateCbox.selected = newId;
        this.saveTemplateCboxSelection({id: newId});
    }

    displayAttr(field: string): boolean {
        // show everything for templateOnlyMode
        return this.templateOnlyMode || this.volcopy.defaults?.hidden?.[field] !== true;
    }

    fieldLabel(field: string): string {

        // handle non-copy fields first
        switch(field) {
            case 'label_class': return $localize`Call Number Label Classification`;
            case 'prefix': return $localize`Call Number Prefix`;
            case 'suffix': return $localize`Call Number Suffix`;
        }

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
            // console.debug('CopyAttrsComponent, emitSaveChange()');
            const canSave = this.batchAttrs.filter(
                attr => {
                    const w= attr.warnOnRequired();
                    // console.debug('attr.warnOnRequired()', attr, w);
                    return w;
                }).length === 0;
            // console.debug('CopyAttrsComponent, emitSaveChange(), canSave', canSave);
            this.canSaveChange.emit(canSave);
        });
    }

    // True if one of our batch editors has been put into edit
    // mode and left there without an Apply, Cancel, or Clear
    hasActiveInput(): boolean {
        return this.batchAttrs.filter(attr => attr.editing).length > 0;
    }

    onKeydown(field: string, $event) {
        switch ($event.key) {
            case 'Escape':
                // console.debug('Canceling out of', field);
                this.cancel(field);
                break;
            case 'Enter':
                // console.debug('Saving', field);
                this.save(field);
                break;
        }
    }

    save(field) {
        // console.debug('save() on Enter:', field, this.values[field]);
        this.batchAttrs.filter(attr => attr.editing && attr.name === field).forEach(attr => attr.save());
    }

    cancel(field) {
        this.batchAttrs.filter(attr => attr.editing && attr.name === field).forEach(attr => attr.cancel());
    }

    applyPendingChanges() {
        // console.debug('applyPendingChanges()');
        // If a user has left any changes in the 'editing' state, this
        // will go through and apply the values so they do not have to
        // click Apply for every one.
        this.batchAttrs.filter(attr => attr.editing).forEach(attr => attr.save());
    }

    copyLocationOrgs(): number[] {
        if (!this.context) { console.debug('No copy location context'); return []; }

        // Make sure every org unit represented by the edit batch
        // is represented.
        const ids = this.context.orgNodes()?.map(n => n.target.id()) || [];

        // Make sure all locations within the "full path" of our
        // workstation org unit are included.
        return ids.concat(this.org.fullPath(this.auth.user().ws_ou()));
    }

    alertsHaveChanged() {
        return this.context?.newAlerts?.length
        || this.context?.changedAlerts?.length
        || this.context?.deletedAlerts?.length;
    }

    tagsHaveChanged() {
        return this.context?.newTagMaps?.length
        || this.context?.changedTagMaps?.length
        || this.context?.deletedTagMaps?.length;
    }

    notesHaveChanged() {
        return this.context?.newNotes?.length
        || this.context?.changedNotes?.length
        || this.context?.deletedNotes?.length;
    }

    clearChangesAction() {
        // console.debug('clearChangesAction()');
        // Reset all batch attributes
        this.batchAttrs.forEach(attr => {
            attr.hasChanged = false;
            attr.editing = false;
            attr.checkValuesForCSS();
            // console.debug('attr ' + attr.name, attr);
        });

        // Clear all values
        this.values = {};
        this.statCatValues = {};

        if (this.copyAlertsDialog) {
            this.copyAlertsDialog.clearPending();
            this.context.newAlerts = []; // not sure why the binding isn't behaving bidirectionally
            this.context.changedAlerts = [];
            this.context.deletedAlerts = [];
        }
        if (this.copyTagsDialog) {
            this.copyTagsDialog.clearPending();
            this.context.newTagMaps = []; // not sure why the binding isn't behaving bidirectionally
            this.context.changedTagMaps = [];
            this.context.deletedTagMaps = [];
        }
        if (this.copyNotesDialog) {
            this.copyNotesDialog.clearPending();
            this.context.newNotes = []; // not sure why the binding isn't behaving bidirectionally
            this.context.changedNotes = [];
            this.context.deletedNotes = [];
        }

        if (this.context) {
            // Restore copies from backup
            this.context.copyList().forEach(copy => {
                const originalCopy = this.originalCopies[copy.id()];
                if (!originalCopy) {
                    // console.debug(`No original state found for copy ${copy.id()}`);
                    this.originalCopies[copy.id()] = this.idl.create('acp');
                    this.originalCopies[copy.id()].id( copy.id() );
                }

                // Restore each field from the original
                this.idl.classes['acp'].fields.forEach(field => {
                    if (field.name !== 'call_number') {
                        copy[field.name](originalCopy[field.name]());
                    }
                });

                copy.ischanged(false);
                // console.debug('copy ' + copy.id(), copy);
            });

            // Restore volumes from backup
            this.context.volNodes().forEach(volNode => {
                const originalVol = this.originalVols[volNode.target.id()];
                if (!originalVol) {
                    // console.debug(`No original state found for volume ${volNode.target.id()}`);
                    this.originalVols[volNode.target.id()] = this.idl.create('acn');
                    this.originalVols[volNode.target.id()].id( volNode.target.id() );
                }
                this.idl.classes['acn'].fields.forEach(field => {
                    volNode.target[field.name](originalVol[field.name]());
                });
                volNode.target.ischanged(false);
                // console.debug('volNode ' + volNode.target.id(), volNode);
            });

            // "new" values new conditions
            this.batchAttrs.forEach(attr => {
                attr.checkValuesForCSS();
            });
        }

        this.clearChanges.emit(null);
    }

    hasDisabledAlerts(alerts: any[]): boolean {
        return alerts?.some(alert => this.copyAlertsDialog && this.copyAlertsDialog?.disabledAlertTypes?.includes(alert.alert_type()));
    }

    countTotalTags(): number {
        if (!this.copyTagsDialog) {return 0;}
        let existing = [];

        if (this.context.copyList().length > 1 ) {
            existing = this.copyTagsDialog.allTagsInCommon;
        } else {
            existing = this.context.copyList()[0].tags();
        }

        // console.debug('countTotalTags: ', existing.length, this.context.newTagMaps.length, this.context.deletedTagMaps.length);
        return existing.length + this.context.newTagMaps.length - this.context.deletedTagMaps.length;
    }
}



