import {Component, OnInit, Input, ViewChild,
    Output, EventEmitter, TemplateRef} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {FormatService} from '@eg/core/format.service';
import {TranslateComponent} from '@eg/share/translate/translate.component';
import {FmRecordEditorActionComponent} from './fm-editor-action.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

interface CustomFieldTemplate {
    template: TemplateRef<any>;

    // Allow the caller to pass in a free-form context blob to
    // be addedto the caller's custom template context, along
    // with our stock context.
    context?: {[fields: string]: any};
}

export interface CustomFieldContext {
    // Current create/edit/view record
    record: IdlObject;

    // IDL field definition blob
    field: any;

    // additional context values passed via CustomFieldTemplate
    [fields: string]: any;
}

// Collection of extra options that may be applied to fields
// for controling non-default behaviour.
export interface FmFieldOptions {

    // Render the field as a combobox using these values, regardless
    // of the field's datatype.
    customValues?: ComboboxEntry[];

    // Provide / override the "selector" value for the linked class.
    // This is the field the combobox will search for typeahead.  If no
    // field is defined, the "selector" field is used.  If no "selector"
    // field exists, the combobox will pre-load all linked values so
    // the user can click to navigate.
    linkedSearchField?: string;

    // When true for combobox fields, pre-fetch the combobox data
    // so the user can click or type to find values.
    preloadLinkedValues?: boolean;

    // Directly override the required state of the field.
    // This only has an affect if the value is true.
    isRequired?: boolean;

    // If this function is defined, the function will be called
    // at render time to see if the field should be marked are required.
    // This supersedes all other isRequired specifiers.
    isRequiredOverride?: (field: string, record: IdlObject) => boolean;

    // Directly apply the readonly status of the field.
    // This only has an affect if the value is true.
    isReadonly?: boolean;

    // If this function is defined, the function will be called
    // at render time to see if the field should be marked readonly.
    // This supersedes all other isReadonly specifiers.
    isReadonlyOverride?: (field: string, record: IdlObject) => boolean;

    // Render the field using this custom template instead of chosing
    // from the default set of form inputs.
    customTemplate?: CustomFieldTemplate;
}

