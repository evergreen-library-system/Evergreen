/* eslint-disable */
import {Component, OnInit, Input, Output, EventEmitter, ViewChild,
    OnChanges, SimpleChanges} from '@angular/core';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AcqSearchTerm, AcqSearch} from './acq-search.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Component({
    selector: 'eg-acq-search-form',
    styleUrls: ['acq-search-form.component.css'],
    templateUrl: './acq-search-form.component.html'
})

export class AcqSearchFormComponent implements OnInit, OnChanges {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];
    @Input() fallbackSearchTerms: AcqSearchTerm[] = [];
    @Input() defaultSearchSetting = '';
    @Input() runImmediatelySetting = '';
    @Input() filterToInvoiceableSetting = '';
    @Input() keepResultsSetting = '';
    @Input() trimListSetting = '';
    @Input() invoice: IdlObject;
    @Input() providerId: string;
    @Input() searchTypeLabel = '';
    @Input() searchContext = ''; // only used to *ngIf some widgets

    @Output() searchSubmitted = new EventEmitter<AcqSearch>();
    @Output() keepResultsChange: EventEmitter<boolean> = new EventEmitter();
    @Output() trimListChange: EventEmitter<boolean> = new EventEmitter();

    onKeepResultsChange(value: boolean) {
        console.debug('AcqSearchFormComponent, onKeepResultsChange', value);
        this.keepResultsChange.emit(value);
    }
    onTrimListChange(value: boolean) {
        console.debug('AcqSearchFormComponent, onTrimListChange', value);
        this.trimListChange.emit(value);
    }

    @ViewChild('defaultSearchSavedString', { static: true}) defaultSearchSavedString: StringComponent;
    @ViewChild('defaultSearchResetString', { static: true}) defaultSearchResetString: StringComponent;

    showForm = true;

    hints = ['jub', 'acqpl', 'acqpo', 'acqinv', 'acqlid', 'acqlisumi'];
    availableSearchFields = {};
    dateLikeSearchFields = {};
    searchTermDatatypes = {};
    searchTermFieldIsRequired = {};
    searchFieldLinkedClasses = {};
    validSearchTypes = ['lineitems', 'purchaseorders', 'invoices', 'selectionlists'];
    defaultSearchType = 'lineitems';
    searchConjunction = 'all';
    runImmediately = false;
    hasDefaultSearch = false;
    filterToInvoiceable = false;
    keepResults = false;
    trimList = false;

    searchTerms: AcqSearchTerm[] = [];

    constructor(
        private pcrud: PcrudService,
        private store: ServerStoreService,
        private idl: IdlService,
        private toast: ToastService
    ) {}

    loadRunImmediatelySettingAndMaybeRun() {
        const self = this;
        this.store.getItem(this.runImmediatelySetting).then(val => {
            this.runImmediately = val;

            this.hints.forEach(
                function(hint) {
                    const o = {};
                    o['__label'] = self.idl.classes[hint].label;
                    o['__fields'] = [];
                    self.idl.classes[hint].fields.forEach(
                        function(field) {
                            if (!field.virtual) {
                                o['__fields'].push(field.name);
                                o[field.name] = {
                                    label: field.label,
                                    datatype: field.datatype
                                };
                                self.searchTermDatatypes[hint + ':' + field.name] = field.datatype;
                                self.searchTermFieldIsRequired[hint + ':' + field.name] = field.required;
                                if (field.datatype === 'link') {
                                    if ((hint === 'jub' && field.name === 'eg_bib_id') ||
                                        (hint === 'acqlid' && field.name === 'eg_copy_id')) {
                                        // special exception for eg_bib_id and eg_copy_id, which
                                        // shouldn't get comboboxes on the search form
                                        self.searchTermDatatypes[hint + ':' + field.name] = 'int';
                                    } else {
                                        self.searchFieldLinkedClasses[hint + ':' + field.name] = field.class;
                                    }
                                }
                            }
                        }
                    );
                    self.availableSearchFields[hint] = o;
                }
            );

            this.hints.push('acqlia');
            this.availableSearchFields['acqlia'] = {'__label': this.idl.classes.acqlia.label, '__fields': []};
            this.pcrud.retrieveAll('acqliad', {'order_by': {'acqliad': 'id'}})
                .subscribe(liad => {
                    this.availableSearchFields['acqlia']['__fields'].push('' + liad.id());
                    this.availableSearchFields['acqlia'][liad.id()] = {
                        label: liad.description(),
                        datatype: 'text'
                    };
                    this.searchTermDatatypes['acqlia:' + liad.id()] = 'text';
                    if (liad.code().match(/date/)) {
                        this.dateLikeSearchFields['acqlia:' + liad.id()] = true;
                    }
                });

            if (this.initialSearchTerms.length > 0) {
                this.searchTerms = JSON.parse(JSON.stringify(this.initialSearchTerms)); // deep copy
                this.submitSearch(); // if we've been passed an initial search, e.g., via a URL, assume
                // we want the results immediately regardless of the workstation
                // setting
            } else {
                this.store.getItem(this.defaultSearchSetting).then(
                    defaultSearch => {
                        if (defaultSearch) {
                            this.searchTerms = JSON.parse(JSON.stringify(defaultSearch.terms));
                            this.searchConjunction = defaultSearch.conjunction;
                            this.hasDefaultSearch = true;
                            this.maybeAddInvoiceableItemTerms(this.filterToInvoiceable);
                        } else if (this.fallbackSearchTerms.length) {
                            this.searchTerms.length = 0;
                            JSON.parse(JSON.stringify(this.fallbackSearchTerms))
                                .forEach(term => this.searchTerms.push(term)); // need a copy
                            this.maybeAddInvoiceableItemTerms(this.filterToInvoiceable);
                        } else {
                            this.maybeAddInvoiceableItemTerms(this.filterToInvoiceable);
                            this.addSearchTerm();
                        }
                        if (this.runImmediately) {
                            if ((this.searchTerms.length > 0) &&
                                (this.searchTerms[0].field !== '')) {
                                this.submitSearch();
                            }
                        }
                    }
                );
            }
        });
    }

    ngOnInit() {
        console.warn('AcqSearchFormComponent, this', this);

        if (this.searchContext === 'InvoiceEmbeddedLineitem') {
            this.store.getItemBatch([
                this.filterToInvoiceableSetting,
                this.keepResultsSetting,
                this.trimListSetting,
            ]).then(settings => {
                console.debug('AcqSearchFormComponent, store.getItemBatch', settings);

                this.filterToInvoiceable = settings[this.filterToInvoiceableSetting] || false;
                this.keepResults = settings[this.keepResultsSetting] || false;
                this.trimList = settings[this.trimListSetting] || false;

                console.debug('AcqSearchFormComponent, filterToInvoiceable, keepResults, trimList',
                    this.filterToInvoiceable, this.keepResults, this.trimList);
                this.onKeepResultsChange(this.keepResults);
                this.onTrimListChange(this.trimList);
                // this will be handled by LineitemResultsComponent in this context:
                //   this.loadRunImmediatelySettingAndMaybeRun();
            });
        } else {
            this.loadRunImmediatelySettingAndMaybeRun();
        }
    }

    ngOnChanges(changes: SimpleChanges) {
        if ('initialSearchTerms' in changes && !changes.initialSearchTerms.firstChange) {
            this.ngOnInit();
        }
    }

    filterOutTheseLiIds(liIds: number[]) {
        // example: {field: 'jub:id', op: '__not', value1: '1', value2: '', is_date: false}
        const newTerms = liIds.map(liId => ({
            field: 'jub:id',
            op: '__not',
            value1: liId.toString(),
            value2: '',
            is_date: false
        }));
        newTerms.forEach(newTerm => {
            // Check if term already exists in array
            const termExists = this.searchTerms.some(
                existingTerm => JSON.stringify(existingTerm) === JSON.stringify(newTerm));

            // Only add term if it does not exist
            if (!termExists) {
                this.searchTerms.unshift(newTerm);
            }
        });
    }

    maybeAddInvoiceableItemTerms(newValue) {
        if (newValue) {
            const newTerms = [
                { 'field': 'jub:state', 'op': '__not',
                    'value1': 'cancelled', 'value2': '', 'is_date': false },
                { 'field': 'acqlisumi:item_count', 'op':'__gte',
                    'value1': '1', 'value2': '', 'is_date': false },
            ];
            if (this.invoice && !this.invoice.isnew()) {
                newTerms.push(
                    { 'field': 'acqinv:id', 'op': '__not',
                        'value1': this.invoice.id(), 'value2': '', 'is_date': false }
                );
            }
            if (this.providerId) {
                newTerms.push(
                    { 'field': 'jub:provider', 'op': '',
                        'value1': this.providerId, 'value2': '', 'is_date': false }
                );
            }

            newTerms.forEach(newTerm => {
                // Check if term already exists in array
                const termExists = this.searchTerms.some(
                    existingTerm => JSON.stringify(existingTerm) === JSON.stringify(newTerm));

                // Only add term if it does not exist
                if (!termExists) {
                    this.searchTerms.unshift(newTerm);
                }
            });

            // if (dojo.byId('acq-invoice-search-limit-invoiceable').checked) {
            //    if (!searchObject.jub)
            //        searchObject.jub = [];
            //
            //    // exclude lineitems that are "cancelled" (sidebar: 'Mericans spell it 'canceled')
            //    searchObject.jub.push({state : 'cancelled', '__not' : true});
            //
            //    // exclude lineitems already linked to this invoice
            //    if (invoice && invoice.id() > 0) {
            //        if (!searchObject.acqinv)
            //            searchObject.acqinv = [];
            //        searchObject.acqinv.push({id : invoice.id(), '__not' : true});
            //    }
            //
            //    // limit to lineitems that have invoiceable copies
            //    searchObject.acqlisumi = [{item_count : 1, '_gte' : true}];
            //
            //    // limit to provider if a provider is selected
            //    var provider = invoicePane.getFieldValue('provider');
            //    if (provider) {
            //        if (!searchObject.jub.filter(function(i) { return i.provider != null }).length)
            //            searchObject.jub.push({provider : provider});
            //    }
            // }
        }
    }

    addSearchTerm() {
        this.searchTerms.push({ field: '', op: '', value1: '', value2: '' });
    }
    delSearchTerm(index: number) {
        if (this.searchTerms.length < 2) {
            this.clearSearchTerm(this.searchTerms[0]);
            // special case for org_unit
            if (this.searchTerms[0].field && this.searchTermDatatypes[this.searchTerms[0].field] === 'org_unit') {
                this.searchTerms = [{ field: this.searchTerms[0].field, op: this.searchTerms[0].op, value1: '', value2: ''}];
            }
            // and timestamps
            if (this.searchTerms[0].field && this.searchTermDatatypes[this.searchTerms[0].field] === 'timestamp') {
                this.searchTerms = [{ field: this.searchTerms[0].field, op: this.searchTerms[0].op, value1: '', value2: ''}];
            }
        } else {
            this.searchTerms.splice(index, 1);
        }
    }
    clearSearchTerm(term: AcqSearchTerm, old?) {
        // work around fact that org selector doesn't implement ngModel
        // and we don't use it for eg-date-select
        if (old && this.searchTermDatatypes[old] === this.searchTermDatatypes[term.field] &&
            (this.searchTermDatatypes[old] === 'org_unit' || this.searchTermDatatypes[old] === 'timestamp')) {
            // don't change values if we're moving from one
            // org_unit or timestamp field to another
        } else {
            term.value1 = '';
            term.value2 = '';
            term.is_date = false;
        }

        // handle change of field type
        if (old && this.searchTermDatatypes[old] !== this.searchTermDatatypes[term.field]) {
            term.op = '';
        }
        if (old && this.searchTermDatatypes[old] === this.searchTermDatatypes[term.field] &&
            this.searchTermDatatypes[term.field] === 'link' &&
            (this.searchFieldLinkedClasses[old] !== this.searchFieldLinkedClasses[term.field])
        ) {
            term.op = '';
        }
        if (term.field.startsWith('acqlia:') && term.op === '') {
            // default operator for line item attributes should be "contains"
            term.op = '__fuzzy';
        } else if (this.searchTermDatatypes[term.field] !== 'text' && term.op.endsWith('__fuzzy')) {
            // avoid trying to use the "contains" operator for non-text fields
            term.op = '';
        }
    }
    // conditionally clear the search term after changing
    // to selected search operators
    clearSearchTermValueAfterOpChange(term: AcqSearchTerm, oldOp?) {
        if (term.op === '__age') {
            term.value1 = '';
            term.value2 = '';
        }
        if (this.searchTermDatatypes[term.field] === 'link') {
            if (oldOp === '__fuzzy' || term.op === '__fuzzy' ||
                oldOp === '__not,__fuzzy' || term.op === '__not,__fuzzy'
            ) {
                term.value1 = '';
                term.value2 = '';
            }
        }
    }

    setOrgUnitSearchValue(org: IdlObject, term: AcqSearchTerm) {
        // eslint-disable-next-line eqeqeq
        if (org == null) {
            term.value1 = '';
        } else {
            term.value1 = org.id();
        }
    }

    submitSearch() {
        // tossing setTimeout here to ensure that the
        // grid data source is fully initialized
        setTimeout(() => {
            console.warn('AcqSearchFormComponent, terms and conjunction',
                this.searchTerms, this.searchConjunction);
            this.searchSubmitted.emit({
                terms: this.searchTerms,
                conjunction: this.searchConjunction
            });
        });
    }

    saveSearchAsDefault() {
        return this.store.setItem(this.defaultSearchSetting, {
            terms: this.searchTerms,
            conjunction: this.searchConjunction
        }).then(() => {
            this.hasDefaultSearch = true;
            this.defaultSearchSavedString.current().then(msg =>
                this.toast.success(msg)
            );
        });
    }
    clearDefaultSearch() {
        return this.store.removeItem(this.defaultSearchSetting).then(() => {
            this.hasDefaultSearch = false;
            this.defaultSearchResetString.current().then(msg =>
                this.toast.success(msg)
            );
        });
    }
    saveRunImmediately(newValue) {
        console.debug('AcqSearchFormComponent, saveRunImmediately',this.runImmediatelySetting, newValue);
        return this.store.setItem(this.runImmediatelySetting, newValue);
    }
    saveFilterToInvoiceable(newValue) {
        console.debug('AcqSearchFormComponent, saveFilterToInvoiceable',this.filterToInvoiceableSetting, newValue);
        return this.store.setItem(this.filterToInvoiceableSetting, newValue);
    }
    saveTrimList(newValue) {
        console.debug('AcqSearchFormComponent, saveTrimList',this.trimListSetting, newValue);
        return this.store.setItem(this.trimListSetting, newValue);
    }
    saveKeepResults(newValue) {
        console.debug('AcqSearchFormComponent, saveKeepResults',this.keepResultsSetting, newValue);
        return this.store.setItem(this.keepResultsSetting, newValue);
    }
}
