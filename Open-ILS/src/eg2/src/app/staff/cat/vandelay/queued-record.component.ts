import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';

@Component({
  templateUrl: 'queued-record.component.html'
})
export class QueuedRecordComponent {

    queueId: number;
    queueType: string;
    recordId: number;
    recordTab: string;

    constructor(
        private router: Router,
        private route: ActivatedRoute) {

        this.route.paramMap.subscribe((params: ParamMap) => {
            this.queueId = +params.get('id');
            this.recordId = +params.get('recordId');
            this.queueType = params.get('qtype');
            this.recordTab = params.get('recordTab');
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
}

