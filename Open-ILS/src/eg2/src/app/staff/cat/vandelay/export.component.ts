import {Component, AfterViewInit, ViewChild, Renderer2, OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {HttpClient, HttpRequest, HttpEventType,
    HttpResponse, HttpErrorResponse} from '@angular/common/http';
import {saveAs} from 'file-saver';
import {AuthService} from '@eg/core/auth.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ProgressInlineComponent} from '@eg/share/dialog/progress-inline.component';
import {VANDELAY_EXPORT_PATH} from './vandelay.service';
import {BasketService} from '@eg/share/catalog/basket.service';


@Component({
    templateUrl: 'export.component.html'
})
export class ExportComponent implements AfterViewInit, OnInit {

    recordSource = 'csv';
    fieldNumber: number;
    selectedFile: File;
    recordId: number;
    bucketId: number;
    recordType: string;
    recordFormat: string;
    recordEncoding: string;
    includeHoldings: boolean;
    isExporting: boolean;
    exportingBasket: boolean;
    basketRecords: number[];

    @ViewChild('fileSelector', { static: false }) private fileSelector;
    @ViewChild('exportProgress', { static: true })
    private exportProgress: ProgressInlineComponent;

    constructor(
        private renderer: Renderer2,
        private route: ActivatedRoute,
        private http: HttpClient,
        private toast: ToastService,
        private auth: AuthService,
        private basket: BasketService
    ) {
        this.recordType = 'biblio';
        this.recordFormat = 'USMARC';
        this.recordEncoding = 'UTF-8';
        this.includeHoldings = false;
        this.basketRecords = [];
    }

    ngOnInit() {
        const segments = this.route.snapshot.url.length;
        if (segments > 0 &&
            this.route.snapshot.url[segments - 1].path === 'basket') {
            this.exportingBasket = true;
            this.basket.getRecordIds().then(
                ids => this.basketRecords = ids
            );
        }
    }

    ngAfterViewInit() {
        if (this.exportingBasket) {
            return; // no source to focus
        }
        // this.renderer.selectRootElement('#csv-input').focus();
    }

    fileSelected($event) {
        this.selectedFile = $event.target.files[0];
    }

    hasNeededData(): boolean {
        return Boolean(
            this.selectedFile ||
            this.recordId     ||
            this.bucketId     ||
            (this.exportingBasket && this.basketRecords.length > 0)
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

        if (this.exportingBasket) {
            this.basketRecords.forEach(id => formData.append('id', '' + id));

        } else {

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
        }

        this.sendExportRequest(formData);
    }

    sendExportRequest(formData: FormData) {

        const fileName = `export.${this.recordType}.` +
            `${this.recordEncoding}.${this.recordFormat}`;

        const req = new HttpRequest('POST', VANDELAY_EXPORT_PATH,
            formData, {reportProgress: true, responseType: 'text'});

        this.http.request(req).subscribe(
            { next: evt => {
                console.debug(evt);
                if (evt.type === HttpEventType.DownloadProgress) {
                    // File size not reported by server in advance.
                    this.exportProgress.update({value: evt.loaded});

                } else if (evt instanceof HttpResponse) {

                    saveAs(new Blob([evt.body as Blob],
                        {type: 'application/octet-stream'}), fileName);

                    this.isExporting = false;
                }
            }, error: (err: HttpErrorResponse) => {
                console.error(err);
                this.toast.danger(err.error);
                this.isExporting = false;
            } }
        );
    }
}

