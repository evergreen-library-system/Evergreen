import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {throwError} from 'rxjs';
import {switchMap} from 'rxjs/operators';
import {NetService} from '@eg/core/net.service';
import {IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {StringComponent} from '@eg/share/string/string.component';
import {BucketService} from '@eg/staff/share/buckets/bucket.service';

/**
 * Dialog for adding bib records to new and existing record buckets.
 */

@Component({
    selector: 'eg-bucket-dialog',
    templateUrl: 'bucket-dialog.component.html'
})

export class BucketDialogComponent extends DialogComponent implements OnInit {

    activeTabId = 1; // Existing Buckets tab
    selectedBucket: number;
    sharedBucketId: number;
    sharedBucketName: string;
    newBucketName: string;
    newBucketDesc: string;
    buckets: any[];
    showExistingBuckets = true;

    @Input() bucketClass: 'biblio' | 'user' | 'callnumber' | 'copy';
    @Input() bucketType: string; // e.g. staff_client

    // ID's of items to add to the bucket
    @Input() itemIds: number[];

    // If set, itemIds will be derived from the records in a bib queue
    @Input() fromBibQueue: number;

    // bucket item classes are these plus a following 'i'.
    bucketFmClass: 'ccb' | 'ccnb' | 'cbreb' | 'cub';
    targetField: string;

    @ViewChild('confirmAddToShared') confirmAddToShared: ConfirmDialogComponent;
    @ViewChild('successString') successString: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private renderer: Renderer2,
        private toast: ToastService,
        private idl: IdlService,
        private net: NetService,
        private bucketService: BucketService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
        this.buckets = [];
        this.itemIds = [];
        this.fromBibQueue = null;
    }

    ngOnInit() {
        this.onOpen$.subscribe(ok => {
            this.reset(); // Reset data on dialog open
            if (this.showExistingBuckets) {
                this.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.retrieve_by_class.authoritative',
                    this.auth.token(), this.auth.user().id(),
                    this.bucketClass, this.bucketType
                // eslint-disable-next-line rxjs/no-nested-subscribe
                ).subscribe(buckets => this.buckets = buckets);
            } else {
                this.activeTabId = 2; // New Bucket tab
            }
        });
    }

    reset() {
        this.selectedBucket = null;
        this.sharedBucketId = null;
        this.sharedBucketName = '';
        this.newBucketName = '';
        this.newBucketDesc = '';

        if (!this.bucketClass) {
            this.bucketClass = 'biblio';
        }

        switch (this.bucketClass) {
            case 'biblio':
                if (this.fromBibQueue) {
                    this.bucketType = 'vandelay_queue';
                }
                this.bucketFmClass = 'cbreb';
                this.targetField = 'target_biblio_record_entry';
                break;
            case 'copy':
                this.bucketFmClass = 'ccb';
                this.targetField = 'target_copy';
                break;
            case 'callnumber':
                this.bucketFmClass = 'ccnb';
                this.targetField = 'target_call_number';
                break;
            case 'user':
                this.bucketFmClass = 'cub';
                this.targetField = 'target_user';
        }

        if (!this.bucketType) {
            this.bucketType = 'staff_client';
        }

        this.showExistingBuckets = this.itemIds.length > 0 || Boolean(this.fromBibQueue);
    }

    addToSelected() {
        this.addToBucket(this.selectedBucket);
    }

    addToShared() {
        this.net.request('open-ils.actor',
            'open-ils.actor.container.flesh',
            this.auth.token(), this.bucketClass,
            this.sharedBucketId)
            .pipe(switchMap((resp) => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    this.toast.danger(evt.toString());
                    return throwError(evt);
                } else {
                    this.sharedBucketName = resp.name();
                    return this.confirmAddToShared.open();
                }
            })).subscribe(() => {
                this.addToBucket(this.sharedBucketId);
            });
    }

    bucketChanged(entry: ComboboxEntry) {
        if (entry) {
            this.selectedBucket = entry.id;
        } else {
            this.selectedBucket = null;
        }
    }

    formatBucketEntries(): ComboboxEntry[] {
        return this.buckets.map(b => ({id: b.id(), label: b.name()}));
    }

    // Create a new bucket then add the record
    addToNew() {
        const bucket = this.idl.create(this.bucketFmClass);

        bucket.owner(this.auth.user().id());
        bucket.name(this.newBucketName);
        bucket.description(this.newBucketDesc);
        bucket.btype(this.bucketType);

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.create',
            this.auth.token(), this.bucketClass, bucket
        ).subscribe(bktId => {
            const evt = this.evt.parse(bktId);
            if (evt) {
                this.toast.danger(evt.desc);
            } else {
                // make it find-able to the queue-add method which
                // requires the bucket name.
                bucket.id(bktId);
                this.buckets.push(bucket);
                if (this.showExistingBuckets) { // aka, in a "add to bucket" context
                    this.addToBucket(bktId);
                } else {
                    this.bucketService.logRecordBucket(bktId);
                    this.bucketService.requestBibBucketsRefresh();
                    this.close({success: true, bucket: bktId}); // we're done
                }
            }
        });
    }

    addToBucket(id: number) {
        if (this.itemIds.length > 0) {
            this.addRecordToBucket(id);
        } else if (this.fromBibQueue) {
            this.addBibQueueToBucket(id);
        }
    }

    // Add the record(s) to the bucket with provided ID.
    addRecordToBucket(bucketId: number) {
        this.bucketService.logRecordBucket(bucketId);
        const items = [];
        this.itemIds.forEach(itemId => {
            const item = this.idl.create(this.bucketFmClass + 'i');
            item.bucket(bucketId);
            item[this.targetField](itemId);
            items.push(item);
        });

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create',
            this.auth.token(), this.bucketClass, items
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.toast.success(this.successString.text);
                this.bucketService.requestBibBucketsRefresh();
                this.close({success: true, bucket: bucketId}); // we're done
            }
        });
    }

    addBibQueueToBucket(bucketId: number) {
        const bucket = this.buckets.filter(b => b.id() === bucketId)[0];
        if (!bucket) { return; }
        this.bucketService.logRecordBucket(bucketId);

        this.net.request(
            'open-ils.vandelay',
            'open-ils.vandelay.bib_queue.to_bucket',
            this.auth.token(), this.fromBibQueue, bucket.name()
        ).toPromise().then(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.bucketService.requestBibBucketsRefresh();
                this.close({success: true, bucket: bucketId}); // we're done
            }
        });
    }
}