@Component({
  selector: 'eg-fm-record-editor',
  templateUrl: './fm-editor.component.html',
  /* align checkboxes when not using class="form-check" */
  styles: ['input[type="checkbox"] {margin-left: 0px;}']
})
export class FmRecordEditorComponent
    extends DialogComponent implements OnInit {

    // IDL class hint (e.g. "aou")
    @Input() idlClass: string;

    // Show datetime fields in this particular timezone
    timezone: string = this.format.wsOrgTimezone;

    // Permissions extracted from the permacrud defs in the IDL
    // for the current IDL class
    modePerms: {[mode: string]: string};

    // Collection of FmFieldOptions for specifying non-default
    // behaviour for each field (by field name).
    @Input() fieldOptions: {[fieldName: string]: FmFieldOptions} = {};

    // This is used to set default values when making a new record
    @Input() defaultNewRecord: IdlObject;

    // list of fields that should not be displayed
    @Input() hiddenFieldsList: string[] = [];
    @Input() hiddenFields: string; // comma-separated string version

    // list of fields that should always be read-only
    @Input() readonlyFieldsList: string[] = [];
    @Input() readonlyFields: string; // comma-separated string version

    // list of required fields; this supplements what the IDL considers
    // required
    @Input() requiredFieldsList: string[] = [];
    @Input() requiredFields: string; // comma-separated string version

    // list of timestamp fields that should display with a timepicker
    @Input() datetimeFieldsList: string[] = [];
    @Input() datetimeFields: string; // comma-separated string version

    // list of org_unit fields where a default value may be applied by
    // the org-select if no value is present.
    @Input() orgDefaultAllowedList: string[] = [];
    @Input() orgDefaultAllowed: string; // comma-separated string version

    // IDL record display label.  Defaults to the IDL label.
    @Input() recordLabel: string;

    // When true at the component level, pre-fetch the combobox data
    // for all combobox fields.  See also FmFieldOptions.
    @Input() preloadLinkedValues: boolean;

    // Display within a modal dialog window or inline in the page.
    @Input() displayMode: 'dialog' | 'inline' = 'dialog';

    // Hide the top 'Record Editor: ...' banner.  Primarily useful
    // for displayMode === 'inline'
    @Input() hideBanner: boolean;

    // Emit the modified object when the save action completes.
    @Output() recordSaved = new EventEmitter<IdlObject>();

    // Emit the modified object when the save action completes.
    @Output() recordDeleted = new EventEmitter<IdlObject>();

    // Emit the original object when the save action is canceled.
    @Output() recordCanceled = new EventEmitter<IdlObject>();

    // Emit an error message when the save action fails.
    @Output() recordError = new EventEmitter<string>();

    @ViewChild('translator', { static: true }) private translator: TranslateComponent;
    @ViewChild('successStr', { static: true }) successStr: StringComponent;
    @ViewChild('failStr', { static: true }) failStr: StringComponent;
    @ViewChild('confirmDel', { static: true }) confirmDel: ConfirmDialogComponent;

    // IDL info for the the selected IDL class
    idlDef: any;

    // Can we edit the primary key?
    pkeyIsEditable = false;

    // List of IDL field definitions.  This is a subset of the full
    // list of fields on the IDL, since some are hidden, virtual, etc.
    fields: any[];

    // DOM id prefix to prevent id collisions.
    idPrefix: string;

    // mode: 'create' for creating a new record,
    //       'update' for editing an existing record
    //       'view' for viewing an existing record without editing
    @Input() mode: 'create' | 'update' | 'view' = 'create';

    // custom function for munging the record before it gets saved;
    // will get passed mode and the record itself
    @Input() preSave: Function;

    // recordId and record getters and setters.
    // Note that setting the this.recordId to NULL does not clear the
    // current value of this.record and vice versa.  Only viable data
    // is actionable.  This allows the caller to use both @Input()'s
    // without each clobbering the other.

    // Record ID to view/update.
    _recordId: any = null;
    @Input() set recordId(id: any) {
        if (id) {
            if (id !== this._recordId) {
                this._recordId = id;
                this._record = null; // force re-fetch
                this.handleRecordChange();
            }
        } else {
            this._recordId = null;
        }
    }

    get recordId(): any {
        return this._recordId;
    }

    // IDL record we are editing
    _record: IdlObject = null;
    @Input() set record(r: IdlObject) {
        if (r) {
            if (!this.idl.pkeyMatches(this.record, r)) {
                this._record = r;
                this._recordId = null; // avoid mismatch
                this.handleRecordChange();
            }
        } else {
            this._record = null;
        }
    }

    get record(): IdlObject {
        return this._record;
    }

    actions: FmRecordEditorActionComponent[] = [];

    initDone: boolean;

    // Comma-separated list of field names defining the order in which
    // fields should be rendered in the form.  Any fields not represented
    // will be rendered alphabetically by label after the named fields.
    @Input() fieldOrder: string;

    // When true, show a delete button and support delete operations.
    @Input() showDelete: boolean;

    constructor(
      private modal: NgbModal, // required for passing to parent
      private idl: IdlService,
      private auth: AuthService,
      private toast: ToastService,
      private format: FormatService,
      private pcrud: PcrudService) {
      super(modal);
    }

    // Avoid fetching data on init since that may lead to unnecessary
    // data retrieval.
    ngOnInit() {

        // In case the caller sets the value to null / undef.
        if (!this.fieldOptions) { this.fieldOptions = {}; }

        this.listifyInputs();
        this.idlDef = this.idl.classes[this.idlClass];
        this.recordLabel = this.idlDef.label;

        // Add some randomness to the generated DOM IDs to ensure against clobbering
        this.idPrefix = 'fm-editor-' + Math.floor(Math.random() * 100000);

        if (this.isDialog()) {
            this.onOpen$.subscribe(() => this.initRecord());
        } else {
            this.initRecord();
        }
        this.initDone = true;
    }

    // If the record ID changes after ngOnInit has been called
    // and we're using displayMode=inline, force the data to
    // resync in real time
    handleRecordChange() {
        if (this.initDone && !this.isDialog()) {
            this.initRecord();
        }
    }

    open(args?: NgbModalOptions): Observable<any> {
        if (!args) {
            args = {};
        }
        // ensure we don't hang on to our copy of the record
        // if the user dismisses the dialog
        args.beforeDismiss = () => {
            this.record = undefined;
            return true;
        };
        return super.open(args);
    }

    isDialog(): boolean {
        return this.displayMode === 'dialog';
    }

    // DEPRECATED: This is a duplicate of this.record = abc;
    setRecord(record: IdlObject) {
        console.warn('fm-editor:setRecord() is deprecated. ' +
            'Use editor.record = abc or [record]="abc" instead');
        this.record = record; // this calls the setter
    }

    // Translate comma-separated string versions of various inputs
    // to arrays.
    private listifyInputs() {
        if (this.hiddenFields) {
            this.hiddenFieldsList = this.hiddenFields.split(/,/);
        }
        if (this.readonlyFields) {
            this.readonlyFieldsList = this.readonlyFields.split(/,/);
        }
        if (this.requiredFields) {
            this.requiredFieldsList = this.requiredFields.split(/,/);
        }
        if (this.datetimeFields) {
            this.datetimeFieldsList = this.datetimeFields.split(/,/);
        }
        if (this.orgDefaultAllowed) {
            this.orgDefaultAllowedList = this.orgDefaultAllowed.split(/,/);
        }
    }

    private initRecord(): Promise<any> {

        const pc = this.idlDef.permacrud || {};
        this.modePerms = {
            view:   pc.retrieve ? pc.retrieve.perms : [],
            create: pc.create ? pc.create.perms : [],
            update: pc.update ? pc.update.perms : [],
        };

        this.pkeyIsEditable = !('pkey_sequence' in this.idlDef);

        if (this.mode === 'update' || this.mode === 'view') {

            let promise;
            if (this.record && this.recordId === null) {
                promise = Promise.resolve(this.record);
            } else if (this.recordId) {
                promise =
                    this.pcrud.retrieve(this.idlClass, this.recordId).toPromise();
            } else {
                // Not enough data yet to fetch anything
                return Promise.resolve();
            }

            return promise.then(rec => {

                if (!rec) {
                    return Promise.reject(`No '${this.idlClass}'
                        record found with id ${this.recordId}`);
                }

                // Set this._record (not this.record) to avoid loop in initRecord()
                this._record = rec;
                this.convertDatatypesToJs();
                return this.getFieldList();
            });
        }

        // In 'create' mode.
        //
        // Create a new record from the stub record provided by the
        // caller or a new from-scratch record
        if (!this.record) {
            // NOTE: Set this._record (not this.record) to avoid
            // loop in initRecord()
            if (this.defaultNewRecord) {
                // Clone to avoid polluting the stub record
                this._record = this.idl.clone(this.defaultNewRecord);
            } else {
                this._record = this.idl.create(this.idlClass);
            }
        }
        this._recordId = null; // avoid future confusion

        return this.getFieldList();
    }

    // Modifies the FM record in place, replacing IDL-compatible values
    // with native JS values.
    private convertDatatypesToJs() {
        this.idlDef.fields.forEach(field => {
            if (field.datatype === 'bool') {
                if (this.record[field.name]() === 't') {
                    this.record[field.name](true);
                } else if (this.record[field.name]() === 'f') {
                    this.record[field.name](false);
                }
            }
        });
    }

    // Modifies the provided FM record in place, replacing JS values
    // with IDL-compatible values.
    convertDatatypesToIdl(rec: IdlObject) {
        const fields = this.idlDef.fields.filter(f => !f.virtual);

        fields.forEach(field => {
            if (field.datatype === 'bool') {
                if (rec[field.name]() === true) {
                    rec[field.name]('t');
                // } else if (rec[field.name]() === false) {
                } else { // TODO: some bools can be NULL
                    rec[field.name]('f');
                }
            } else if (field.datatype === 'org_unit') {
                const org = rec[field.name]();
                if (org && typeof org === 'object') {
                    rec[field.name](org.id());
                }
            }
        });
    }

    private flattenLinkedValues(field: any, list: IdlObject[]): ComboboxEntry[] {
        const class_ = field.class;
        const fieldOptions = this.fieldOptions[field.name] || {};
        const idField = this.idl.classes[class_].pkey;

        const selector = fieldOptions.linkedSearchField
            || this.idl.getClassSelector(class_) || idField;

        return list.map(item => {
            return {id: item[idField](), label: item[selector]()};
        });
    }

    private getFieldList(): Promise<any> {

        const fields = this.idlDef.fields.filter(f =>
            !f.virtual && !this.hiddenFieldsList.includes(f.name));

        // Wait for all network calls to complete
        return Promise.all(
            fields.map(field => this.constructOneField(field))

        ).then(() => {

            if (!this.fieldOrder) {
                this.fields = fields.sort((a, b) => a.label < b.label ? -1 : 1);
                return;
            }

            let newList = [];
            const ordered = this.fieldOrder.split(/,/);

            ordered.forEach(name => {
                const f1 = fields.filter(f2 => f2.name === name)[0];
                if (f1) { newList.push(f1); }
            });

            // Sort remaining fields by label
            const remainder = fields.filter(f => !ordered.includes(f.name));
            remainder.sort((a, b) => a.label < b.label ? -1 : 1);
            newList = newList.concat(remainder);

            this.fields = newList;
        });
    }

    private constructOneField(field: any): Promise<any> {

        let promise = null;
        const fieldOptions = this.fieldOptions[field.name] || {};

        if (this.mode === 'view') {
            field.readOnly = true;
        } else if (fieldOptions.isReadonlyOverride) {
            field.readOnly =
                !fieldOptions.isReadonlyOverride(field.name, this.record);
        } else {
            field.readOnly = fieldOptions.isReadonly === true
                || this.readonlyFieldsList.includes(field.name);
        }

        if (fieldOptions.isRequiredOverride) {
            field.isRequired = () => {
                return fieldOptions.isRequiredOverride(field.name, this.record);
            };
        } else {
            field.isRequired = () => {
                return field.required
                    || fieldOptions.isRequired
                    || this.requiredFieldsList.includes(field.name);
            };
        }

        if (fieldOptions.customValues) {

            field.linkedValues = fieldOptions.customValues;

        } else if (field.datatype === 'link' && field.readOnly) {

            // no need to fetch all possible values for read-only fields
            const idToFetch = this.record[field.name]();

            if (idToFetch) {

                // If the linked class defines a selector field, fetch the
                // linked data so we can display the data within the selector
                // field.  Otherwise, avoid the network lookup and let the
                // bare value (usually an ID) be displayed.
                const selector = fieldOptions.linkedSearchField ||
                    this.idl.getClassSelector(field.class);

                if (selector && selector !== field.name) {
                    promise = this.pcrud.retrieve(field.class, idToFetch)
                        .toPromise().then(list => {
                            field.linkedValues =
                                this.flattenLinkedValues(field, Array(list));
                        });
                } else {
                    // No selector, display the raw id/key value.
                    field.linkedValues = [{id: idToFetch, name: idToFetch}];
                }
            }

        } else if (field.datatype === 'link') {

            promise = this.wireUpCombobox(field);

        } else if (field.datatype === 'timestamp') {
            field.datetime = this.datetimeFieldsList.includes(field.name);
        } else if (field.datatype === 'org_unit') {
            field.orgDefaultAllowed =
                this.orgDefaultAllowedList.includes(field.name);
        }

        if (fieldOptions.customTemplate) {
            field.template = fieldOptions.customTemplate.template;
            field.context = fieldOptions.customTemplate.context;
        }

        return promise || Promise.resolve();
    }

    wireUpCombobox(field: any): Promise<any> {

        const fieldOptions = this.fieldOptions[field.name] || {};

        // globally preloading unless a field-specific value is set.
        if (this.preloadLinkedValues) {
            if (!('preloadLinkedValues' in fieldOptions)) {
                fieldOptions.preloadLinkedValues = true;
            }
        }

        const selector = fieldOptions.linkedSearchField ||
            this.idl.getClassSelector(field.class);

        if (!selector && !fieldOptions.preloadLinkedValues) {
            // User probably expects an async data source, but we can't
            // provide one without a selector.  Warn the user.
            console.warn(`Class ${field.class} has no selector.
                Pre-fetching all rows for combobox`);
        }

        if (fieldOptions.preloadLinkedValues || !selector) {
            return this.pcrud.retrieveAll(field.class, {}, {atomic : true})
            .toPromise().then(list => {
                field.linkedValues =
                    this.flattenLinkedValues(field, list);
            });
        }

        // If we have a selector, wire up for async data retrieval
        field.linkedValuesSource =
            (term: string): Observable<ComboboxEntry> => {

            const search = {};
            const orderBy = {order_by: {}};
            const idField = this.idl.classes[field.class].pkey || 'id';

            search[selector] = {'ilike': `%${term}%`};
            orderBy.order_by[field.class] = selector;

            return this.pcrud.search(field.class, search, orderBy)
            .pipe(map(idlThing =>
                // Map each object into a ComboboxEntry upon arrival
                this.flattenLinkedValues(field, [idlThing])[0]
            ));
        };

        // Using an async data source, but a value is already set
        // on the field.  Fetch the linked object and add it to the
        // combobox entry list so it will be avilable for display
        // at dialog load time.
        const linkVal = this.record[field.name]();
        if (linkVal !== null && linkVal !== undefined) {
            return this.pcrud.retrieve(field.class, linkVal).toPromise()
            .then(idlThing => {
                field.linkedValues =
                    this.flattenLinkedValues(field, Array(idlThing));
            });
        }

        // No linked value applied, nothing to pre-fetch.
        return Promise.resolve();
    }

    // Returns a context object to be inserted into a custom
    // field template.
    customTemplateFieldContext(fieldDef: any): CustomFieldContext {
        return Object.assign(
            {   record : this.record,
                field: fieldDef // from this.fields
            },  fieldDef.context || {}
        );
    }

    save() {
        const recToSave = this.idl.clone(this.record);
        if (this.preSave) {
            this.preSave(this.mode, recToSave);
        }
        this.convertDatatypesToIdl(recToSave);
        this.pcrud[this.mode]([recToSave]).toPromise().then(
            result => {
                this.recordSaved.emit(result);
                this.successStr.current().then(msg => this.toast.success(msg));
                if (this.isDialog()) { this.record = undefined; this.close(result); }
            },
            error => {
                this.recordError.emit(error);
                this.failStr.current().then(msg => this.toast.warning(msg));
                if (this.isDialog()) { this.error(error); }
            }
        );
    }

    remove() {
        this.confirmDel.open().subscribe(confirmed => {
            if (!confirmed) { return; }
            const recToRemove = this.idl.clone(this.record);
            this.pcrud.remove(recToRemove).toPromise().then(
                result => {
                    this.recordDeleted.emit(result);
                    this.successStr.current().then(msg => this.toast.success(msg));
                    if (this.isDialog()) { this.close(result); }
                },
                error => {
                    this.recordError.emit(error);
                    this.failStr.current().then(msg => this.toast.warning(msg));
                    if (this.isDialog()) { this.error(error); }
                }
            );
        });
    }

    cancel() {
        this.recordCanceled.emit(this.record);
        this.record = undefined;
        this.close();
    }

    closeEditor() {
        this.record = undefined;
        this.close();
    }

    // Returns a string describing the type of input to display
    // for a given field.  This helps cut down on the if/else
    // nesti-ness in the template.  Each field will match
    // exactly one type.
    inputType(field: any): string {

        if (field.template) {
            return 'template';
        }

        if ( field.datatype === 'timestamp' && field.datetime ) {
            return 'timestamp-timepicker';
        }

        // Some widgets handle readOnly for us.
        if (   field.datatype === 'timestamp'
            || field.datatype === 'org_unit'
            || field.datatype === 'bool') {
            return field.datatype;
        }

        if (field.readOnly) {
            if (field.datatype === 'money') {
                return 'readonly-money';
            }

            if (field.datatype === 'link' && field.class === 'au') {
                return 'readonly-au';
            }

            if (field.datatype === 'link' || field.linkedValues) {
                return 'readonly-list';
            }

            return 'readonly';
        }

        if (field.datatype === 'id' && !this.pkeyIsEditable) {
            return 'readonly';
        }

        if (   field.datatype === 'int'
            || field.datatype === 'float'
            || field.datatype === 'money') {
            return field.datatype;
        }

        if (field.datatype === 'link' || field.linkedValues) {
            return 'list';
        }

        // datatype == text / interval / editable-pkey
        return 'text';
    }

    openTranslator(field: string) {
        this.translator.fieldName = field;
        this.translator.idlObject = this.record;

        this.translator.open().subscribe(
            newValue => {
                if (newValue) {
                    this.record[field](newValue);
                }
            }
        );
    }
}

