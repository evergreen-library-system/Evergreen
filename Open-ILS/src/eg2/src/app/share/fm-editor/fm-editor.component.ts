import {Component, OnInit, Input,
    Output, EventEmitter, TemplateRef} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

interface CustomFieldTemplate {
    template: TemplateRef<any>;

    // Allow the caller to pass in a free-form context blob to
    // be addedto the caller's custom template context, along
    // with our stock context.
    context?: {[fields: string]: any};
}

interface CustomFieldContext {
    // Current create/edit/view record
    record: IdlObject;

    // IDL field definition blob
    field: any;

    // additional context values passed via CustomFieldTemplate
    [fields: string]: any;
}

@Component({
  selector: 'eg-fm-record-editor',
  templateUrl: './fm-editor.component.html'
})
export class FmRecordEditorComponent
    extends DialogComponent implements OnInit {

    // IDL class hint (e.g. "aou")
    @Input() idlClass: string;

    // mode: 'create' for creating a new record,
    //       'update' for editing an existing record
    //       'view' for viewing an existing record without editing
    mode: 'create' | 'update' | 'view' = 'create';
    recId: any;
    // IDL record we are editing
    // TODO: allow this to be update in real time by the caller?
    record: IdlObject;

    // Permissions extracted from the permacrud defs in the IDL
    // for the current IDL class
    modePerms: {[mode: string]: string};

    @Input() customFieldTemplates:
        {[fieldName: string]: CustomFieldTemplate} = {};

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

    // list of org_unit fields where a default value may be applied by
    // the org-select if no value is present.
    @Input() orgDefaultAllowedList: string[] = [];
    @Input() orgDefaultAllowed: string; // comma-separated string version

    // hash, keyed by field name, of functions to invoke to check
    // whether a field is required.  Each callback is passed the field
    // name and the record and should return a boolean value. This
    // supports cases where whether a field is required or not depends
    // on the current value of another field.
    @Input() isRequiredOverride:
        {[field: string]: (field: string, record: IdlObject) => boolean};

    // IDL record display label.  Defaults to the IDL label.
    @Input() recordLabel: string;

    // Emit the modified object when the save action completes.
    @Output() onSave$ = new EventEmitter<IdlObject>();

    // Emit the original object when the save action is canceled.
    @Output() onCancel$ = new EventEmitter<IdlObject>();

    // Emit an error message when the save action fails.
    @Output() onError$ = new EventEmitter<string>();

    // IDL info for the the selected IDL class
    idlDef: any;

    // Can we edit the primary key?
    pkeyIsEditable = false;

    // List of IDL field definitions.  This is a subset of the full
    // list of fields on the IDL, since some are hidden, virtual, etc.
    fields: any[];

    @Input() editMode(mode: 'create' | 'update' | 'view') {
        this.mode = mode;
    }

    // Record ID to view/update.  Value is dynamic.  Records are not
    // fetched until .open() is called.
    @Input() set recordId(id: any) {
        if (id) { this.recId = id; }
    }

    idPrefix: string;

    constructor(
      private modal: NgbModal, // required for passing to parent
      private idl: IdlService,
      private auth: AuthService,
      private pcrud: PcrudService) {
      super(modal);
    }

    // Avoid fetching data on init since that may lead to unnecessary
    // data retrieval.
    ngOnInit() {
        this.listifyInputs();
        this.idlDef = this.idl.classes[this.idlClass];
        this.recordLabel = this.idlDef.label;

	// Add some randomness to the generated DOM IDs to ensure against clobbering
	this.idPrefix = 'fm-editor-' + Math.floor(Math.random() * 100000);
    }

    // Opening dialog, fetch data.
    open(options?: NgbModalOptions): Promise<any> {
        return this.initRecord().then(
            ok => super.open(options),
            err => console.warn(`Error fetching FM data: ${err}`)
        );
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

        if (this.mode === 'update' || this.mode === 'view') {
            return this.pcrud.retrieve(this.idlClass, this.recId)
            .toPromise().then(rec => {

                if (!rec) {
                    return Promise.reject(`No '${this.idlClass}'
                        record found with id ${this.recId}`);
                }

                this.record = rec;
                this.convertDatatypesToJs();
                return this.getFieldList();
            });
        }

        // create a new record from scratch
        this.pkeyIsEditable = !('pkey_sequence' in this.idlDef);
        this.record = this.idl.create(this.idlClass);
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
        const fields = this.idlDef.fields;
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


    private flattenLinkedValues(cls: string, list: IdlObject[]): any[] {
        const idField = this.idl.classes[cls].pkey;
        const selector =
            this.idl.classes[cls].field_map[idField].selector || idField;

        return list.map(item => {
            return {id: item[idField](), name: item[selector]()};
        });
    }

    private getFieldList(): Promise<any> {

        this.fields = this.idlDef.fields.filter(f =>
            !f.virtual && !this.hiddenFieldsList.includes(f.name)
        );

        const promises = [];

        this.fields.forEach(field => {
            field.readOnly = this.mode === 'view'
                || this.readonlyFieldsList.includes(field.name);

            if (this.isRequiredOverride &&
                field.name in this.isRequiredOverride) {
                field.isRequired = () => {
                    return this.isRequiredOverride[field.name](field.name, this.record);
                };
            } else {
                field.isRequired = () => {
                    return field.required ||
                        this.requiredFieldsList.includes(field.name);
                };
            }

            if (field.datatype === 'link' && field.readOnly) { // no need to fetch all possible values for read-only fields
                let id_to_fetch = this.record[field.name]();
                if (id_to_fetch) {
                    promises.push(
                        this.pcrud.retrieve(field.class, this.record[field.name]())
                        .toPromise().then(list => {
                            field.linkedValues =
                                this.flattenLinkedValues(field.class, Array(list));
                        })
                    );
                }
            } else if (field.datatype === 'link') {
                promises.push(
                    this.pcrud.retrieveAll(field.class, {}, {atomic : true})
                    .toPromise().then(list => {
                        field.linkedValues =
                            this.flattenLinkedValues(field.class, list);
                    })
                );
            } else if (field.datatype === 'org_unit') {
                field.orgDefaultAllowed =
                    this.orgDefaultAllowedList.includes(field.name);
            }

            if (this.customFieldTemplates[field.name]) {
                field.template = this.customFieldTemplates[field.name].template;
                field.context = this.customFieldTemplates[field.name].context;
            }

        });

        // Wait for all network calls to complete
        return Promise.all(promises);
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
        this.convertDatatypesToIdl(recToSave);
        this.pcrud[this.mode]([recToSave]).toPromise().then(
            result => this.close(result),
            error  => this.dismiss(error)
        );
    }

    cancel() {
        this.dismiss('canceled');
    }
}


