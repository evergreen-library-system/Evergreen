import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {tap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {HoldNoteDialogComponent} from './note-dialog.component';
import {HoldNotifyDialogComponent} from './notify-dialog.component';

/** Hold details read-only view */

@Component({
    selector: 'eg-hold-detail',
    templateUrl: 'detail.component.html'
})
export class HoldDetailComponent implements OnInit {
    detailTab = 'notes';
    notes: IdlObject[] = [];
    notifies: IdlObject[] = [];

    private _holdId: number;
    @Input() set holdId(id: number) {
        if (this._holdId !== id) {
            this._holdId = id;
            if (this.initDone) {
                this.fetchHold();
            }
        }
    }

    get holdId(): number {
        return this._holdId;
    }

    hold: any; // wide hold reference
    @Input() set wideHold(wh: any) {
        this.hold = wh;
    }

    get wideHold(): any {
        return this.hold;
    }

    // Display bib record summary along the top of the detail page.
    @Input() showRecordSummary = false;

    initDone: boolean;
    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onShowList: EventEmitter<any>;

    @ViewChild('noteDialog') noteDialog: HoldNoteDialogComponent;
    @ViewChild('notifyDialog') notifyDialog: HoldNotifyDialogComponent;

    constructor(
        private net: NetService,
        private pcrud: PcrudService,
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
        if (!this.holdId && !this.hold) { return; }

        const promise = this.hold ? Promise.resolve(this.hold) :
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.hold.wide_hash.stream',
                this.auth.token(), {id: this.holdId}
            ).toPromise();

        return promise.then(wideHold => {
            this.hold = wideHold;
            // avoid this.holdId = since it re-fires this fetch.
            this._holdId = wideHold.id;
        })
            .then(_ => this.getNotes())
            .then(_ => this.getNotifies());
    }

    getNotes(): Promise<any> {
        this.notes = [];
        return this.pcrud.search('ahrn', {hold: this.holdId})
            .pipe(tap(note => this.notes.push(note))).toPromise();
    }

    getNotifies(): Promise<any> {
        this.notifies = [];

        return this.pcrud.search('ahn', {hold: this.holdId}, {
            flesh: 1,
            flesh_fields: {ahn: ['notify_staff']},
            order_by: {ahn: 'notify_time DESC'}
        }).pipe(tap(notify => this.notifies.push(notify))).toPromise();
    }

    getOrgName(id: number) {
        if (id) {
            return this.org.get(id).shortname();
        }
    }

    showListView() {
        this.onShowList.emit();
    }

    deleteNote(note: IdlObject) {
        this.pcrud.remove(note).toPromise()
            .then(ok => { if (ok) { this.getNotes(); } });
    }

    newNote() {
        this.noteDialog.open().subscribe(note => this.notes.unshift(note));
    }

    newNotify() {
        this.notifyDialog.open().subscribe(notify => this.getNotifies()); // fleshing
    }
}


