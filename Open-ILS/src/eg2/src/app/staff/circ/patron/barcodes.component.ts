import {Component, Input} from '@angular/core';
import {Observable} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {PermService} from '@eg/core/perm.service';

const PERMS = ['UPDATE_PATRON_ACTIVE_CARD', 'UPDATE_PATRON_PRIMARY_CARD'];

/* Add/Remove Secondary Groups */

@Component({
    selector: 'eg-patron-barcodes',
    templateUrl: 'barcodes.component.html',
    styleUrls: ['barcodes.component.css']
})

export class PatronBarcodesDialogComponent extends DialogComponent {

    // Localized strings for template (JIT-compatible)
    deletionRequirementsTitle = $localize`Deletion Requirements`;
    deletionHelpLabel = $localize`Deletion requirements help`;

    @Input() set patron(p: IdlObject) {
        this._patron = p;
        // Reset backend state tracking when a new patron is provided
        if (p) {
            this.backendActive = new WeakMap();
            p.cards().forEach(card => this.backendActive.set(card, card.active()));
        }
    }
    get patron(): IdlObject {
        return this._patron;
    }
    private _patron: IdlObject;

    primaryCard: number;
    myPerms: {[name: string]: boolean} = {};
    private backendActive: WeakMap<IdlObject, string> = new WeakMap();
    private origPrimaryCard: number;

    constructor(
        private modal: NgbModal,
        private toast: ToastService,
        private perms: PermService
    ) { super(modal); }

    open(ops: NgbModalOptions): Observable<any> {
        this.primaryCard = this.patron.card().id();
        this.origPrimaryCard = this.primaryCard;

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
            if (card) {
                this.patron.card(card);
                // Update _primary flags for all cards
                this.patron.cards().forEach(c => (c as any)._primary = (c === card));
                // Mark the patron as changed so the editor knows to save
                if (typeof (this.patron as any).ischanged === 'function') {
                    (this.patron as any).ischanged(true);
                }
            }
        }
        this.close(true);
    }

    close(apply?: boolean) {
        if (!apply) {
            // Revert unsaved changes when closing without applying
            this.patron.cards().forEach(card => {
                if (this.backendActive.has(card)) {
                    card.active(this.backendActive.get(card));
                }
                card._primary = (card.id() === this.origPrimaryCard);
                if (card.isdeleted()) {
                    card.isdeleted(false);
                }
            });
        }
        super.close(apply);
    }

    activeChange(card: IdlObject, active: boolean) {
        card.ischanged(true);
        card.active(active ? 't' : 'f');
    }

    hasUnsavedActiveChanges(card: IdlObject): boolean {
        return this.backendActive.has(card) && this.backendActive.get(card) !== card.active();
    }

    getDeleteTitle(card: IdlObject): string {
        return this.hasUnsavedActiveChanges(card)
            ? $localize`Save patron record after deactivating before deleting`
            : $localize`Barcode must be deactivated and saved before deletion`;
    }

    deleteCard(card: IdlObject) {
        if (!(this.myPerms.UPDATE_PATRON_ACTIVE_CARD && this.myPerms.UPDATE_PATRON_PRIMARY_CARD)) {
            this.toast.danger($localize`Permission denied for deleting barcodes`);
            return;
        }

        // Cannot delete primary card
        if (card.id() === this.primaryCard) {
            this.toast.danger($localize`Cannot delete the primary barcode`);
            return;
        }

        // Cannot delete active barcode - must deactivate first
        if (card.active() === 't') {
            this.toast.danger(
                $localize`Active barcodes cannot be deleted. Deactivate the barcode first, save the patron record, then delete it.`
            );
            return;
        }

        // Check for unsaved deactivation changes
        if (this.hasUnsavedActiveChanges(card)) {
            this.toast.warning($localize`Please save the patron record after deactivating the barcode before deleting it.`);
            return;
        }

        card.isdeleted(true);
    }

    hasPendingDeletes(): boolean {
        return this.patron.cards().some(card => card.isdeleted());
    }
}

