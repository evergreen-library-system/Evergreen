import {Component, Input, OnInit} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';

/**
 * MARC Record flat text (marc-breaker) editor.
 */

@Component({
  selector: 'eg-marc-flat-editor',
  templateUrl: './flat-editor.component.html',
  styleUrls: ['flat-editor.component.css']
})

export class MarcFlatEditorComponent implements OnInit {

    @Input() context: MarcEditContext;
    get record(): MarcRecord {
        return this.context.record;
    }

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private store: ServerStoreService
    ) {}

    ngOnInit() {
        // Be sure changes made in the enriched editor are
        // reflected here.
        this.record.breakerText = this.record.toBreaker();
    }

    // When we have breaker text, limit the vertical expansion of the
    // text area to the size of the data plus a little padding.
    rowCount(): number {
        if (this.record && this.record.breakerText) {
            return this.record.breakerText.split(/\n/).length + 2;
        }
        return 40;
    }

    textChanged() {
        this.context.changesPending = true;
    }
}



