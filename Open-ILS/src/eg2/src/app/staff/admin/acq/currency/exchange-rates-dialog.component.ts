import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {PermService} from '@eg/core/perm.service';

@Component({
    selector: 'eg-exchange-rates-dialog',
    templateUrl: './exchange-rates-dialog.component.html'
})

export class ExchangeRatesDialogComponent
    extends DialogComponent implements OnInit {

    @Input() currencyCode: string;
    currency: IdlObject;
    otherCurrencies: IdlObject[];
    existingRatios: {[toCurrency: string]: IdlObject} = {};
    existingInverseRatios: {[fromCurrency: string]: IdlObject} = {};
    ratios: IdlObject[];
    idlDef: any;
    fieldOrder: any;
    canUpdate = false;
    doneLoading = false;

    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;

    constructor(
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private perm: PermService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
    }

    ngOnInit() {
        this.currency = null;
        this.onOpen$.subscribe(() => this._initRecord());
        this.idlDef = this.idl.classes['acqct'];
        this.perm.hasWorkPermAt(['ADMIN_CURRENCY_TYPE'], true).then((perm) => {
            if (perm['ADMIN_CURRENCY_TYPE'].length > 0) {
                this.canUpdate = true;
            }
        });
    }

    private _initRecord() {
        this.doneLoading = false;
        this.ratios = [];
        this.otherCurrencies = [];
        this.existingRatios = {};
        this.existingInverseRatios = {};
        this.pcrud.retrieve('acqct', this.currencyCode, {}
        ).subscribe(res => this.currency = res);
        this.pcrud.search('acqexr', { from_currency: this.currencyCode }, {
            flesh: 1,
            flesh_fields: {'acqexr': ['to_currency']},
        }, {}).subscribe({
            next: exr => this.existingRatios[exr.to_currency().code()] = exr,
            error: (err: unknown) => {},
            complete: () => this.pcrud.search('acqexr', { to_currency: this.currencyCode }, {
                flesh: 1,
                flesh_fields: {'acqexr': ['from_currency']},
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
            }, {}).subscribe({
                next: exr => this.existingInverseRatios[exr.from_currency().code()] = exr,
                error: (err: unknown) => {},
                complete: () =>  this.pcrud.search('acqct', { code: { '!=': this.currencyCode } },
                    { order_by: 'code ASC' }, { atomic: true })
                // eslint-disable-next-line rxjs-x/no-nested-subscribe
                    .subscribe({
                        next: currs => this.otherCurrencies = currs,
                        error: (err: unknown) => {},
                        complete: () => { this._mergeCurrenciesAndRates(); this.doneLoading = true; } }
                    ) }
            ) }
        );
    }

    private _mergeCurrenciesAndRates() {
        this.ratios = [];
        this.otherCurrencies.forEach(curr => {
            if (curr.code() in this.existingRatios) {
                this.ratios.push(this.existingRatios[curr.code()]);
            } else if (curr.code() in this.existingInverseRatios) {
                const ratio = this.idl.clone(this.existingInverseRatios[curr.code()]);
                // mark it as an inverse ratio that should not be directly edited
                ratio.id(-1);
                const toCur = ratio.to_currency();
                ratio.to_currency(ratio.from_currency());
                ratio.from_currency(toCur);
                ratio.ratio(1.0 / ratio.ratio());
                this.ratios.push(ratio);
            } else {
                const ratio = this.idl.create('acqexr');
                ratio.from_currency(this.currencyCode);
                ratio.to_currency(curr);
                this.ratios.push(ratio);
            }
        });
        this.ratios.sort((a, b) => {
            return a.to_currency().code() < b.to_currency().code() ? -1 : 1;
        });
    }

    save() {
        const updateBatch: IdlObject[] = [];
        this.ratios.forEach(ratio => {
            if (ratio.id() === -1) {
                // ignore inverse entries
            } else if (ratio.id() === undefined && ratio.ratio() !== undefined && ratio.ratio() !== null) {
                // completely new entry
                ratio.isnew(true);
                updateBatch.push(ratio);
            } else if (ratio.id() !== undefined && ratio.ratio() !== undefined && ratio.ratio() !== null) {
                // entry that might have been updated
                ratio.ischanged(true);
                updateBatch.push(ratio);
            } else if (ratio.id() !== undefined && (ratio.ratio() === undefined || ratio.ratio() === null)) {
                // existing entry to delete
                ratio.isdeleted(true);
                updateBatch.push(ratio);
            }
        });
        this.pcrud.autoApply(updateBatch).toPromise().then(res => this.close(res));
    }

}
