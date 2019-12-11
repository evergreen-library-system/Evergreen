import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy} from '@angular/core';
import {filter} from 'rxjs/operators';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {TagTableService} from './tagtable.service';
import {MarcRecord, MarcField} from './marcrecord';
import {MarcEditContext} from './editor-context';


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

    constructor(
        private idl: IdlService,
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
            this.tagTable.loadTagTable({marcRecordType: this.context.recordType}),
            this.tagTable.getFfPosTable(this.record.recordType()),
            this.tagTable.getFfValueTable(this.record.recordType())
        ]).then(_ =>
            // setTimeout forces all of our sub-components to rerender
            // themselves each time init() is called.  Without this,
            // changing the record Type would only re-render the fixed
            // fields editor when data had to be fetched from the
            // network.  (Sometimes the data is cached).
            setTimeout(() => this.dataLoaded = true)
        );
    }

    stackSubfieldsChange() {
        if (this.stackSubfields) {
            this.store.setItem('cat.marcedit.stack_subfields', true);
        } else {
            this.store.removeItem('cat.marcedit.stack_subfields');
        }
    }

    undoCount(): number {
        return this.context.undoStack.length;
    }

    redoCount(): number {
        return this.context.redoStack.length;
    }

    undo() {
        this.context.requestUndo();
    }

    redo() {
        this.context.requestRedo();
    }

    controlFields(): MarcField[] {
        return this.record.fields.filter(f => f.isControlfield());
    }

    dataFields(): MarcField[] {
        return this.record.fields.filter(f => !f.isControlfield());
    }
}



