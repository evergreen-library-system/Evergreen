import {Component, OnInit, Input, ViewChild, Renderer2} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap, map, tap} from 'rxjs/operators';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';


/**
 * Dialog for changing an item's barcode
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

    @ViewChild('successMsg', { static: true })
        private successMsg: StringComponent;

    @ViewChild('errorMsg', { static: true })
        private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private pcrud: PcrudService,
        private renderer: Renderer2) {
        super(modal); // required for subclassing
    }

    ngOnInit() {}

    open(args: NgbModalOptions): Observable<boolean> {
        this.ids = [].concat(this.copyIds);
        this.numSucceeded = 0;
        this.numFailed = 0;

        return this.getNextCopy()
        .pipe(switchMap(() => super.open(args)),
            tap(() =>
                this.renderer.selectRootElement('#new-barcode-input').focus())
        );
    }

    getNextCopy(): Observable<any> {

        if (this.ids.length === 0) {
            this.close(this.numSucceeded > 0);
        }

        this.newBarcode = '';

        const id = this.ids.pop();

        return this.pcrud.retrieve('acp', id)
        .pipe(map(c => this.copy = c));
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
                    return this.getNextCopy().toPromise();
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



