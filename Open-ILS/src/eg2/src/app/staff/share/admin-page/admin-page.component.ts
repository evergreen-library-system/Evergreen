import {Component, Input, OnInit, TemplateRef, ViewChild} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {Location} from '@angular/common';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {FormatService} from '@eg/core/format.service';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {TranslateComponent} from '@eg/share/translate/translate.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {FmRecordEditorComponent, FmFieldOptions
    } from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';

/**
 * General purpose CRUD interface for IDL objects
 *
 * Object types using this component must be editable via PCRUD.
 */

@Component({
    selector: 'eg-admin-page',
    templateUrl: './admin-page.component.html'
})

export class AdminPageComponent implements OnInit {

    @Input() idlClass: string;

    // Default sort field, used when no grid sorting is applied.
    @Input() sortField: string;

    // Data source may be provided by the caller.  This gives the caller
    // complete control over the contents of the grid.  If no data source
    // is provided, a generic one is create which is sufficient for data
    // that requires no special handling, filtering, etc.
    @Input() dataSource: GridDataSource;

    // Size of create/edito dialog.  Uses large by default.
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    // comma-separated list of fields to hide.
    // This does not imply all other fields should be visible, only that
    // the selected fields will be hidden.
    @Input() hideGridFields: string;

    // If an org unit field is specified, an org unit filter
    // is added to the top of the page.
    @Input() orgField: string;

    // Disable the auto-matic org unit field filter
    @Input() disableOrgFilter: boolean;

    // Include objects linking to org units which are ancestors
    // of the selected org unit.
    @Input() includeOrgAncestors: boolean;

    // Ditto includeOrgAncestors, but descendants.
    @Input() includeOrgDescendants: boolean;

    // Optional grid persist key.  This is the part of the key
    // following eg.grid.
    @Input() persistKey: string;

    // Optional path component to add to the generated grid persist key,
    // formatted as (for example):
    // 'eg.grid.admin.${persistKeyPfx}.config.billing_type'
    @Input() persistKeyPfx: string;

    // Optional comma-separated list of read-only fields
    @Input() readonlyFields: string;

    // Optional template containing help/about text which will
    // be added to the page, above the grid.
    @Input() helpTemplate: TemplateRef<any>;

    // Override field options for create/edit dialog
    @Input() fieldOptions: {[field: string]: FmFieldOptions};

    // Override default values for fm-editor
    @Input() defaultNewRecord: IdlObject;

