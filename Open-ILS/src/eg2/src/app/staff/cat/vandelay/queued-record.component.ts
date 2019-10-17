import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
  templateUrl: 'queued-record.component.html'
})
export class QueuedRecordComponent {

    queueId: number;
    queueType: string;
    recordId: number;
    recordTab: string;
    queuedRecord: IdlObject;

    @ViewChild('updateSuccess') updateSuccess: StringComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private toast: ToastService,
        private pcrud: PcrudService) {

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
    onTabChange(evt: NgbTabChangeEvent) {
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
        this.pcrud.retrieve('vqbr', this.recordId)
        .subscribe(rec => this.queuedRecord = rec);
    }

    handleMarcRecordSaved(saveEvent: any) {
        this.queuedRecord.marc(saveEvent.marcXml);
        this.queuedRecord.bib_source(saveEvent.bibSource);
        this.pcrud.update(this.queuedRecord).subscribe(
            response => this.toast.success(this.updateSuccess.text),
            error => {
                console.error(error);
                this.toast.danger(error);
            }
        );
    }
}

