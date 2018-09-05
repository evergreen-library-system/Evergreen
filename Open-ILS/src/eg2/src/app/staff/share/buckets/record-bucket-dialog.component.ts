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

    recId: number;
    @Input() set recordId(id: number) {
        this.recId = id;
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
    }

    ngOnInit() {

        this.onOpen$.subscribe(ok => {
            // Reset data on dialog open

            this.selectedBucket = null;
            this.newBucketName = '';
            this.newBucketDesc = '';

            this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_by_class.authoritative',
                this.auth.token(), this.auth.user().id(),
                'biblio', 'staff_client'
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
        bucket.btype('staff_client');

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.create',
            this.auth.token(), 'biblio', bucket
        ).subscribe(bktId => {
            const evt = this.evt.parse(bktId);
            if (evt) {
                this.toast.danger(evt.desc);
            } else {
                this.addToBucket(bktId);
            }
        });
    }

    // Add the record to the selected existing bucket
    addToBucket(id: number) {
        const item = this.idl.create('cbrebi');
        item.bucket(id);
        item.target_biblio_record_entry(this.recId);
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create',
            this.auth.token(), 'biblio', item
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                this.toast.danger(evt.toString());
            } else {
                this.close();
            }
        });
    }
}



