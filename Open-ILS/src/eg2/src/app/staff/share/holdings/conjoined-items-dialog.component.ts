import {Component, OnInit, OnDestroy, Input, ViewChild, Renderer2} from '@angular/core';
import {Subscription} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
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

    // If true, ignore the provided copyIds array and fetch all of
    // the linked copies to work on.
    @Input() modifyAll: boolean;

    // If peerRecord is not set, the localStorage value will be used.
    @Input() peerRecord: number;

    peerType: number;
    numSucceeded: number;
    numFailed: number;
    peerTypes: ComboboxEntry[];
    existingMaps: any;
    onOpenSub: Subscription;

    @ViewChild('successMsg', { static: true }) private successMsg: StringComponent;
    @ViewChild('errorMsg', { static: true }) private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private localStore: StoreService) {
        super(modal); // required for subclassing
        this.peerTypes = [];
        this.copyIds = [];
    }

    ngOnInit() {
        this.onOpenSub = this.onOpen$.subscribe(() => {
            if (this.modifyAll) {
                // This will be set once the list of copies to
                // modify has been fetched.
                this.copyIds = [];
            }
            this.numSucceeded = 0;
            this.numFailed = 0;

            if (!this.peerRecord) {
                this.peerRecord =
                    this.localStore.getLocalItem('eg.cat.marked_conjoined_record');

                if (!this.peerRecord) {
                    this.close(false);
                }
            }

            if (this.peerTypes.length === 0) {
                this.getPeerTypes();
            }

            this.fetchExistingMaps();
        });
    }

    ngOnDestroy() {
        this.onOpenSub.unsubscribe();
    }

    fetchExistingMaps() {
        this.existingMaps = {};
        const search: any = {
            peer_record: this.peerRecord
        };

        if (!this.modifyAll) {
            search.target_copy = this.copyIds;
        }

        this.pcrud.search('bpbcm', search)
            .subscribe(map => {
                this.existingMaps[map.target_copy()] = map;
                if (this.modifyAll) {
                    this.copyIds.push(map.target_copy());
                }
            });
    }

    // Fetch and map peer types to combobox entries
    getPeerTypes(): Promise<any> {
        return this.pcrud.retrieveAll('bpt', {}, {atomic: true}).toPromise()
            .then(types =>
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

    // Create or update peer copy links.
    linkCopies() {

        const maps: IdlObject[] = [];
        this.copyIds.forEach(id => {
            let map: IdlObject;
            if (this.existingMaps[id]) {
                map = this.existingMaps[id];
                map.ischanged(true);
            } else {
                map = this.idl.create('bpbcm');
                map.isnew(true);
            }

            map.peer_record(this.peerRecord);
            map.target_copy(id);
            map.peer_type(this.peerType);
            maps.push(map);
        });

        return this.pcrud.autoApply(maps).subscribe(
            { next: ok => this.numSucceeded++, error: (err: unknown) => {
                this.numFailed++;
                console.error(err);
                this.errorMsg.current().then(msg => this.toast.warning(msg));
            }, complete: () => {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.close(this.numSucceeded > 0);
            } }
        );
    }
}



