/* eslint-disable max-len */
import {Component, Input, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {Subscription, firstValueFrom} from 'rxjs';
import {tap} from 'rxjs/operators';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {EventService} from '@eg/core/event.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    selector: 'eg-record-bucket-item-upload-dialog',
    templateUrl: './record-bucket-item-upload-dialog.component.html'
})
export class RecordBucketItemUploadDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    @Input() containerObjects: any[];
    @Input() bucketLabel: string;

    @ViewChild('fail', { static: true }) fail: AlertDialogComponent;
    @ViewChild('success', { static: true }) success: AlertDialogComponent;
    @ViewChild('confirm', { static: true }) confirm: ConfirmDialogComponent;

    importDisabled = true;
    importType: 'bibIds' | 'tcns' = 'bibIds';
    pastedValues = '';
    selectedFile: File | null = null;
    csvColumnNumber = 1;
    maxCsvColumns = 100;

    constructor(
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private idl: IdlService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        console.debug('RecordBucketItemUploadDialogComponent, init', this);
    }

    // eslint-disable-next-line @angular-eslint/no-empty-lifecycle-method
    ngOnDestroy() {
        // Unsubscribe from any subscriptions if needed
    }

    onFileSelected(event: Event) {
        console.debug('onFileSelected', event);
        const target = event.target as HTMLInputElement;
        if (target.files && target.files.length > 0) {
            this.selectedFile = target.files[0];
        } else {
            this.selectedFile = null;
        }
        this.importDisabled = !this.isImportAllowed();
    }

    clearPastedValues() {
        this.pastedValues = '';
    }

    isImportAllowed(): boolean {
        return !!(this.selectedFile || this.pastedValues.trim());
    }

    tickleDisabledCheck() {
        this.importDisabled = !this.isImportAllowed();
    }

    async importRecords(): Promise<void> {
        this.importDisabled = !this.isImportAllowed();
        if (this.importDisabled) { return; }

        let values: string[] = [];

        if (this.selectedFile) {
            values = await this.readCsvFile(this.selectedFile);
        } else if (this.pastedValues.trim()) {
            values = this.pastedValues.split(/\r?\n/).filter(v => v.trim());
        }

        if (values.length > 0) {
            if (this.importType === 'tcns') {
                const bibIds = await this.fetchBibIdsFromTCNs(values);
                await this.addToBuckets(bibIds);
            } else {
                const bibIds = await this.testBibIds(values);
                await this.addToBuckets(bibIds);
            }
            this.close({success: true});
        } else {
            this.importDisabled = true;
        }
    }


    private async readCsvFile(file: File): Promise<string[]> {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => {
                const content = e.target.result as string;
                const lines = content.split(/\r?\n/).filter(line => line.trim());
                const values: string[] = [];

                for (const line of lines) {
                    const columns = line.split(',');
                    if (this.csvColumnNumber > columns.length) {
                        reject(new Error($localize`CSV column number ${this.csvColumnNumber} is out of range. The file only has ${columns.length} columns.`));
                        return;
                    }
                    const value = columns[this.csvColumnNumber - 1].trim();
                    if (value) {
                        values.push(value);
                    }
                }

                resolve(values);
            };
            reader.onerror = (e) => reject(new Error($localize`Error reading CSV file`));
            reader.readAsText(file);
        });
    }

    private async fetchBibIdsFromTCNs(rawInput: string[]): Promise<number[]> {
        try {
            const TCNs = rawInput.filter(id => id.trim() !== '-1'); // remove pre-cat bib
            console.debug('attempting TCNs', TCNs);
            if (TCNs.length === 0) {
                this.fail.dialogBody = $localize`After filtering, there no valid TCNs to process.`;
                this.fail.open();
                return [];
            }

            const response = await firstValueFrom(this.net.request(
                'open-ils.search',
                'open-ils.search.biblio.tcn.batch',
                this.auth.token(),
                TCNs
            ));
            const evt = this.evt.parse(response);
            if (evt) {
                console.error(evt.toString());
                this.fail.dialogBody = evt.toString();
                this.fail.open();
                return [];
            }

            const bibIds: number[] = [];

            response.successful.forEach(item => {
                bibIds.push(...item.ids);
            });
            const failedTCNs = response.failed;

            const imported = $localize`Bibs imported: ` + bibIds.length;
            if (failedTCNs.length > 0) {
                console.warn('failedTCNs',failedTCNs);
                if (failedTCNs.length > 10) {
                    this.fail.dialogBody = imported + '\n' + $localize`Failed to find bibs for more than 10 TCNs. See the developer tools console for specific entries.`;
                } else {
                    this.fail.dialogBody = imported + '\n' + $localize`Failed to find bibs for the following TCNs: ` + failedTCNs.join(', ');
                }
                this.fail.open();
            } else {
                this.success.dialogTitle = 'Successful Import';
                this.success.dialogBody = imported;
                this.success.alertType = 'success';
                this.success.open();
            }

            return bibIds;
        } catch (error) {
            console.error('Error fetching Bib IDs from TCNs', error);
            this.fail.dialogBody = error.toString();
            this.fail.open();
            return [];
        }
    }

    private async testBibIds(bibIds: string[]): Promise<number[]> {
        try {
            // Filter out non-numeric IDs and cast remaining IDs to numbers
            const numericBibIds = bibIds
                .filter(id => !isNaN(Number(id)))
                .map(id => Number(id))
                .filter(id => id !== -1); // remove pre-cat bib
            console.debug('attempting bib Ids', numericBibIds);

            if (numericBibIds.length === 0) {
                this.fail.dialogBody = $localize`After filtering, there no valid Ids to process.`;
                this.fail.open();
                return [];
            }

            // Fetch valid IDs from the database
            const validIds = await firstValueFrom(this.pcrud.search('bre', { id: numericBibIds }, {}, { idlist: true, atomic: true }));
            console.debug('validIds', validIds);

            // Determine valid numeric IDs as strings for comparison
            const validNumericIds = validIds.map(id => id.toString());

            // Find invalid IDs (both numeric and non-numeric)
            const invalidIds = bibIds.filter(id => {
                const isNumeric = !isNaN(Number(id));
                return !isNumeric || !validNumericIds.includes(id);
            });

            const imported = $localize`Bibs imported: ` + validIds.length;
            if (invalidIds.length > 0) {
                console.warn('invalidIds',invalidIds);
                if (invalidIds.length > 10) {
                    this.fail.dialogBody = imported + '\n' + $localize`Failed to find bibs for more than 10 Ids. See the developer tools console for specific entries.`;
                } else {
                    this.fail.dialogBody = imported + '\n' + $localize`Failed to find bibs for the following Ids: ` + invalidIds.join(', ');
                }
                this.fail.open();
            } else {
                this.success.dialogTitle = 'Successful Import';
                this.success.dialogBody = imported;
                this.success.alertType = 'success';
                this.success.open();
            }

            return validIds;
        } catch (error) {
            console.error('Error fetching Bib IDs from Ids', error);
            this.fail.dialogBody = error.toString();
            this.fail.open();
            return [];
        }
    }

    private async addToBuckets(bibIds: number[]): Promise<void> {
        if (bibIds.length === 0) {
            this.importDisabled = true;
            return;
        }
        for (const bucket of this.containerObjects) {
            // eslint-disable-next-line no-await-in-loop
            await this.addRecordsToBucket(bucket.id, bibIds);
        }
    }

    private async addRecordsToBucket(bucketId: number, bibIds: number[]): Promise<void> {

        const entries = bibIds.map(bibId => {
            const entry = this.idl.create('cbrebi');
            entry.bucket(bucketId);
            entry.target_biblio_record_entry(bibId);
            return entry;
        });

        try {
            const resp = await firstValueFrom(this.net.request(
                'open-ils.actor',
                'open-ils.actor.container.item.create',
                this.auth.token(), 'biblio', entries
            ));
            console.debug('item.create, resp', resp);
            const evt = this.evt.parse(resp);
            if (evt) {
                this.fail.dialogBody = evt.toString();
                this.fail.open();
            } else {
                this.clearPastedValues(); // clear the pasted values only on success
            }
        } catch (error) {
            console.error('Error adding records to bucket', error);
            try { this.fail.dialogBody = error.toString(); } catch(E) { console.error(E); this.fail.dialogBody = $localize`See the developer tools console for the specific error.`; }
            try { this.fail.open(); } catch(E) { console.error(E); }
        }
        this.selectedFile = null; // clear the uploaded file in all cases
        this.importDisabled = !this.isImportAllowed();
    }
}
