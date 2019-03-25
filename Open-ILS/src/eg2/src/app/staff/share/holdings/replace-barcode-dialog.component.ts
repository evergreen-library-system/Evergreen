import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for marking items missing.
 */

@Component({
  selector: 'eg-replace-barcode-dialog',
  templateUrl: 'replace-barcode-dialog.component.html'
})

export class ReplaceBarcodeDialogComponent
    extends DialogComponent implements OnInit {

    @Input() copyIds: number[];
    ids: number[]; // copy of list so we can pop()

    copy: IdlObject;
    newBarcode: string;
    barcodeExists: boolean;

    numSucceeded: number;
    numFailed: number;

    @ViewChild('successMsg')
        private successMsg: StringComponent;

    @ViewChild('errorMsg')
        private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private renderer: Renderer2,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    async open(args: NgbModalOptions): Promise<boolean> {
        this.ids = [].concat(this.copyIds);
        this.numSucceeded = 0;
        this.numFailed = 0;

        await this.getNextCopy();
        setTimeout(() =>
            // Give the dialog a chance to render
            this.renderer.selectRootElement('#new-barcode-input').focus()
        );
        return super.open(args);
    }

    async getNextCopy(): Promise<any> {

        if (this.ids.length === 0) {
            this.close(this.numSucceeded > 0);
            return Promise.resolve();
        }

        this.newBarcode = '';

        const id = this.ids.pop();

        return this.pcrud.retrieve('acp', id)
        .toPromise().then(c => this.copy = c);
    }

    async replaceOneBarcode(): Promise<any> {
        this.barcodeExists = false;

        // First see if the barcode is in use
        return this.pcrud.search('acp', {deleted: 'f', barcode: this.newBarcode})
        .toPromise().then(async (existing) => {
            if (existing) {
                this.barcodeExists = true;
                return;
            }

            this.copy.barcode(this.newBarcode);
            this.pcrud.update(this.copy).toPromise().then(
                async (ok) => {
                    this.numSucceeded++;
                    this.toast.success(await this.successMsg.current());
                    this.getNextCopy();
                },
                async (err) => {
                    this.numFailed++;
                    console.error('Replace barcode failed: ', err);
                    this.toast.warning(await this.errorMsg.current());
                }
            );
        });
    }
}



