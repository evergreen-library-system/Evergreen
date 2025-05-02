import {Component, HostListener, OnInit, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {ServerStoreService} from '@eg/core/server-store.service';

/**
 * Special Characters Map Dialog
 */

@Component({
    selector: 'eg-charmap-dialog',
    templateUrl: './charmap-dialog.component.html',
    styleUrls: ['charmap-dialog.component.css']
})

export class CharMapDialogComponent extends DialogComponent implements OnInit {

    copy = '';
    disableAccessKeys = true;

    constructor(
        private modal: NgbModal,
        private store: ServerStoreService
    ) { super(modal); }

    async ngOnInit(): Promise<void> {
        this.disableAccessKeys = await this.checkAccessKeys();
    }

    async checkAccessKeys(): Promise<boolean> {
        return this.store.getItem('eg.admin.keyboard_shortcuts.disable_single');
    }

    setAccessKeysPref(val: boolean) {
        this.disableAccessKeys = val;
        this.store.setItem('eg.admin.keyboard_shortcuts.disable_single', val);
    }

    @HostListener('window:keydown', ['$event'])
    focusHeading($event) {
        if (!this.modalRef) {return;} // don't grab keydown if the charmap modal isn't open
        if (this.disableAccessKeys) {return;}
        // console.debug("Keydown ", $event.key);
        const letters = '0123456789abcdefghijklmnopqrstuvwxyz'.split('');
        if (letters.includes($event.key)) {
            const el = document.querySelector('[data-index='+String($event.key)+']') as HTMLElement;
            setTimeout(() => el?.focus());
        }
    }

    public copyChar(char: string) {
        this.copy = char;
        // make the announcement visible
        document.querySelector('#copyAnnouncement').classList.remove('d-none');
        // trigger the ARIA status announcement
        document.querySelector('#copyAnnouncement span').classList.remove('d-none');
        console.debug('Copying character code ', char);
        navigator.clipboard.writeText(char);
        setTimeout(() => this.close(), 1000);
    }
}
