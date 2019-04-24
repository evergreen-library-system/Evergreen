import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';

/** Hold details read-only view */

@Component({
  selector: 'eg-hold-detail',
  templateUrl: 'detail.component.html'
})
export class HoldDetailComponent implements OnInit {

    _holdId: number;
    @Input() set holdId(id: number) {
        this._holdId = id;
        if (this.initDone) {
            this.fetchHold();
        }
    }

    hold: any; // wide hold reference
    @Input() set wideHold(wh: any) {
        this.hold = wh;
    }

    initDone: boolean;
    @Output() onShowList: EventEmitter<any>;

    constructor(
        private net: NetService,
        private org: OrgService,
        private auth: AuthService,
    ) {
        this.onShowList = new EventEmitter<any>();
    }

    ngOnInit() {
        this.initDone = true;
        this.fetchHold();
    }

    fetchHold() {
        if (!this._holdId) { return; }

        this.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.wide_hash.stream',
            this.auth.token(), {id: this._holdId}
        ).subscribe(wideHold => {
            this.hold = wideHold;
        });
    }

    getOrgName(id: number) {
        if (id) {
            return this.org.get(id).shortname();
        }
    }

    showListView() {
        this.onShowList.emit();
    }
}


