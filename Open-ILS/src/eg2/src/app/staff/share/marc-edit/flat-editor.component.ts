import { Component, Input, OnInit, inject } from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {MarcRecord} from './marcrecord';
import {MarcEditContext} from './editor-context';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

/**
 * MARC Record flat text (marc-breaker) editor.
 */

@Component({
    selector: 'eg-marc-flat-editor',
    templateUrl: './flat-editor.component.html',
    styleUrls: ['flat-editor.component.css'],
    imports: [CommonModule, FormsModule]
})

export class MarcFlatEditorComponent implements OnInit {
    private idl = inject(IdlService);
    private org = inject(OrgService);
    private store = inject(ServerStoreService);


    @Input() context: MarcEditContext;
    get record(): MarcRecord {
        return this.context.record;
    }

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
        // eslint-disable-next-line no-magic-numbers
        return 40;
    }

    textChanged() {
        this.context.changesPending = true;
    }
}



