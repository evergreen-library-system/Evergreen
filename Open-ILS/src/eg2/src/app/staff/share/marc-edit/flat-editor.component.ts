import {Component, Input, OnInit, Host} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {MarcEditorComponent} from './editor.component';
import {MarcRecord} from './marcrecord';

/**
 * MARC Record flat text (marc-breaker) editor.
 */

@Component({
  selector: 'eg-marc-flat-editor',
  templateUrl: './flat-editor.component.html',
  styleUrls: ['flat-editor.component.css']
})

export class MarcFlatEditorComponent implements OnInit {

    get record(): MarcRecord {
        return this.editor.record;
    }

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private store: ServerStoreService,
        @Host() private editor: MarcEditorComponent
    ) {
    }

    ngOnInit() {}

    // When we have breaker text, limit the vertical expansion of the
    // text area to the size of the data plus a little padding.
    rowCount(): number {
        if (this.record && this.record.breakerText) {
            return this.record.breakerText.split(/\n/).length + 2;
        }
        return 40;
    }
}



