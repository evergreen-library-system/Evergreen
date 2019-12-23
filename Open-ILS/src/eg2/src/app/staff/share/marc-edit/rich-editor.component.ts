import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    ViewChild, OnDestroy} from '@angular/core';
import {filter} from 'rxjs/operators';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {TagTableService} from './tagtable.service';
import {MarcRecord, MarcField} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {AuthorityLinkingDialogComponent} from './authority-linking-dialog.component';
import {PhysCharDialogComponent} from './phys-char-dialog.component';


/**
 * MARC Record rich editor interface.
 */

@Component({
  selector: 'eg-marc-rich-editor',
  templateUrl: './rich-editor.component.html',
  styleUrls: ['rich-editor.component.css']
})

export class MarcRichEditorComponent implements OnInit {

    @Input() context: MarcEditContext;
    get record(): MarcRecord { return this.context.record; }

    dataLoaded: boolean;
    showHelp: boolean;
    randId = Math.floor(Math.random() * 100000);
    stackSubfields: boolean;
    controlledBibTags: string[] = [];

    @ViewChild('authLinker', {static: false})
        authLinker: AuthorityLinkingDialogComponent;

    @ViewChild('physCharDialog', {static: false})
        physCharDialog: PhysCharDialogComponent;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private store: ServerStoreService,
        private tagTable: TagTableService
    ) {}

    ngOnInit() {

        this.store.getItem('cat.marcedit.stack_subfields')
        .then(stack => this.stackSubfields = stack);

        this.init().then(_ =>
            this.context.recordChange.subscribe(__ => this.init()));

        // Changing the Type fixed field means loading new meta-metadata.
        this.record.fixedFieldChange.pipe(filter(code => code === 'Type'))
        .subscribe(_ => this.init());
    }

    init(): Promise<any> {
        this.dataLoaded = false;

        if (!this.record) { return Promise.resolve(); }

        return Promise.all([
            this.tagTable.loadTags({
                marcRecordType: this.context.recordType,
                ffType: this.record.recordType()
            }).then(table => this.context.tagTable = table),
            this.tagTable.getControlledBibTags().then(
                tags => this.controlledBibTags = tags),
            this.fetchSettings()
        ]).then(_ =>
            // setTimeout forces all of our sub-components to rerender
            // themselves each time init() is called.  Without this,
            // changing the record Type would only re-render the fixed
            // fields editor when data had to be fetched from the
            // network.  (Sometimes the data is cached).
            setTimeout(() => this.dataLoaded = true)
        );
    }

    fetchSettings(): Promise<any> {
        // Fetch at rich editor load time to cache.
        return this.org.settings(['cat.marc_control_number_identifier']);
    }

    stackSubfieldsChange() {
        if (this.stackSubfields) {
            this.store.setItem('cat.marcedit.stack_subfields', true);
        } else {
            this.store.removeItem('cat.marcedit.stack_subfields');
        }
    }

    undoCount(): number {
        return this.context.undoCount();
    }

    redoCount(): number {
        return this.context.redoCount();
    }

    undo() {
        this.context.requestUndo();
    }

    redo() {
        this.context.requestRedo();
    }

    controlFields(): MarcField[] {
        return this.record.fields.filter(f => f.isCtrlField);
    }

    dataFields(): MarcField[] {
        return this.record.fields.filter(f => !f.isCtrlField);
    }

    validate() {
        const fields = [];

        this.record.fields.filter(f => this.isControlledBibTag(f.tag))
        .forEach(f => {
            f.authValid = false;
            fields.push({
                id: f.fieldId, // ignored and echoed by server
                tag: f.tag,
                ind1: f.ind1,
                ind2: f.ind2,
                subfields: f.subfields.map(sf => [sf[0], sf[1]])
            });
        });

        this.net.request('open-ils.cat',
            'open-ils.cat.authority.validate.bib_field', fields)
        .subscribe(checkedField => {
            const bibField = this.record.fields
                .filter(f => f.fieldId === +checkedField.id)[0];

            bibField.authChecked = true;
            bibField.authValid = checkedField.valid;
        });
    }

    isControlledBibTag(tag: string): boolean {
        return this.controlledBibTags && this.controlledBibTags.includes(tag);
    }

    openLinkerDialog(field: MarcField) {
        this.authLinker.bibField = field;
        this.authLinker.open({size: 'xl'}).subscribe(newField => {

            // The presence of newField here means the linker wants to
            // replace the field with a new field from the authority
            // record.  Otherwise, the original field may have been
            // directly modified or the dialog canceled.
            if (!newField) { return; }

            // Performs an insert followed by a delete, so the two
            // fields can be tracked separately for undo/redo actions.
            const marcField = this.record.newField(newField);
            this.context.insertField(field, marcField);
            this.context.deleteField(field);

            // Mark the insert and delete as an atomic undo/redo action.
            this.context.setUndoGroupSize(2);
        });
    }

    // 007 Physical characteristics wizard.
    openPhysCharDialog(field: MarcField) {
        this.physCharDialog.fieldData = field.data;

        this.physCharDialog.open({size: 'lg'}).subscribe(
            newData => {
                if (newData) {
                    this.context.requestFieldFocus({
                        fieldId: field.fieldId,
                        target: 'cfld',
                        newText: newData
                    });
                }
            }
        );
    }
}



