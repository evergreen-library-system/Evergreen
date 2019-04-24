import {Component, OnInit, ViewChild} from '@angular/core';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {VandelayService} from './vandelay.service';

@Component({
  templateUrl: 'queue-list.component.html'
})
export class QueueListComponent {

    queueType: string; // bib / auth / bib-acq
    queueSource: GridDataSource;
    deleteSelected: (rows: IdlObject[]) => void;

    // points to the currently active grid.
    queueGrid: GridComponent;

    @ViewChild('bibQueueGrid') bibQueueGrid: GridComponent;
    @ViewChild('authQueueGrid') authQueueGrid: GridComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private vandelay: VandelayService) {

        this.queueType = 'bib';
        this.queueSource = new GridDataSource();

        // Reset queue grid offset
        this.vandelay.queuePageOffset = 0;

        // queue API does not support sorting
        this.queueSource.getRows = (pager: Pager) => {
            return this.loadQueues(pager);
        };

        this.deleteSelected = (queues: IdlObject[]) => {

            // Serialize the deletes, especially if there are many of them
            // because they can be bulky calls
            const qtype = this.queueType;
            const method = `open-ils.vandelay.${qtype}_queue.delete`;
            const selected = queues.slice(0); // clone to be nice

            const deleteNext = (idx: number) => {
                const queue = selected[idx];
                if (!queue) {
                    this.currentGrid().reload();
                    return Promise.resolve();
                }

                return this.net.request('open-ils.vandelay',
                    method, this.auth.token(), queue.id()
                ).toPromise().then(() => deleteNext(++idx));
            };

            deleteNext(0);
        };
    }

    currentGrid(): GridComponent {
        // The active grid changes along with the queue type.
        // The inactive grid will be set to null.
        return this.bibQueueGrid || this.authQueueGrid;
    }

    rowActivated(queue) {
        const url = `/staff/cat/vandelay/queue/${this.queueType}/${queue.id()}`;
        this.router.navigate([url]);
    }

    queueTypeChanged($event) {
        this.queueType = $event.id;
        this.queueSource.reset();
    }


    loadQueues(pager: Pager): Observable<any> {

        if (!this.queueType) {
            return of();
        }

        const qtype = this.queueType.match(/bib/) ? 'bib' : 'authority';
        const method = `open-ils.vandelay.${qtype}_queue.owner.retrieve`;

        return this.net.request('open-ils.vandelay',
            method, this.auth.token(), null, null,
            {offset: pager.offset, limit: pager.limit}
        );
    }
}

