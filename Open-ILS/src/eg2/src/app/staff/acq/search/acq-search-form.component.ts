import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter, ViewChild,
        OnChanges, SimpleChanges} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {StaffCommonModule} from '@eg/staff/common.module';
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

export class AcqSearchFormComponent implements OnInit, AfterViewInit, OnChanges {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];
    @Input() fallbackSearchTerms: AcqSearchTerm[] = [];
    @Input() defaultSearchSetting = '';
    @Input() runImmediatelySetting = '';
    @Input() searchTypeLabel = '';

    @Output() searchSubmitted = new EventEmitter<AcqSearch>();

    @ViewChild('defaultSearchSavedString', { static: true}) defaultSearchSavedString: StringComponent;
    @ViewChild('defaultSearchResetString', { static: true}) defaultSearchResetString: StringComponent;

    showForm = true;

    hints = ['jub', 'acqpl', 'acqpo', 'acqinv', 'acqlid'];
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

    searchTerms: AcqSearchTerm[] = [];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private store: ServerStoreService,
        private idl: IdlService,
        private toast: ToastService,
    ) {}

    ngOnInit() {
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
                                    self.searchFieldLinkedClasses[hint + ':' + field.name] = field.class;
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
                        } else if (this.fallbackSearchTerms.length) {
                            this.searchTerms.length = 0;
                            JSON.parse(JSON.stringify(this.fallbackSearchTerms))
                                .forEach(term => this.searchTerms.push(term)); // need a copy
                        } else {
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

    ngAfterViewInit() {}

    ngOnChanges(changes: SimpleChanges) {
        if ('initialSearchTerms' in changes && !changes.initialSearchTerms.firstChange) {
            this.ngOnInit();
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
    saveRunImmediately() {
        return this.store.setItem(this.runImmediatelySetting, this.runImmediately);
    }
}
