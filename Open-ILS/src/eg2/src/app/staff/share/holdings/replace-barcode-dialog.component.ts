import { Component, Input, ViewChild, Renderer2, inject } from '@angular/core';
import {Observable, switchMap, map, tap} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';
import { FormsModule } from '@angular/forms';



/**
 * Dialog for changing an item's barcode
 */

@Component({
    selector: 'eg-replace-barcode-dialog',
    templateUrl: 'replace-barcode-dialog.component.html',
    imports: [
        FormsModule,
        StringComponent
    ]
})

export class ReplaceBarcodeDialogComponent
    extends DialogComponent {
    private toast = inject(ToastService);
    private auth = inject(AuthService);
    private net = inject(NetService);
    private evt = inject(EventService);
    private pcrud = inject(PcrudService);
    private renderer = inject(Renderer2);


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

        if (this.auth.opChangeIsActive()) {
            // FIXME: kludge for now, opChange has been reverting mid-dialog with batch use when handling permission elevation
            this.auth.undoOpChange();
        }

        if (this.ids.length === 0) {
            this.close(this.numSucceeded > 0);
        }

        this.newBarcode = '';

        const id = this.ids.pop();

        return this.pcrud.retrieve('acp', id)
            .pipe(map(c => this.copy = c));
    }

    replaceOneBarcode() {
        this.barcodeExists = false;

        // First see if the barcode is in use
        return this.pcrud.search('acp', {deleted: 'f', barcode: this.newBarcode})
            .toPromise().then(async (existing) => {
                if (existing) {
                    this.barcodeExists = true;
                    return;
                }

                this.net.request(
                    'open-ils.cat',
                    'open-ils.cat.update_copy_barcode',
                    this.auth.token(), this.copy.id(), this.newBarcode
                ).subscribe(
                    { next: (res) => {
                        if (this.evt.parse(res)) {
                            console.error('parsed error response', res);
                        } else {
                            console.log('success', res);
                            this.numSucceeded++;
                            this.successMsg.current().then(m => this.toast.success(m));
                            this.getNextCopy().toPromise();
                        }
                    }, error: (err: unknown) => {
                        console.error('error', err);
                        this.numFailed++;
                        console.error('Replace barcode failed: ', err);
                        this.errorMsg.current().then(m => this.toast.warning(m));
                    }, complete: () => {
                        console.log('finis');
                    } }
                );
            });
    }
}



