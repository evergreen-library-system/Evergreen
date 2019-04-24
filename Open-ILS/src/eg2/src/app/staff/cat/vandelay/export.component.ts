import {Component, AfterViewInit, ViewChild, Renderer2} from '@angular/core';
import {NgbPanelChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {HttpClient, HttpRequest, HttpEventType} from '@angular/common/http';
import {HttpResponse, HttpErrorResponse} from '@angular/common/http';
import {saveAs} from 'file-saver';
import {AuthService} from '@eg/core/auth.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {VandelayService, VANDELAY_EXPORT_PATH} from './vandelay.service';


@Component({
  templateUrl: 'export.component.html'
})
export class ExportComponent implements AfterViewInit {

    recordSource: string;
    fieldNumber: number;
    selectedFile: File;
    recordId: number;
    bucketId: number;
    recordType: string;
    recordFormat: string;
    recordEncoding: string;
    includeHoldings: boolean;
    isExporting: boolean;

    @ViewChild('fileSelector') private fileSelector;
    @ViewChild('exportProgress')
        private exportProgress: ProgressInlineComponent;

    constructor(
        private renderer: Renderer2,
        private http: HttpClient,
        private toast: ToastService,
        private auth: AuthService
    ) {
        this.recordType = 'biblio';
        this.recordFormat = 'USMARC';
        this.recordEncoding = 'UTF-8';
        this.includeHoldings = false;
    }

    ngAfterViewInit() {
        this.renderer.selectRootElement('#csv-input').focus();
    }

    sourceChange($event: NgbPanelChangeEvent) {
        this.recordSource = $event.panelId;

        if ($event.nextState) { // panel opened

            // give the panel a chance to render before focusing input
            setTimeout(() => {
                this.renderer.selectRootElement(
                    `#${this.recordSource}-input`).focus();
            });
        }
    }

    fileSelected($event) {
       this.selectedFile = $event.target.files[0];
    }

    hasNeededData(): boolean {
        return Boolean(
            this.selectedFile || this.recordId || this.bucketId
        );
    }

    exportRecords() {
        this.isExporting = true;
        this.exportProgress.update({value: 0});

        const formData: FormData = new FormData();

        formData.append('ses', this.auth.token());
        formData.append('rectype', this.recordType);
        formData.append('encoding', this.recordEncoding);
        formData.append('format', this.recordFormat);

        if (this.includeHoldings) {
            formData.append('holdings', '1');
        }

        switch (this.recordSource) {

            case 'csv':
                formData.append('idcolumn', '' + this.fieldNumber);
                formData.append('idfile',
                    this.selectedFile, this.selectedFile.name);
                break;

            case 'record-id':
                formData.append('id', '' + this.recordId);
                break;

            case 'bucket-id':
                formData.append('containerid', '' + this.bucketId);
                break;
        }

        this.sendExportRequest(formData);
    }

    sendExportRequest(formData: FormData) {

        const fileName = `export.${this.recordType}.` +
            `${this.recordEncoding}.${this.recordFormat}`;

        const req = new HttpRequest('POST', VANDELAY_EXPORT_PATH,
            formData, {reportProgress: true, responseType: 'text'});

        this.http.request(req).subscribe(
            evt => {
                console.debug(evt);
                if (evt.type === HttpEventType.DownloadProgress) {
                    // File size not reported by server in advance.
                    this.exportProgress.update({value: evt.loaded});

                } else if (evt instanceof HttpResponse) {

                    saveAs(new Blob([evt.body as Blob],
                        {type: 'application/octet-stream'}), fileName);

                    this.isExporting = false;
                }
            },

            (err: HttpErrorResponse) => {
                console.error(err);
                this.toast.danger(err.error);
                this.isExporting = false;
            }
        );
    }
}