    // Used as the first part of the routerLink path when creating
    // links to related tables via configField's.
    @Input() configLinkBasePath: string;

    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: true }) createString: StringComponent;
    @ViewChild('createErrString', { static: true }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: true }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('translator', { static: true }) translator: TranslateComponent;

    idlClassDef: any;
    pkeyField: string;
    configFields: any[]; // IDL field definitions

    // True if any columns on the object support translations
    translateRowIdx: number;
    translateFieldIdx: number;
    translatableFields: string[];

    contextOrg: IdlObject;
    searchOrgs: OrgFamily;
    orgFieldLabel: string;
    viewPerms: string;
    canCreate: boolean;

    // Filters may be passed via URL query param.
    // They are used to augment the grid data search query.
    gridFilters: {[key: string]: string | number};

    constructor(
        private route: ActivatedRoute,
        private ngLocation: Location,
        private format: FormatService,
        public idl: IdlService,
        private org: OrgService,
        public auth: AuthService,
        public pcrud: PcrudService,
        private perm: PermService,
        public toast: ToastService
    ) {
        this.translatableFields = [];
        this.configFields = [];
    }

    applyOrgValues(orgId?: number) {

        if (this.disableOrgFilter) {
            this.orgField = null;
            return;
        }

        if (!this.orgField) {
            // If no org unit field is specified, try to find one.
            // If an object type has multiple org unit fields, the
            // caller should specify one or disable org unit filter.
            this.idlClassDef.fields.forEach(field => {
                if (field['class'] === 'aou') {
                    this.orgField = field.name;
                }
            });
        }

        if (this.orgField) {
            this.orgFieldLabel = this.idlClassDef.field_map[this.orgField].label;
            this.contextOrg = this.org.get(orgId) || this.org.get(this.auth.user().ws_ou()) || this.org.root();
            this.searchOrgs = {primaryOrgId: this.contextOrg.id()};
        }
    }

    ngOnInit() {

        this.idlClassDef = this.idl.classes[this.idlClass];
        this.pkeyField = this.idlClassDef.pkey || 'id';

        this.translatableFields =
            this.idlClassDef.fields.filter(f => f.i18n).map(f => f.name);

        if (!this.persistKey) {
            this.persistKey =
                'admin.' +
                (this.persistKeyPfx ? this.persistKeyPfx + '.' : '') +
                this.idlClassDef.table;
        }


        // Note the field filter could be based purely on fields
        // which are links, but that leads to cases where links
        // are created to tables which are too big and/or admin
        // interfaces which are not otherwise used because they
        // have custom UI's instead.
        // this.idlClassDef.fields.filter(f => f.datatype === 'link');
        this.configFields =
            this.idlClassDef.fields.filter(f => f.config_field);

        // gridFilters are a JSON encoded string
        const filters = this.route.snapshot.queryParamMap.get('gridFilters');
        if (filters) {
            try {
                this.gridFilters = JSON.parse(filters);
            } catch (E) {
                console.error('Invalid grid filters provided: ', filters);
            }

            // Use the grid filters as the basis for our default
            // new record (passed to fm-editor).
            if (!this.defaultNewRecord) {
                const rec = this.idl.create(this.idlClass);
                Object.keys(this.gridFilters).forEach(field => {
                    // When filtering on the primary key of the current
                    // object type, avoid using it in the default new object.
                    if (rec[field] && this.pkeyField !== field) {
                        rec[field](this.gridFilters[field]);
                    }
                });
                this.defaultNewRecord = rec;
            }
        }

        // Limit the view org selector to orgs where the user has
        // permacrud-encoded view permissions.
        const pc = this.idlClassDef.permacrud;
        if (pc && pc.retrieve) {
            this.viewPerms = pc.retrieve.perms;
        }

        const contextOrg = this.route.snapshot.queryParamMap.get('contextOrg');
        this.checkCreatePerms();
        this.applyOrgValues(Number(contextOrg));

        // If the caller provides not data source, create a generic one.
        if (!this.dataSource) {
            this.initDataSource();
        }

        // TODO: pass the row activate handler via the grid markup
        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => this.showEditDialog(idlThing)
        );
    }

    checkCreatePerms() {
        this.canCreate = false;
        const pc = this.idlClassDef.permacrud || {};
        const perms = pc.create ? pc.create.perms : [];
        if (perms.length === 0) { return; }

        this.perm.hasWorkPermAt(perms, true).then(permMap => {
            Object.keys(permMap).forEach(key => {
                if (permMap[key].length > 0) {
                    this.canCreate = true;
                }
            });
        });
    }

    initDataSource() {
        this.dataSource = new GridDataSource();

        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};

            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;

            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            if (!this.contextOrg && !this.gridFilters) {
                // No org filter -- fetch all rows
                return this.pcrud.retrieveAll(
                    this.idlClass, searchOps, {fleshSelectors: true});
            }

            const search: any = {};

            if (this.orgField) {
                search[this.orgField] =
                    this.searchOrgs.orgIds || [this.contextOrg.id()];
            }

            if (this.gridFilters) {
                // Lay the URL grid filters over our search object.
                Object.keys(this.gridFilters).forEach(key => {
                    search[key] = this.gridFilters[key];
                });
            }

            return this.pcrud.search(
                this.idlClass, search, searchOps, {fleshSelectors: true});
        };
    }

    showEditDialog(idlThing: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = idlThing[this.pkeyField]();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialogSize}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    editSelected(idlThings: IdlObject[]) {

        // Edit each IDL thing one at a time
        const editOneThing = (thing: IdlObject) => {
            if (!thing) { return; }

            this.showEditDialog(thing).then(
                () => editOneThing(idlThings.shift()));
        };

        editOneThing(idlThings.shift());
    }

    deleteSelected(idlThings: IdlObject[]) {
        idlThings.forEach(idlThing => idlThing.isdeleted(true));
        this.pcrud.autoApply(idlThings).subscribe(
            val => {
                console.debug('deleted: ' + val);
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
            },
            err => {
                this.deleteFailedString.current()
                    .then(str => this.toast.danger(str));
            },
            ()  => this.grid.reload()
        );
    }

    createNew() {
        this.editDialog.mode = 'create';
        // We reuse the same editor for all actions.  Be sure
        // create action does not try to modify an existing record.
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialogSize}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    }
    // Open the field translation dialog.
    // Link the next/previous actions to cycle through each translatable
    // field on each row.
    translate() {
        this.translateRowIdx = 0;
        this.translateFieldIdx = 0;
        this.translator.fieldName = this.translatableFields[this.translateFieldIdx];
        this.translator.idlObject = this.dataSource.data[this.translateRowIdx];

        this.translator.nextString = () => {

            if (this.translateFieldIdx < this.translatableFields.length - 1) {
                this.translateFieldIdx++;

            } else if (this.translateRowIdx < this.dataSource.data.length - 1) {
                this.translateRowIdx++;
                this.translateFieldIdx = 0;
            }

            this.translator.idlObject =
                this.dataSource.data[this.translateRowIdx];
            this.translator.fieldName =
                this.translatableFields[this.translateFieldIdx];
        };

        this.translator.prevString = () => {

            if (this.translateFieldIdx > 0) {
                this.translateFieldIdx--;

            } else if (this.translateRowIdx > 0) {
                this.translateRowIdx--;
                this.translateFieldIdx = 0;
            }

            this.translator.idlObject =
                this.dataSource.data[this.translateRowIdx];
            this.translator.fieldName =
                this.translatableFields[this.translateFieldIdx];
        };

        this.translator.open({size: 'lg'});
    }

    // Construct a routerLink path for a configField.
    configFieldRouteLink(row: any, col: GridColumn): string {
        const cf = this.configFields.filter(field => field.name === col.name)[0];
        const linkClass = this.idl.classes[cf['class']];
        const pathParts = linkClass.table.split(/\./); // schema.tablename
        return `${this.configLinkBasePath}/${pathParts[0]}/${pathParts[1]}`;
    }

    // Compiles a gridFilter value used when navigating to a linked
    // class via configField.  The filter ensures the linked page
    // only shows rows which refer back to the object from which the
    // link was clicked.
    configFieldRouteParams(row: any, col: GridColumn): any {
        const cf = this.configFields.filter(field => field.name === col.name)[0];
        let value = this.configFieldLinkedValue(row, col);

        // For certain has-a relationships, the linked object will be
        // fleshed so its display (selector) value can be used.
        // Extract the scalar value found at the remote target field.
        if (value && typeof value === 'object') { value = value[cf.key](); }

        const filter: any = {};
        filter[cf.key] = value;

        return {gridFilters : JSON.stringify(filter)};
    }

    // Returns the value on the local object for the field which
    // refers to the remote object.  This may be a scalar or a
    // fleshed IDL object.
    configFieldLinkedValue(row: any, col: GridColumn): any {
        const cf = this.configFields.filter(field => field.name === col.name)[0];
        const linkClass = this.idl.classes[cf['class']];

        // cf.key is the name of the field on the linked object that matches
        // the value on our local object.
        // In as has_many relationship, the remote field has its own
        // 'key' value which determines which field on the local object
        // represents the other end of the relationship.  This is
        // typically, but not always the local pkey field.

        const localField =
            cf.reltype === 'has_many' ?
            (linkClass.field_map[cf.key].key || this.pkeyField) : cf.name;

        return row[localField]();
    }

    // Returns a URL suitable for using as an href.
    // We use an href to jump to the secondary admin page because
    // routerLink within the same base component results in component
    // reuse of a series of components which were not designed with
    // reuse in mind.
    configFieldLinkUrl(row: any, col: GridColumn): string {
        const path = this.configFieldRouteLink(row, col);
        const filters = this.configFieldRouteParams(row, col);
        const url = path + '?gridFilters=' +
            encodeURIComponent(filters.gridFilters);

        return this.ngLocation.prepareExternalUrl(url);
    }

    configLinkLabel(row: any, col: GridColumn): string {
        const cf = this.configFields.filter(field => field.name === col.name)[0];

        // Has-many links have no specific value to use for display
        // so just use the column label.
        if (cf.reltype === 'has_many') { return col.label; }

        return this.format.transform({
            value: row[col.name](),
            idlClass: this.idlClass,
            idlField: col.name
        });
    }

    clearGridFiltersUrl(): string {
        const parts = this.idlClassDef.table.split(/\./);
        const url = this.configLinkBasePath + '/' + parts[0] + '/' + parts[1];
        return this.ngLocation.prepareExternalUrl(url);
    }
}


