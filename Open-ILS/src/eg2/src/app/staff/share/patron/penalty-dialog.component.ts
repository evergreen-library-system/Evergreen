import {Component, OnInit, Input, Output, ViewChild} from '@angular/core';
import {merge, from, Observable} from 'rxjs';
import {tap, take, switchMap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
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

    staffInitials: string;
    penaltyTypes: IdlObject[];
    penaltyTypeFromSelect = '';
    penaltyTypeFromButton;
    patron: IdlObject;
    dataLoaded = false;
    requireInitials = false;
    initials: string;
    noteText = '';

    @ViewChild('successMsg', {static: false}) successMsg: StringComponent;
    @ViewChild('errorMsg', {static: false}) errorMsg: StringComponent;

    constructor(
        private modal: NgbModal,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
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

        this.penaltyTypeFromButton = this.SILENT_NOTE;

        this.org.settings(['ui.staff.require_initials.patron_standing_penalty'])
        .then(sets => this.requireInitials =
            sets['ui.staff.require_initials.patron_standing_penalty']);

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

    apply() {

        const pen = this.idl.create('ausp');
        pen.usr(this.patronId);
        pen.org_unit(this.auth.user().ws_ou());
        pen.set_date('now');
        pen.staff(this.auth.user().id());

        pen.note(this.initials ?
            `${this.noteText} [${this.initials}]` : this.noteText);

        pen.standing_penalty(
            this.penaltyTypeFromSelect || this.penaltyTypeFromButton);

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.penalty.apply',
            this.auth.token(), pen
        ).subscribe(resp => {
            const e = this.evt.parse(resp);
            if (e) {
                this.errorMsg.current().then(msg => this.toast.danger(msg));
                this.error(e, true);
            } else {
                // resp == penalty ID on success
                this.successMsg.current().then(msg => this.toast.success(msg));
                this.close(resp);
            }
        });
    }

    buttonClass(pType: number): string {
        return this.penaltyTypeFromButton === pType ?
            'btn-primary' : 'btn-light';
    }
}



