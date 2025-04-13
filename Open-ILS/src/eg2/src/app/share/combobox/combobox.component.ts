/* eslint-disable */
/* eslint-disable no-case-declarations */
/**
 * <eg-combobox [allowFreeText]="true" [entries]="comboboxEntryList"/>
 *  <!-- see also <eg-combobox-entry> -->
 * </eg-combobox>
 */
import {Component, OnInit, Input, Output, ViewChild,
    Directive, ViewChildren, QueryList, AfterViewInit,
    OnChanges, SimpleChanges,
    TemplateRef, EventEmitter, ElementRef, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';
import {EMPTY, Observable, of, Subject} from 'rxjs';
import {map, mergeMap, mapTo, debounceTime, distinctUntilChanged, merge, filter, mergeWith} from 'rxjs/operators';
import {NgbTypeahead, NgbTypeaheadSelectItemEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';

export interface ComboboxEntry {
  id: any;
  // If no label is provided, the 'id' value is used.
  label?: string;
  freetext?: boolean;
  userdata?: any; // opaque external value; ignored by this component.
  fm?: IdlObject;
  disabled?: boolean;
  class?: any;  // any valid ngClass value
}

@Directive({
    selector: 'ng-template[egIdlClass]'
})
export class IdlClassTemplateDirective {
  @Input() egIdlClass: string;
  constructor(public template: TemplateRef<any>) {}
}

@Component({
    selector: 'eg-combobox',
    templateUrl: './combobox.component.html',
    styles: [`
    .icons {margin-left:-18px}
    .material-icons {font-size: 16px;font-weight:bold}
  `],
    providers: [{
        provide: NG_VALUE_ACCESSOR,
        useExisting: forwardRef(() => ComboboxComponent),
        multi: true
    }]
})
export class ComboboxComponent
implements ControlValueAccessor, OnInit, AfterViewInit, OnChanges {

    static domIdAuto = 0;

    selected: ComboboxEntry;
    click$: Subject<string>;
    entrylist: ComboboxEntry[];

    @ViewChild('instance', {static: false}) instance: NgbTypeahead;
    @ViewChild('defaultDisplayTemplate', {static: true}) defaultDisplayTemplate: TemplateRef<any>;
    @ViewChildren(IdlClassTemplateDirective) idlClassTemplates: QueryList<IdlClassTemplateDirective>;

    @Input() domId = 'eg-combobox-' + ComboboxComponent.domIdAuto++;
    @Input() tabindex = null;

    // Applies a name attribute to the input.
    // Useful in forms.
    @Input() name: string;

    @Input() ariaLabel?: string = null;

    // Placeholder text for selector input
    @Input() placeholder = '';

    @Input() persistKey: string; // TODO

    @Input() allowFreeText = false;
    @Input() labelTrim = true;

    @Input() inputSize?: number = null;
    @Input() maxLength?: number = null;

    // If true, applies form-control-sm CSS
    @Input() smallFormControl = false;

    // space-separated list of additional CSS classes to append
    @Input() moreClasses: string;

    // If false, omits the up/down arrow icons
    @Input() icons = true;

    // If true, the typeahead only matches values that start with
    // the value typed as opposed to a 'contains' match.
    @Input() startsWith = false;

    @Input() clearOnAsync = false;
    @Input() isEditable = true;
    @Input() selectOnExact = false;

    // Add a 'required' attribute to the input
    isRequired: boolean;
    @Input() set required(r: boolean) {
        this.isRequired = r;
    }
    // and a 'mandatory' synonym, as an issue
    // has been observed in at least Firefox 88.0.1
    // where the left border indicating whether a required
    // value has been set or not is displayed in the
    // container of the combobox, not just the dropdown
    @Input() set mandatory(r: boolean) {
        this.isRequired = r;
    }

    // Array of entry identifiers to disable in the selector
    @Input() disableEntries: any[] = [];

    // Disable the input
    isDisabled: boolean;
    @Input() set disabled(d: boolean) {
        this.isDisabled = d;
    }

    // Entry ID of the default entry to select (optional)
    // onChange() is NOT fired when applying the default value,
    // unless startIdFiresOnChange is set to true.
    @Input() startId: any = null;
    @Input() idlClass: string;
    @Input() idlBaseQuery: any = null;
    @Input() startIdFiresOnChange: boolean;

    @Input() searchInId = false;

    // If provided, the default pcrud-based async data source
    // will also add an entry with an ID of null and this label.
    // Be sure to mark it for translation.
    @Input() unsetString: string;

    // This will be appended to the async data retrieval query
    // when fetching objects by idlClass.
    @Input() idlQueryAnd: {[field: string]: any};

    @Input() idlQuerySort: {[cls: string]: string};

    // Display the selected value as text instead of within
    // the typeahead
    @Input() readOnly = false;

    @Input() focused = false;

    // Allow the selected entry ID to be passed via the template
    // This does NOT not emit onChange events.
    @Input() set selectedId(id: any) {
        if (id === undefined) {
            return;
        }

        // clear on explicit null
        if (id === null) {
            this.selected = null;
            return;
        }

        if (this.entrylist.length) {
            this.selected = this.entrylist.filter(e => e.id === id)[0];
        }

        if (!this.selected) {
            // It's possible the selected ID lives in a set of entries
            // that are yet to be provided.
            this.startId = id;
            if (this.idlClass) {
                this.pcrud.retrieve(this.idlClass, id)
                    .subscribe(rec => {
                        this.entrylist = [{
                            id: id,
                            label: this.getFmRecordLabel(rec),
                            fm: rec,
                            disabled : this.disableEntries.includes(id)
                        }];
                        this.selected = this.entrylist.filter(e => e.id === id)[0];
                    });
            }
        }
    }

    get selectedId(): any {
        return this.selected ? this.selected.id : null;
    }

    @Input() idlField: string;
    @Input() idlIncludeLibraryInLabel: string;
    @Input() asyncDataSource: (term: string) => Observable<ComboboxEntry>;

    // If true, an async data search is allowed to fetch all
    // values when given an empty term. This should be used only
    // if the maximum number of entries returned by the data source
    // is known to be no more than a couple hundred.
    @Input() asyncSupportsEmptyTermClick: boolean;

    // Useful for efficiently preventing duplicate async entries
    asyncIds: {[idx: string]: boolean};

    // True if a default selection has been made.
    defaultSelectionApplied: boolean;

    @Input() set entries(el: ComboboxEntry[]) {
        if (el) {

            if (this.entrylistMatches(el)) {
                // Avoid reprocessing data we already have.
                return;
            }

            this.entrylist = el;

            // new set of entries essentially means a new instance. reset.
            this.defaultSelectionApplied = false;
            this.applySelection();

            // It's possible to provide an entrylist at load time, but
            // fetch all future data via async data source.  Track the
            // values we already have so async lookup won't add them again.
            // A new entry list wipes out any existing async values.
            this.asyncIds = {};
            el.forEach(entry => this.asyncIds['' + entry.id] = true);
        }
    }

    // When provided use this as the display template for each entry.
    // To create a custom result format in a single component, add <ng-template> to
    // your component HTML and provide its TemplateRef using [displayTemplate]
    @Input() displayTemplate: TemplateRef<any>;

    // For propagating focus/blur events coming from the input element
    @Output() inputFocused: EventEmitter<void>;
    @Output() inputBlurred: EventEmitter<void>;

    // Optionally provide an aria-labelledby for the input.  This should be one or more
    // space-delimited ids of elements that describe this combobox.
    @Input() ariaLabelledby: string;

    // Emitted when the value is changed via UI.
    // When the UI value is cleared, null is emitted.
    @Output() onChange: EventEmitter<ComboboxEntry>;

    // set to "id" to use the result ID instead of the result label
    // as the inputFormatter display string
    @Input() inputFormatField = 'label';

    // Useful for massaging the match string prior to comparison
    // and display.  Default version trims leading/trailing spaces
    // from the result, unless ID is specified using inputFormatField.
    // Used as ngbTypeahead's inputFormatter directive.
    formatDisplayString: (e: ComboboxEntry) => string;

    idlDisplayTemplateMap: { [key: string]: TemplateRef<any> } = {};
    getFmRecordLabel: (fm: IdlObject) => string;

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    constructor(
      private elm: ElementRef,
      private idl: IdlService,
      private pcrud: PcrudService,
      private org: OrgService,
    ) {
        this.entrylist = [];
        this.asyncIds = {};
        this.click$ = new Subject<string>();
        this.onChange = new EventEmitter<ComboboxEntry>();
        this.defaultSelectionApplied = false;

        this.inputFocused = new EventEmitter<void>();
        this.inputBlurred = new EventEmitter<void>();

        // determines how selected items display in the <input>, if different from result
        this.formatDisplayString = (result: ComboboxEntry) => {
            //console.debug('formatDisplayString result (input):', result);
            const displayField = this.inputFormatField || 'label';

            // trim the result string
            const display = result[displayField] || result.id;
            //console.debug('formatDisplayString display (output):', result);
            if (!this.labelTrim) {return (display + '');}
            return (display + '').trim();
        };

        this.getFmRecordLabel = (fm: IdlObject) => {
            // FIXME: it would be cleaner if we could somehow use
            // the per-IDL-class ng-templates directly
            switch (this.idlClass) {
                case 'acmc':
                    return fm.course_number() + ': ' + fm.name();
                case 'acqf':
                    return fm.code() + ' (' + fm.year() + ')' +
                           ' (' + this.getOrgShortname(fm.org()) + ')';
                case 'acpl':
                    return fm.name() + ' (' + this.getOrgShortname(fm.owning_lib()) + ')';
                    break;
                case 'acqpro':
                    return fm.code() + ' (' + this.getOrgShortname(fm.owner()) + ')';
                    break;
                default:
                    const field = this.idlField;
                    if (this.idlIncludeLibraryInLabel) {
                        return fm[field]() + ' (' + this.getOrgShortname(fm[this.idlIncludeLibraryInLabel]()) + ')';
                    } else {
                        return fm[field]();
                    }
            }
        };
    }

    ngOnInit() {

        // Make [allowFreeText] a master ON switch for ngbTypeahead
        // [editable], otherwise we don't get onChange for
        // selectorChanged propagation
        if (!this.isEditable && this.allowFreeText) {
            this.isEditable = this.allowFreeText
        }

        if (this.idlClass) {
            const classDef = this.idl.classes[this.idlClass];
            const pkeyField = classDef.pkey;

            if (!pkeyField) {
                throw new Error(`IDL class ${this.idlClass} has no pkey field`);
            }

            if (!this.idlField) {
                this.idlField = this.idl.getClassSelector(this.idlClass);
            }

            this.asyncDataSource = term => {
                const field = this.idlField;
                let args = {};
                if (this.idlBaseQuery) {
                    args = this.idlBaseQuery;
                }
                const extra_args = { order_by : {} };
                if (this.startsWith) {
                    args[field] = {'ilike': `${term}%`};
                } else {
                    args[field] = {'ilike': `%${term}%`}; // could -or search on label
                }
                if (this.idlQueryAnd) {
                    Object.assign(args, this.idlQueryAnd);
                }
                if (this.idlQuerySort) {
                    extra_args['order_by'] = this.idlQuerySort;
                } else {
                    extra_args['order_by'][this.idlClass] = field;
                }
                extra_args['limit'] = 100;

                // If the unsetString is provided, emit a null entry
                const unsetOption$ = this.unsetString ? of({id: null, label: this.unsetString}) : EMPTY;
                if (this.idlIncludeLibraryInLabel) {
                    extra_args['flesh'] = 1;
                    const flesh_fields: Object = {};
                    flesh_fields[this.idlClass] = [ this.idlIncludeLibraryInLabel ];
                    extra_args['flesh_fields'] = flesh_fields;
                    return this.pcrud.search(this.idlClass, args, extra_args).pipe(map(data => {
                        return {
                            id: data[pkeyField](),
                            label: this.getFmRecordLabel(data),
                            fm: data
                        };
                    }), mergeWith(unsetOption$));
                } else {
                    return this.pcrud.search(this.idlClass, args, extra_args).pipe(map(data => {
                        return {id: data[pkeyField](), label: this.getFmRecordLabel(data), fm: data};
                    }), mergeWith(unsetOption$));
                }
            };
        }
    }

    ngAfterViewInit() {
        this.idlDisplayTemplateMap = this.idlClassTemplates.reduce((acc, cur) => {
            acc[cur.egIdlClass] = cur.template;
            return acc;
        }, {});
    }

    ngOnChanges(changes: SimpleChanges) {
        let firstTime = true;
        Object.keys(changes).forEach(key => {
            if (!changes[key].firstChange) {
                firstTime = false;
            }
        });
        if (!firstTime) {
            if ('selectedId' in changes) {
                if (!changes.selectedId.currentValue) {

                    // In allowFreeText mode, selectedId will be null even
                    // though a freetext value may be present in the combobox.
                    if (this.allowFreeText) {
                        if (this.selected && !this.selected.freetext) {
                            this.selected = null;
                        }
                    } else {
                        this.selected = null;
                    }
                }
            }
            if ('idlClass' in changes) {
                if (!('idlField' in changes)) {
                    // let ngOnInit reset it to the
                    // selector of the new IDL class
                    this.idlField = null;
                }
                this.asyncIds = {};
                this.entrylist.length = 0;
                this.selected = null;
                this.ngOnInit();
            }
            if ('idlQueryAnd' in changes) {
                this.asyncIds = {};
                this.entrylist.length = 0;
                this.selected = null;
                this.ngOnInit();
            }
        }
    }

    onClick($event) {
        this.click$.next($event.target.value);
    }

    getResultTemplate(): TemplateRef<any> {
        if (this.displayTemplate) {
            return this.displayTemplate;
        }
        if (this.idlClass in this.idlDisplayTemplateMap) {
            return this.idlDisplayTemplateMap[this.idlClass];
        }
        return this.defaultDisplayTemplate;
    }

    getOrgShortname(ou: any) {
        if (typeof ou === 'object') {
            return ou.shortname();
        } else {
            return this.org.get(ou).shortname();
        }
    }

    openMe($event) {
        // Give the input a chance to focus then fire the click
        // handler to force open the typeahead
        this.elm.nativeElement.getElementsByTagName('input')[0].focus();
        setTimeout(() => this.click$.next(''));
    }

    closeMe($event) {
        this.instance.dismissPopup();
    }

    // Returns true if the 2 entries are equivalent.
    entriesMatch(e1: ComboboxEntry, e2: ComboboxEntry): boolean {
        return (
            e1 && e2 &&
            e1.id === e2.id &&
            e1.label === e2.label &&
            e1.freetext === e2.freetext
        );
    }

    // Returns true if the 2 lists are equivalent.
    entrylistMatches(el: ComboboxEntry[]): boolean {
        if (el.length === 0 && this.entrylist.length === 0) {
            // Empty arrays are only equivalent if they are the same array,
            // since the caller may provide an array that starts empty, but
            // is later populated.
            return el === this.entrylist;
        }
        if (el.length !== this.entrylist.length) {
            return false;
        }
        for (let i = 0; i < el.length; i++) {
            const mine = this.entrylist[i];
            if (!mine || !this.entriesMatch(mine, el[i])) {
                return false;
            }
        }
        return true;
    }

    // Apply a default selection where needed
    applySelection() {

        if (this.entrylist && !this.defaultSelectionApplied) {

            const entry =
                this.entrylist.filter(e => e.id === this.startId)[0];

            if (entry) {
                this.selected = entry;
                this.defaultSelectionApplied = true;
                if (this.startIdFiresOnChange) {
                    this.selectorChanged(
                        {item: this.selected, preventDefault: () => true});
                }
            }
        }
    }

    // Called by combobox-entry.component
    addEntry(entry: ComboboxEntry) {
        if (entry.disabled) {
            if (!this.disableEntries.find(e => e === entry.id)) {
                this.disableEntries.push(entry.id);
            }
        }
        this.entrylist.push(entry);
        this.applySelection();
    }

    // I don't think we have anything enforcing unique id's here, so We could
    // conceivably have multiple entries with the same id but different labels.
    // Thus, check both together as a composite key.
    isDuplicateEntry(entry: ComboboxEntry) {
        return this.entrylist.some(e =>
            e.id === entry.id &&
        e.label === entry.label
        );
    }

    // Manually set the selected value by ID.
    // This does NOT fire the onChange handler.
    // DEPRECATED: use this.selectedId = abc or [selectedId]="abc" instead.
    applyEntryId(entryId: any) {
        this.selected = this.entrylist.filter(e => e.id === entryId)[0];
    }

    removeEntryById(entryId: string) {
        if (this.hasEntry(entryId)) {
            this.entrylist.splice(
                this.entrylist.findIndex(e => e.id === entryId),
                1
            );
        }
    }

    addAsyncEntry(entry: ComboboxEntry) {
        if (!entry) { return; }
        // Avoid duplicate async entries
        const old_label = this.entrylist.find(e => e.id === entry.id)?.label;
        const old_ud = this.entrylist.find(e => e.id === entry.id)?.userdata;
        const old_fm = this.entrylist.find(e => e.id === entry.id)?.fm;
        if (!this.asyncIds['' + entry.id]) { // no matchin async id recorded
            this.asyncIds['' + entry.id] = true;
            this.addEntry(entry);
        } else if (old_label !== entry?.label
                || old_ud !== entry?.userdata
                || old_fm !== entry?.fm) { // something is different, replace it
            this.removeEntryById(entry.id);
            this.asyncIds['' + entry.id] = true;
            this.addEntry(entry);
        }
    }

    hasEntry(entryId: any): boolean {
        return this.entrylist.filter(e => e.id === entryId)[0] !== undefined;
    }

    onFocus($event) {
        this.focused = true;
        this.inputFocused.emit();
        $event.preventDefault();
        //console.debug('onFocus: ', $event);
    }

    onBlur($event) {
        this.focused = false;

        //console.debug('onBlur selected started as: ', this.selected);
        // When the selected value is a string it means we have either
        // no value (user cleared the input) or a free-text value.

        if (typeof this.selected === 'string') {

            if (this.allowFreeText && this.selected !== '') {
                const freeText = this.entrylist.filter(e => e.id === null)[0];

                if (freeText) {

                    // If we already had a free text entry, just replace
                    // the label with the new value
                    freeText.label = this.selected;
                    this.selected = freeText;

                }  else {

                    // Free text entered which does not match a known entry
                    // translate it into a dummy ComboboxEntry
                    this.selected = {
                        id: null,
                        label: this.selected,
                        freetext: true
                    };
                }

                if (this.inputFormatField) {
                    this.selected[this.inputFormatField] = this.selected.label;
                }

            } else {

                this.selected = null;
            }

            // Manually fire the onchange since NgbTypeahead fails
            // to fire the onchange when the value is cleared.
            this.selectorChanged(
                {item: this.selected, preventDefault: () => true});
        }
        this.inputBlurred.emit();
        //console.debug('onBlur selected is now: ', this.selected);
        this.propagateTouch();
    }

    // Fired by the typeahead to inform us of a change.
    selectorChanged(selEvent: NgbTypeaheadSelectItemEvent) {
        // selEvent.preventDefault();
        this.onChange.emit(selEvent.item);
        this.propagateChange(selEvent.item);
        //console.debug('selectorChanged: ', selEvent);
    }

    // Adds matching async entries to the entry list
    // and propagates the search term for pipelining.
    addAsyncEntries(term: string): Observable<string> {

        if (!term || !this.asyncDataSource) {
            return of(term);
        }

        let searchTerm = term;
        if (term === '_CLICK_') {
            if (this.asyncSupportsEmptyTermClick) {
                // Search for "all", but retain and propage the _CLICK_
                // term so the filter knows to open the selector
                searchTerm = '';
            } else {
                // Skip the final filter map and display nothing.
                return of();
            }
        }

        if (this.clearOnAsync) {
            this.asyncIds = {};
            this.entrylist.length = 0;
            this.selected = null;
        }

        return new Observable(observer => {
            this.asyncDataSource(searchTerm).subscribe(
                (entry: ComboboxEntry) => this.addAsyncEntry(entry),
                (err: unknown) => {},
                ()  => {
                    observer.next(term);
                    observer.complete();
                }
            );
        });
    }

    // NgbTypeahead doesn't offer a way to style the dropdown
    // button directly, so we have to reach up and style it ourselves.
    applyDisableStyle() {
        this.disableEntries.forEach(id => {
            const node = document.getElementById(`${this.domId}-${id}`);
            if (node) {
                const button = node.parentNode as HTMLElement;
                button.classList.add('disabled');
            }
        });
    }

    filter = (text$: Observable<string>): Observable<ComboboxEntry[]> => {
        return text$.pipe(
            // eslint-disable-next-line no-magic-numbers
            debounceTime(200),
            distinctUntilChanged(),

            // Merge click actions in with the stream of text entry
            merge(
                // Inject a specifier indicating the source of the
                // action is a user click instead of a text entry.
                // This tells the filter to show all values in sync mode.
                this.click$.pipe(filter(() =>
                    !this.instance.isPopupOpen()
                )).pipe(mapTo('_CLICK_'))
            ),

            // mergeMap coalesces an observable into our stream.
            mergeMap(term => this.addAsyncEntries(term)),

            map((term: string) => {

                // Display no values when the input is empty and no
                // click action occurred.
                if (term === '') { return []; }

                // If we make it this far, _CLICK_ means show everything.
                if (term === '_CLICK_') { term = ''; }

                // Give the typeahead a chance to open before applying
                // the disabled entry styling.
                setTimeout(() => this.applyDisableStyle());

                // Filter entrylist whose labels substring-match the
                // text entered.
                return this.entrylist.filter(entry => {
                    const label = String(entry.label);
                    const id = String(entry.id);

                    if (!label) { return false; }

                    if (this.startsWith) {
                        if (this.searchInId) {
                            if (id.toLowerCase().startsWith(term.toLowerCase())) {
                                return true;
                            }
                        }
                        return label.toLowerCase().startsWith(term.toLowerCase());
                    } else {
                        if (this.searchInId) {
                            if (id.toLowerCase().indexOf(term.toLowerCase()) > -1) {
                                return true;
                            }
                        }
                        return label.toLowerCase().indexOf(term.toLowerCase()) > -1;
                    }
                });
            })
        );
    };

    writeValue(value: ComboboxEntry) {
        //console.debug('writeValue: ', value);
        if (value !== undefined && value !== null) {
            this.selectedId = value.id;
            this.applySelection();
        }
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }

}


