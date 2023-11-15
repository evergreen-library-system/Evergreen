import {Component, OnInit, Input} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {ActivatedRoute} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {NgForm} from '@angular/forms';

@Component({
    selector: 'eg-query-dialog',
    templateUrl: './query-dialog.component.html'
})

export class QueryDialogComponent extends DialogComponent implements OnInit {

    currentId: number;
    newAsq: IdlObject;
    newAsfge: IdlObject;

    @Input() mode: 'create' | 'update';
    @Input() record: IdlObject;
    @Input() recordId: number;
    @Input() newQueryLabel: string;
    @Input() newQueryText: string;
    @Input() newQueryPosition: string;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private route: ActivatedRoute,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService
    ) {
        super(modal); // required for subclassing
    }

    ngOnInit() {
        this.currentId = parseInt(this.route.snapshot.paramMap.get('id'), 10);
        this.newAsfge = this.idl.create('asfge');
        this.newAsq = this.idl.create('asq');
    }

    // wipe out all data so next time we start with a clean slate
    closeAndReset(data) {
        this.mode = undefined;
        this.record = undefined;
        this.recordId = undefined;
        this.newQueryLabel = undefined;
        this.newQueryPosition = undefined;
        this.newQueryText = undefined;
        this.close(data);
    }

    save() {
        if (!this.newQueryLabel || (!this.newQueryPosition && (this.newQueryPosition !== '0')) || !this.newQueryText) {
            this.closeAndReset({notFilledOut: true});
        }
        const recToSave = this.prepareRecord();
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.filter_group_entry.crud',
            this.auth.token(),
            recToSave
        ).toPromise().then(res => {
            this.closeAndReset(res);
        });
    }

    prepareRecord(): IdlObject {
        let recToSave;
        let queryToSave;
        if (this.mode === 'create') {
            recToSave = this.idl.clone(this.newAsfge);
            queryToSave = this.idl.clone(this.newAsq);
            recToSave.isnew(true);
            recToSave.query(queryToSave);
        } else if (this.mode === 'update') {
            recToSave = this.record;
            queryToSave = this.record.query();
            recToSave.ischanged(true);
        } else {
            console.debug('Error!  No mode defined!');
        }
        queryToSave.label(this.newQueryLabel);
        queryToSave.query_text(this.newQueryText);
        recToSave.pos(this.newQueryPosition);
        recToSave.grp(this.currentId);
        return recToSave;
    }
}
