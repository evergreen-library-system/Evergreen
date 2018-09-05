import {Component, Input, OnInit, ViewChild, TemplateRef, EventEmitter} from '@angular/core';
import {NgbModal, NgbModalRef, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

/**
 * Dialog base class.  Handles the ngbModal logic.
 * Sub-classed component templates must have a #dialogContent selector
 * at the root of the template (see ConfirmDialogComponent).
 */

@Component({
    selector: 'eg-dialog',
    template: '<ng-template></ng-template>'
})
export class DialogComponent implements OnInit {

    // Assume all dialogs support a title attribute.
    @Input() public dialogTitle: string;

    // Pointer to the dialog content template.
    @ViewChild('dialogContent')
    private dialogContent: TemplateRef<any>;

    // Emitted after open() is called on the ngbModal.
    // Note when overriding open(), this will not fire unless also
    // called in the overridding method.
    onOpen$ = new EventEmitter<any>();

    // The modalRef allows direct control of the modal instance.
    private modalRef: NgbModalRef = null;

    constructor(private modalService: NgbModal) {}

    ngOnInit() {
        this.onOpen$ = new EventEmitter<any>();
    }

    open(options?: NgbModalOptions): Promise<any> {

        if (this.modalRef !== null) {
            console.warn('Dismissing existing dialog');
            this.dismiss();
        }

        this.modalRef = this.modalService.open(this.dialogContent, options);

        if (this.onOpen$) {
            // Let the digest cycle complete
            setTimeout(() => this.onOpen$.emit(true));
        }

        return new Promise( (resolve, reject) => {

            this.modalRef.result.then(
                (result) => {
                    resolve(result);
                    this.modalRef = null;
                },
                (result) => {
                    console.debug('dialog closed with ' + result);
                    reject(result);
                    this.modalRef = null;
                }
            );
        });
    }

    close(reason?: any): void {
        if (this.modalRef) {
            this.modalRef.close(reason);
        }
    }

    dismiss(reason?: any): void {
        if (this.modalRef) {
            this.modalRef.dismiss(reason);
        }
    }
}


