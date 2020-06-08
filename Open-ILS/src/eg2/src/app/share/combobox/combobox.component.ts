/**
 * <eg-combobox [allowFreeText]="true" [entries]="comboboxEntryList"/>
 *  <!-- see also <eg-combobox-entry> -->
 * </eg-combobox>
 */
import {Component, OnInit, Input, Output, ViewChild,
    TemplateRef, EventEmitter, ElementRef, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';
import {Observable, of, Subject} from 'rxjs';
import {map, tap, reduce, mergeMap, mapTo, debounceTime, distinctUntilChanged, merge, filter} from 'rxjs/operators';
import {NgbTypeahead, NgbTypeaheadSelectItemEvent} from '@ng-bootstrap/ng-bootstrap';
import {StoreService} from '@eg/core/store.service';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';

export interface ComboboxEntry {
  id: any;
  // If no label is provided, the 'id' value is used.
  label?: string;
  freetext?: boolean;
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
export class ComboboxComponent implements ControlValueAccessor, OnInit {

    selected: ComboboxEntry;
    click$: Subject<string>;
    entrylist: ComboboxEntry[];

    @ViewChild('instance', { static: true }) instance: NgbTypeahead;

    // Applies a name attribute to the input.
    // Useful in forms.
    @Input() name: string;

    // Placeholder text for selector input
    @Input() placeholder = '';

    @Input() persistKey: string; // TODO

    @Input() allowFreeText = false;

    @Input() inputSize: number = null;

    // Add a 'required' attribute to the input
    isRequired: boolean;
    @Input() set required(r: boolean) {
        this.isRequired = r;
    }

    // Disable the input
    isDisabled: boolean;
    @Input() set disabled(d: boolean) {
        this.isDisabled = d;
    }

    // Entry ID of the default entry to select (optional)
    // onChange() is NOT fired when applying the default value,
    // unless startIdFiresOnChange is set to true.
    @Input() startId: any = null;
    @Input() startIdFiresOnChange: boolean;

    // Allow the selected entry ID to be passed via the template
    // This does NOT not emit onChange events.
    @Input() set selectedId(id: any) {
        if (id === undefined) { return; }

        // clear on explicit null
        if (id === null) { this.selected = null; }

        if (this.entrylist.length) {
            this.selected = this.entrylist.filter(e => e.id === id)[0];
        }

        if (!this.selected) {
            // It's possible the selected ID lives in a set of entries
            // that are yet to be provided.
            this.startId = id;
        }
    }

    get selectedId(): any {
        return this.selected ? this.selected.id : null;
    }

    @Input() idlClass: string;
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
    @Input() displayTemplate: TemplateRef<any>;

    // Emitted when the value is changed via UI.
    // When the UI value is cleared, null is emitted.
    @Output() onChange: EventEmitter<ComboboxEntry>;

    // Useful for massaging the match string prior to comparison
    // and display.  Default version trims leading/trailing spaces.
    formatDisplayString: (e: ComboboxEntry) => string;

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    constructor(
      private elm: ElementRef,
      private store: StoreService,
      private idl: IdlService,
      private pcrud: PcrudService,
    ) {
        this.entrylist = [];
        this.asyncIds = {};
        this.click$ = new Subject<string>();
        this.onChange = new EventEmitter<ComboboxEntry>();
        this.defaultSelectionApplied = false;

        this.formatDisplayString = (result: ComboboxEntry) => {
            const display = result.label || result.id;
            return (display + '').trim();
        };
    }

    ngOnInit() {
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
                const args = {};
                const extra_args = { order_by : {} };
                args[field] = {'ilike': `%${term}%`}; // could -or search on label
                extra_args['order_by'][this.idlClass] = field;
                if (this.idlIncludeLibraryInLabel) {
                    extra_args['flesh'] = 1;
                    const flesh_fields: Object = {};
                    flesh_fields[this.idlClass] = [ this.idlIncludeLibraryInLabel ];
                    extra_args['flesh_fields'] = flesh_fields;
                    return this.pcrud.search(this.idlClass, args, extra_args).pipe(map(data => {
                        return {
                            id: data[pkeyField](),
                            label: data[field]() + ' (' + data[this.idlIncludeLibraryInLabel]().shortname() + ')'
                        };
                    }));
                } else {
                    return this.pcrud.search(this.idlClass, args, extra_args).pipe(map(data => {
                        return {id: data[pkeyField](), label: data[field]()};
                    }));
                }
            };
        }
    }

    onClick($event) {
        this.click$.next($event.target.value);
    }

    openMe($event) {
        // Give the input a chance to focus then fire the click
        // handler to force open the typeahead
        this.elm.nativeElement.getElementsByTagName('input')[0].focus();
        setTimeout(() => this.click$.next(''));
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

        if (this.startId !== null &&
            this.entrylist && !this.defaultSelectionApplied) {

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
        this.entrylist.push(entry);
        this.applySelection();
    }

    // Manually set the selected value by ID.
    // This does NOT fire the onChange handler.
    // DEPRECATED: use this.selectedId = abc or [selectedId]="abc" instead.
    applyEntryId(entryId: any) {
        this.selected = this.entrylist.filter(e => e.id === entryId)[0];
    }

    addAsyncEntry(entry: ComboboxEntry) {
        // Avoid duplicate async entries
        if (!this.asyncIds['' + entry.id]) {
            this.asyncIds['' + entry.id] = true;
            this.addEntry(entry);
        }
    }

    hasEntry(entryId: any): boolean {
        return this.entrylist.filter(e => e.id === entryId)[0] !== undefined;
    }

    onBlur() {
        // When the selected value is a string it means we have either
        // no value (user cleared the input) or a free-text value.

        if (typeof this.selected === 'string') {

            if (this.allowFreeText && this.selected !== '') {
                // Free text entered which does not match a known entry
                // translate it into a dummy ComboboxEntry
                this.selected = {
                    id: null,
                    label: this.selected,
                    freetext: true
                };

            } else {

                this.selected = null;
            }

            // Manually fire the onchange since NgbTypeahead fails
            // to fire the onchange when the value is cleared.
            this.selectorChanged(
                {item: this.selected, preventDefault: () => true});
        }
        this.propagateTouch();
    }

    // Fired by the typeahead to inform us of a change.
    selectorChanged(selEvent: NgbTypeaheadSelectItemEvent) {
        this.onChange.emit(selEvent.item);
        this.propagateChange(selEvent.item);
    }

    // Adds matching async entries to the entry list
    // and propagates the search term for pipelining.
    addAsyncEntries(term: string): Observable<string> {

        if (!term || !this.asyncDataSource) {
            return of(term);
        }

        let searchTerm: string;
        searchTerm = term;
        if (searchTerm === '_CLICK_') {
            if (this.asyncSupportsEmptyTermClick) {
                searchTerm = '';
            } else {
                return of();
            }
        }

        return new Observable(observer => {
            this.asyncDataSource(searchTerm).subscribe(
                (entry: ComboboxEntry) => this.addAsyncEntry(entry),
                err => {},
                ()  => {
                    observer.next(searchTerm);
                    observer.complete();
                }
            );
        });
    }

    filter = (text$: Observable<string>): Observable<ComboboxEntry[]> => {
        return text$.pipe(
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

                // In sync-data mode, a click displays the full list.
                if (term === '_CLICK_' && !this.asyncDataSource) {
                    return this.entrylist;
                }

                // Filter entrylist whose labels substring-match the
                // text entered.
                return this.entrylist.filter(entry => {
                    const label = entry.label || entry.id;
                    return label.toLowerCase().indexOf(term.toLowerCase()) > -1;
                });
            })
        );
    }

    writeValue(value: ComboboxEntry) {
        if (value !== undefined && value !== null) {
            this.startId = value.id;
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


