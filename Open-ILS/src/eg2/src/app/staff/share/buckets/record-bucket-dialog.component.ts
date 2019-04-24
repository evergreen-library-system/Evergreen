import {Component, OnInit, Input, Renderer2} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';

/**
 * Dialog for adding bib records to new and existing record buckets.
 */

@Component({
  selector: 'eg-record-bucket-dialog',
  templateUrl: 'record-bucket-dialog.component.html'
})

export class RecordBucketDialogComponent
    extends DialogComponent implements OnInit {

    selectedBucket: number;
    newBucketName: string;
    newBucketDesc: string;
    buckets: any[];

    @Input() bucketType: string;

    // Add one or more bib records to bucket by ID.
    recIds: number[];
    @Input() set recordId(id: number | number[]) {
        this.recIds = [].concat(id);
    }

    // Add items from a (vandelay) bib queue to a bucket
    qId: number;
    @Input() set queueId(id: number) {
        this.qId = id;
    }

    constructor(
        private modal: NgbModal, // required for passing to parent
        private renderer: Renderer2,
        private toast: ToastService,
        private idl: IdlService,
        private net: NetService,
        private evt: EventService,
        private auth: AuthService) {
        super(modal); // required for subclassing
        this.recIds = [];
    }

    ngOnInit() {

        if (this.qId) {
            this.bucketType = 'vandelay_queue';
        } else {
            this.bucketType = 'staff_client';
        }

        this.onOpen$.subscribe(ok => {
            // Reset data on dialog open

            this.selectedBucket = null;
            this.newBucketName = '';
            this.newBucketDesc = '';

            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_by_class.authoritative',
                this.auth.token(), this.auth.user().id(),
                'biblio', this.bucketType
            ).subscribe(buckets => this.buckets = buckets);
        });
    }

    addToSelected() {
        this.addToBucket(this.selectedBucket);
    }

    // Create a new bucket then add the record
    addToNew() {
        const bucket = this.idl.create('cbreb');

        bucket.owner(this.auth.user().id());
        bucket.name(this.newBucketName);
        bucket.description(this.newBucketDesc);
        bucket.btype(this.bucketType);

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.create',
            this.auth.token(), 'biblio', bucket
        ).subscribe(bktId => {
            const evt = this.evt.parse(bktId);
            if (evt) {
                this.toast.danger(evt.desc);
            } else {
                // make it find-able to the queue-add method which
                // requires the bucket name.
                bucket.id(bktId);
                this.buckets.push(bucket);
                this.addToBucket(bktId);
            }
        });
    }

    addToBucket(id: number) {
        if (this.recIds.length > 0) {
            this.addRecordToBucket(id);
        } else if (this.qId) {
            this.addQueueToBucket(id);
        }
    }

    // Add the record(s) to the bucket with provided ID.
    addRecordToBucket(bucketId: number) {
        const items = [];
        this.recIds.forEach(recId => {
            const item = this.idl.create('cbrebi');
            item.bucket(bucketId);
            item.target_biblio_record_entry(recId);
            items.push(item);
        });

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create',
            this.auth.token(), 'biblio', items
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.close();
            }
        });
    }

    addQueueToBucket(bucketId: number) {
        const bucket = this.buckets.filter(b => b.id() === bucketId)[0];
        if (!bucket) { return; }

        this.net.request(
            'open-ils.vandelay',
            'open-ils.vandelay.bib_queue.to_bucket',
            this.auth.token(), this.qId, bucket.name()
        ).toPromise().then(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.close();
            }
        });
    }
}



