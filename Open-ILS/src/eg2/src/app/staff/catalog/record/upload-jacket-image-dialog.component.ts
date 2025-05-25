/* eslint-disable no-self-assign */
import {Component, Input, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {HttpClient, HttpResponse} from '@angular/common/http';

@Component({
    selector: 'eg-upload-jacket-image-dialog',
    templateUrl: './upload-jacket-image-dialog.component.html'
})


export class UploadJacketImageDialogComponent extends DialogComponent implements OnInit {

    // ID of bib record for jacket image
    @Input() recordId: number;

    uploading: boolean;
    noFile: boolean;
    errorUploading: boolean;
    errorAuthentication: boolean;
    errorAuthorization: boolean;
    errorCompressionConfig: boolean;
    errorNotFound: boolean;
    errorLocationConfig: boolean;
    errorWritingFile: boolean;
    errorSize: boolean;
    errorParsing: boolean;
    errorGeneric: boolean;

    private fileEvent: any;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private evt: EventService,
        private net: NetService,
        private toast: ToastService,
        private http: HttpClient
    ) {
        super(modal);
    }

    clearErrors() {
        this.errorAuthentication = false;
        this.errorAuthorization = false;
        this.errorCompressionConfig = false;
        this.errorNotFound = false;
        this.errorLocationConfig = false;
        this.errorWritingFile = false;
        this.errorSize = false;
        this.errorParsing = false;
        this.errorGeneric = false;
        this.errorUploading = false;
    }

    ngOnInit() {
        this.uploading = false;
        this.noFile = true;
        this.clearErrors();
    }

    onFileSelected(event) {
        console.debug('onFileSelected', event);
        this.fileEvent = event;
        const file: File = this.fileEvent.target.files[0];
        if (file) {
            this.noFile = false;
        } else {
            this.noFile = true;
        }
    }

    uploadJacketImage() {
        const file: File = this.fileEvent.target.files[0];
        if (file) {
            this.uploading = true;
            this.clearErrors();
            const formData = new FormData();
            formData.append('jacket_upload', file);
            formData.append('ses', this.auth.token());
            formData.append('bib_record', this.recordId.toString());

            const upload$ = this.http.post('/jacket-upload', formData, {
                reportProgress: true,
                observe: 'events'
            });

            upload$.subscribe(
                { next: x => {
                    console.debug('Jacket upload: ' , x);
                    if (x instanceof HttpResponse) {
                        console.debug('yay', x.body);
                        if (x.body.toString() !== '1') {
                            this.uploading = false;
                            this.errorUploading = true;
                        }
                        switch (x.body) {
                            case 'session not found': this.errorAuthentication = true; break;
                            case 'permission denied': this.errorAuthorization = true; break;
                            case 'invalid compression level': this.errorCompressionConfig = true; break;
                            case 'bib not found': this.errorNotFound = true; break;
                            case 'jacket location not configured': this.errorLocationConfig = true; break;
                            case 'unable to open file for writing': this.errorWritingFile = true; break;
                            case 'file too large': this.errorSize = true; break;
                            case 'parse error': this.errorParsing = true; break;
                            case 'upload error': this.errorGeneric = true; break;
                            default: this.errorGeneric = true; break;
                        }
                    }
                }, error: (err: unknown) => {
                    this.uploading = false;
                    this.errorUploading = true;
                    this.errorGeneric = true;
                    console.error('jacket upload error: ' , err);
                }, complete: () => this.refreshPage() }
            );
        }
    }

    refreshPage() {
        if (this.errorUploading) {
            console.debug('no refresh page due to error');
        } else {
            console.debug('refresh page');
            location.href = location.href;
        }
    }
}
