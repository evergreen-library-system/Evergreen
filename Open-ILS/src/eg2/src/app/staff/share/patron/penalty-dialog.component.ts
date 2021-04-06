import {Component, OnInit, Input, Output, ViewChild} from '@angular/core';
import {merge, from, Observable} from 'rxjs';
import {tap, take, switchMap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog container for patron penalty/message application
 *
 * <eg-patron-penalty-dialog [patronId]="myPatronId">
 * </eg-patron-penalty-dialog>
 */

@Component({
  selector: 'eg-patron-penalty-dialog',
  templateUrl: 'penalty-dialog.component.html'
})

export class PatronPenaltyDialogComponent
    extends DialogComponent implements OnInit {

    @Input() patronId: number;
    @Input() penaltyNote = '';

    ALERT_NOTE = 20;
    SILENT_NOTE = 21;
    STAFF_CHR = 25;

    penalty: IdlObject; // modifying an existing penalty
    penaltyTypes: IdlObject[];
    penaltyTypeFromSelect = '';
    penaltyTypeFromButton: number;
    patron: IdlObject;
    dataLoaded = false;
    requireInitials = false;
    initials: string;
    title = '';
    noteText = '';

    @ViewChild('successMsg', {static: false}) successMsg: StringComponent;
    @ViewChild('errorMsg', {static: false}) errorMsg: StringComponent;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private store: ServerStoreService,
        private evt: EventService,
        private toast: ToastService,
        private auth: AuthService,
        private pcrud: PcrudService) {
        super(modal);
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ =>
            this.init().subscribe(__ => this.dataLoaded = true));
    }

    init(): Observable<any> {
        this.dataLoaded = false;

        if (this.penalty) { // Modifying an existing penalty
            const pen = this.penalty;
            const sp = pen.standing_penalty().id();
            if (sp === this.ALERT_NOTE ||
                sp === this.SILENT_NOTE || sp === this.STAFF_CHR) {
                this.penaltyTypeFromButton = sp;
            } else {
                this.penaltyTypeFromSelect = sp;
            }

            this.noteText = pen.note();

        } else {
            this.penaltyTypeFromButton = this.SILENT_NOTE;
        }

        this.store.getItem('ui.staff.require_initials.patron_standing_penalty')
        .then(require => this.requireInitials = require);

        const obs1 = this.pcrud.retrieve('au', this.patronId)
            .pipe(tap(usr => this.patron = usr));

        if (this.penaltyTypes) { return obs1; }

        return obs1.pipe(switchMap(_ => {
            return this.pcrud.search('csp', {id: {'>': 100}}, {}, {atomic: true})

            .pipe(tap(ptypes => {
                this.penaltyTypes =
                    ptypes.sort((a, b) => a.label() < b.label() ? -1 : 1);
            }));
        }));
    }

    modifyPenalty() {
        this.penalty.note(this.initials ?
            `${this.noteText} [${this.initials}]` : this.noteText);

        this.penalty.standing_penalty(
            this.penaltyTypeFromSelect || this.penaltyTypeFromButton);

        this.pcrud.update(this.penalty).toPromise()
        .then(ok => {
            if (!ok) {
                this.errorMsg.current().then(msg => this.toast.danger(msg));
                this.error('Update failed', true);
            } else {
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.penalty = null;
                this.close(ok);
            }
        });
    }

    apply() {

        if (this.penalty) {
            this.modifyPenalty();
            return;
        }

        const pen = this.idl.create('ausp');
        const msg = {
            title: this.title,
            message: this.noteText ? this.noteText : ''
        };
        pen.usr(this.patronId);
        pen.org_unit(this.auth.user().ws_ou());
        pen.set_date('now');
        pen.staff(this.auth.user().id());

        if (this.initials) {
            msg.message = `${this.noteText} [${this.initials}]`;
        }

        pen.standing_penalty(
            this.penaltyTypeFromSelect || this.penaltyTypeFromButton);

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.penalty.apply',
            this.auth.token(), pen, msg
        ).subscribe(resp => {
            const e = this.evt.parse(resp);
            if (e) {
                this.errorMsg.current().then(m => this.toast.danger(m));
                this.error(e, true);
            } else {
                // resp == penalty ID on success
                this.successMsg.current().then(m => this.toast.success(m));
                this.close(resp);
            }
        });
    }

    buttonClass(pType: number): string {
        return this.penaltyTypeFromButton === pType ?
            'btn-primary' : 'btn-light';
    }
}



