import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {of, Observable} from 'rxjs';
import {tap, take, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {FormatService} from '@eg/core/format.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {EventService} from '@eg/core/event.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';


@Component({
  templateUrl: 'summary.component.html',
  selector: 'eg-acq-picklist-summary'
})
export class PicklistSummaryComponent implements OnInit, AfterViewInit {

    private _picklistId: number;
    @Input() set picklistId(id: number) {
        if (id !== this._picklistId) {
            this._picklistId = id;
            if (this.initDone) {
                this.load();
            }
        }
    }

    get picklistId(): number {
        return this._picklistId;
    }

    picklist: IdlObject;
    newPlName: string;
    editPlName = false;
    initDone = false;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private format: FormatService,
        private evt: EventService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: StoreService,
        private serverStore: ServerStoreService,
        private broadcaster: BroadcastService,
        private holdingSvc: HoldingsService
    ) {}

    ngOnInit() {
        this.load().then(_ => this.initDone = true);
    }

    ngAfterViewInit() {
    }

    load(): Promise<any> {
        this.picklist = null;
        if (!this.picklistId) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.picklist.retrieve.authoritative',
            this.auth.token(), this.picklistId,
            {flesh_lineitem_count: true, flesh_owner: true}
        ).toPromise().then(list => {

            const evt = this.evt.parse(list);
            if (evt) {
                console.error('API returned ', evt);
                return Promise.reject();
            }

            this.picklist = list;
        });
    }

    toggleNameEdit() {
        this.editPlName = !this.editPlName;

        if (this.editPlName) {
            this.newPlName = this.picklist.name();
            setTimeout(() => {
                const node =
                    document.getElementById('pl-name-input') as HTMLInputElement;
                if (node) { node.select(); }
            });

        } else if (this.newPlName && this.newPlName !== this.picklist.name()) {

            const prevName = this.picklist.name();
            this.picklist.name(this.newPlName);
            this.newPlName = null;

            this.net.request(
                'open-ils.acq',
                'open-ils.acq.picklist.update',
                this.auth.token(), this.picklist
            ).subscribe(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                    this.picklist.name(prevName);
                }
            });
        }
    }
}
