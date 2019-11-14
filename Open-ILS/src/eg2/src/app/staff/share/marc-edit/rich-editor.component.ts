import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
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
        private tagTable: TagTableService
    ) {}

    ngOnInit() {
        this.init().then(_ =>
            this.context.recordChange.subscribe(__ => this.init()));
    }

    init(): Promise<any> {
        this.dataLoaded = false;

        if (!this.record) { return Promise.resolve(); }

        return Promise.all([
            this.tagTable.loadTagTable({marcRecordType: this.context.recordType}),
            this.tagTable.getFfPosTable(this.record.recordType()),
            this.tagTable.getFfValueTable(this.record.recordType())
        ]).then(_ => this.dataLoaded = true);
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



