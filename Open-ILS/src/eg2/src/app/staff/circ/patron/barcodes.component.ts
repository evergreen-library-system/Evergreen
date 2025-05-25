import {Component, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {PatronContextService} from './patron.service';
import {PermService} from '@eg/core/perm.service';

const PERMS = ['UPDATE_PATRON_ACTIVE_CARD', 'UPDATE_PATRON_PRIMARY_CARD'];

/* Add/Remove Secondary Groups */

@Component({
    selector: 'eg-patron-barcodes',
    templateUrl: 'barcodes.component.html'
})

export class PatronBarcodesDialogComponent extends DialogComponent {

    @Input() patron: IdlObject;
    primaryCard: number;
    myPerms: {[name: string]: boolean} = {};

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private net: NetService,
        private idl: IdlService,
        private evt: EventService,
        private pcrud: PcrudService,
        private org: OrgService,
        private auth: AuthService,
        private perms: PermService,
        private context: PatronContextService
    ) { super(modal); }

    open(ops: NgbModalOptions): Observable<any> {
        this.patron.cards().some(card => {
            if (card.id() === this.patron.card().id()) {
                this.primaryCard = card.id();
                return true;
            }
        });

        this.perms.hasWorkPermAt(PERMS, true).then(perms => {
            PERMS.forEach(p => {
                this.myPerms[p] = perms[p].includes(this.patron.home_ou());
            });
        });

        return super.open(ops);
    }

    applyChanges() {
        if (this.primaryCard !== this.patron.card().id()) {
            const card = this.patron.cards()
                .filter(c => c.id() === this.primaryCard)[0];
            this.patron.card(card);
        }
        this.close(true);
    }

    activeChange(card: IdlObject, active: boolean) {
        card.ischanged(true);
        card.active(active ? 't' : 'f');
    }
}

