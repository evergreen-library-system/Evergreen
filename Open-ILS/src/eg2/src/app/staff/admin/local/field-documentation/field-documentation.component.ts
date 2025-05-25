import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
    templateUrl: './field-documentation.component.html'
})

export class FieldDocumentationComponent implements OnInit {

    idlEntries: any[] = [];
    fieldOptions: any = {};
    owning_libs: any[] = [];
    @Input() selectedClass: any;
    @Input() fields: [] = [];
    gridDataSource: GridDataSource;
    @ViewChild('fieldClassSelector', {static: true}) fieldClassSelector: any;
    @ViewChild('fieldSelector', {static: true}) fieldSelector: any;
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('fieldDocGrid', { static: true }) fieldDocGrid: GridComponent;
    @ViewChild('updateSuccessString', { static: true }) updateSuccessString: StringComponent;
    @ViewChild('createSuccessString', { static: false }) createSuccessString: StringComponent;
    @ViewChild('createFailedString', { static: false }) createFailedString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    constructor(
    private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private toast: ToastService
    ) {}

    ngOnInit() {
        this.gridDataSource = new GridDataSource();
        Object.values(this.idl.classes).forEach(idlClass => {
            const fields = [];
            Object.values(idlClass['field_map']).forEach(field => {
                // We can safely ignore virtual fields...
                if (!field['virtual']) {
                    fields.push({
                        id: field['name'],
                        label: field['label'] ? field['label'] : field['name']
                    });
                }
            });
            if (idlClass['label']) {
                this.idlEntries.push({
                    label: idlClass['label'],
                    id: idlClass['name'],
                    fields: fields
                });
            }
        });
        this.idlEntries.sort((a, b) => {
            const textA = a.label.toUpperCase();
            const textB = b.label.toUpperCase();
            return (textA < textB) ? -1 : (textA > textB) ? 1 : 0;
        });
        if (this.selectedClass) { this.setGrid(); }
        this.fieldDocGrid.onRowActivate.subscribe((fieldDoc: IdlObject) => {
            this.showEditDialog(fieldDoc);
        });

        this.fieldOptions = {
            fm_class: {
                customTemplate: {
                    template: this.fieldClassSelector,
                    context: {
                        fieldentries: this.idlEntries,
                        selectedEntry: this.selectedClass
                    }
                }
            },
            field: {
                customTemplate: {
                    template: this.fieldSelector,
                    context: {
                        selectedEntry: null
                    }
                }
            }
        };
    }

    setClass(idlClass, entry?) {
        if (this.editDialog.record) { this.editDialog.record.fm_class(idlClass.id); }
        this.fieldOptions.fm_class.customTemplate.context.selectedEntry = idlClass;
        this.fields = idlClass.fields;

        if (entry && entry.field()) {
            this.setField(idlClass.fields.find(o => o.id === entry.field()));
        }
    }

    setField(entry) {
        if (this.editDialog.record) { this.editDialog.record.field(entry.id); }
        this.fieldOptions.field.customTemplate.context.selectedEntry = entry;
    }

    setGrid() {
        this.gridDataSource.data = [];
        this.setCurrentFieldDoc();
    }

    setCurrentFieldDoc() {
        if (this.selectedClass) {
            this.fields = this.selectedClass.fields;
            this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
                const orderBy: any = {};
                if (sort.length) {
                    // Sort specified from grid
                    orderBy['fdoc'] = sort[0].name + ' ' + sort[0].dir;
                }
                const search: any = new Array();
                const orgFilter: any = {};
                orgFilter['owner'] = this.owning_libs['orgIds'];
                if (orgFilter['owner'] && orgFilter['owner'][0]) {
                    search.push(orgFilter);
                }
                search.push({fm_class: this.selectedClass.id});

                const searchOps = {
                    offset: pager.offset,
                    limit: pager.limit,
                    order_by: orderBy
                };
                return this.pcrud.search('fdoc', search, searchOps, {fleshSelectors: true});
            };
            this.fieldDocGrid.reload();
        }
    }

    setFieldOptions(field) {
        field.owner(this.auth.user().ws_ou());
        this.fieldOptions.fm_class.customTemplate.context.selectedEntry = this.selectedClass;
        this.fieldOptions.field.customTemplate.context.fields = this.selectedClass ? this.selectedClass.fields : [];
        this.fieldOptions.field.customTemplate.context.record = field;
        if (this.selectedClass) {
            this.setClass(this.selectedClass, field);
        }
    }

    showEditDialog(field: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = field.id();
        this.setFieldOptions(field);
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe({ next: result => {
                this.updateSuccessString.current()
                    .then(str => this.toast.success(str));
                this.setGrid();
                resolve(result);
            }, error: (error: unknown) => {
                this.updateFailedString.current()
                    .then(str => this.toast.danger(str));
            } });
        });
    }

    editSelected(fields: IdlObject[]) {
        const editOneFieldDoc = (fieldDoc: IdlObject) => {
            if (!fieldDoc) { return; }

            this.showEditDialog(fieldDoc).then(
                () => editOneFieldDoc(fields.shift())
            );
        };

        editOneFieldDoc(fields.shift());
    }

    createNew() {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = this.idl.create('fdoc');
        this.setFieldOptions(this.editDialog.record);
        this.editDialog.open({size: 'lg'}).subscribe(
            { next: ok => {
                this.createSuccessString.current()
                    .then(str => this.toast.success(str));
                this.setGrid();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }
}
