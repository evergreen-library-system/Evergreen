import { Component, inject } from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { FastAddSelectorComponent } from '@eg/staff/share/marc-edit/fast-add-selector.component';
import { MarcEditorComponent } from '@eg/staff/share/marc-edit/editor.component';
import { MarcHtmlComponent } from '@eg/share/catalog/marc-html.component';
import { QueuedRecordMatchesComponent } from './queued-record-matches.component';
import { RecordItemsComponent } from './record-items.component';

@Component({
    templateUrl: 'queued-record.component.html',
    imports: [
        MarcEditorComponent,
        MarcHtmlComponent,
        StaffCommonModule,
        FastAddSelectorComponent,
        QueuedRecordMatchesComponent,
        RecordItemsComponent
    ]
})
export class QueuedRecordComponent {
    private router = inject(Router);
    private route = inject(ActivatedRoute);
    private pcrud = inject(PcrudService);


    queueId: number;
    queueType: string;
    recordId: number;
    recordTab: string;
    queuedRecord: IdlObject;

    constructor() {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.queueId = +params.get('id');
            this.recordId = +params.get('recordId');
            this.queueType = params.get('qtype');
            this.recordTab = params.get('recordTab');
            if (this.recordTab === 'edit') {
                this.loadRecord();
            }
        });
    }

    // Changing a tab in the UI means changing the route.
    // Changing the route ultimately results in changing the tab.
    onNavChange(evt: NgbNavChangeEvent) {
        this.recordTab = evt.nextId;

        // prevent tab changing until after route navigation
        evt.preventDefault();

        const url =
          `/staff/cat/vandelay/queue/${this.queueType}/${this.queueId}` +
          `/record/${this.recordId}/${this.recordTab}`;

        this.router.navigate([url]);
    }

    loadRecord() {
        this.queuedRecord = null;
        this.pcrud.retrieve((this.queueType === 'bib' ? 'vqbr' : 'vqar'), this.recordId)
            .subscribe(rec => this.queuedRecord = rec);
    }

    handleMarcRecordSaved(saveEvent: any) {
        this.queuedRecord.marc(saveEvent.marcXml);
        if (this.queueType === 'bib') {
            this.queuedRecord.bib_source(saveEvent.bibSource);
        }
        this.pcrud.update(this.queuedRecord).subscribe(
            response => {
                console.log('response = ', response);
            }
        );
    }
}

