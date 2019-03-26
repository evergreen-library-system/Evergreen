import {Component, OnInit, OnDestroy, Input, ViewChild, Renderer2} from '@angular/core';
import {Subscription} from 'rxjs';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StoreService} from '@eg/core/store.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';


/**
 * Dialog for linking conjoined items.
 */

@Component({
  selector: 'eg-conjoined-items-dialog',
  templateUrl: 'conjoined-items-dialog.component.html'
})

export class ConjoinedItemsDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    @Input() copyIds: number[];
    ids: number[]; // copy of list so we can pop()

    peerType: number;
    numSucceeded: number;
    numFailed: number;
    peerTypes: ComboboxEntry[];
    peerRecord: number;
    existingMaps: any;

    onOpenSub: Subscription;

    @ViewChild('successMsg')
        private successMsg: StringComponent;

    @ViewChild('errorMsg')
        private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private localStore: StoreService) {
        super(modal); // required for subclassing
        this.peerTypes = [];
    }

    ngOnInit() {
        this.onOpenSub = this.onOpen$.subscribe(() => {
            this.ids = [].concat(this.copyIds);
            this.numSucceeded = 0;
            this.numFailed = 0;
            this.peerRecord =
                this.localStore.getLocalItem('eg.cat.marked_conjoined_record');

            if (!this.peerRecord) {
                this.close(false);
            }

            if (this.peerTypes.length === 0) {
                this.getPeerTypes();
            }

            this.fetchExisting();
        });
    }

    ngOnDestroy() {
        this.onOpenSub.unsubscribe();
    }

    fetchExisting() {
        this.existingMaps = {};
        this.pcrud.search('bpbcm',
            {target_copy: this.copyIds, peer_record: this.peerRecord})
        .subscribe(map => this.existingMaps[map.target_copy()] = map);
    }

    getPeerTypes(): Promise<any> {
        return this.pcrud.retrieveAll('bpt', {}, {atomic: true}).toPromise()
        .then(types =>
            // Map types to ComboboxEntry's
            this.peerTypes = types.map(t => ({id: t.id(), label: t.name()}))
        );
    }

    peerTypeChanged(entry: ComboboxEntry) {
        if (entry) {
            this.peerType = entry.id;
        } else {
            this.peerType = null;
        }
    }

    linkCopies(): Promise<any> {

        if (this.ids.length === 0) {
            this.close(this.numSucceeded > 0);
            return Promise.resolve();
        }

        const id = this.ids.pop();
        const map = this.existingMaps[id] || this.idl.create('bpbcm');
        map.peer_record(this.peerRecord);
        map.target_copy(id);
        map.peer_type(this.peerType);

        let promise: Promise<any>;
        if (this.existingMaps[id]) {
            promise = this.pcrud.update(map).toPromise();
        } else {
            promise = this.pcrud.create(map).toPromise();
        }

        return promise.then(
            ok => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.numSucceeded++;
                return this.linkCopies();
            },
            err => {
                this.numFailed++;
                console.error(err);
                this.errorMsg.current().then(msg => this.toast.warning(msg));
                return this.linkCopies();
            }
        );
    }
}



