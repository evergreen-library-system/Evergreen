/**
 * <eg-combobox [allowFreeText]="true" [entries]="comboboxEntryList"/>
 *  <!-- see also <eg-combobox-entry> -->
 * </eg-combobox>
 */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter, ElementRef} from '@angular/core';
import {Observable, of, Subject} from 'rxjs';
import {map, tap, reduce, mergeMap, mapTo, debounceTime, distinctUntilChanged, merge, filter} from 'rxjs/operators';
import {NgbTypeahead, NgbTypeaheadSelectItemEvent} from '@ng-bootstrap/ng-bootstrap';
import {StoreService} from '@eg/core/store.service';

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
  `]
})
export class ComboboxComponent implements OnInit {

    selected: ComboboxEntry;
    click$: Subject<string>;
    entrylist: ComboboxEntry[];

    @ViewChild('instance') instance: NgbTypeahead;

    // Applies a name attribute to the input.
    // Useful in forms.
    @Input() name: string;

    // Placeholder text for selector input
    @Input() placeholder = '';

    @Input() persistKey: string; // TODO

    @Input() allowFreeText = false;

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
    @Input() startId: any;
    @Input() startIdFiresOnChange: boolean;

    @Input() asyncDataSource: (term: string) => Observable<ComboboxEntry>;

    // Useful for efficiently preventing duplicate async entries
    asyncIds: {[idx: string]: boolean};

    // True if a default selection has been made.
    defaultSelectionApplied: boolean;

    @Input() set entries(el: ComboboxEntry[]) {
        if (el) {
            this.entrylist = el;
            this.applySelection();

            // It's possible to provide an entrylist at load time, but
            // fetch all future data via async data source.  Track the
            // values we already have so async lookup won't add them again.
            // A new entry list wipes out any existing async values.
            this.asyncIds = {};
            el.forEach(entry => this.asyncIds['' + entry.id] = true);
        }
    }

    // Emitted when the value is changed via UI.
    // When the UI value is cleared, null is emitted.
    @Output() onChange: EventEmitter<ComboboxEntry>;

    // Useful for massaging the match string prior to comparison
    // and display.  Default version trims leading/trailing spaces.
    formatDisplayString: (ComboboxEntry) => string;

    constructor(
      private elm: ElementRef,
      private store: StoreService,
    ) {
        this.entrylist = [];
        this.asyncIds = {};
        this.click$ = new Subject<string>();
        this.onChange = new EventEmitter<ComboboxEntry>();
        this.defaultSelectionApplied = false;

        this.formatDisplayString = (result: ComboboxEntry) => {
            return result.label.trim();
        };
    }

    ngOnInit() {
    }

    openMe($event) {
        // Give the input a chance to focus then fire the click
        // handler to force open the typeahead
        this.elm.nativeElement.getElementsByTagName('input')[0].focus();
        setTimeout(() => this.click$.next(''));
    }

    // Apply a default selection where needed
    applySelection() {

        if (this.startId &&
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
    }

    // Fired by the typeahead to inform us of a change.
    selectorChanged(selEvent: NgbTypeaheadSelectItemEvent) {
        this.onChange.emit(selEvent.item);
    }

    // Adds matching async entries to the entry list
    // and propagates the search term for pipelining.
    addAsyncEntries(term: string): Observable<string> {

        if (!term || !this.asyncDataSource) {
            return of(term);
        }

        return new Observable(observer => {
            this.asyncDataSource(term).subscribe(
                (entry: ComboboxEntry) => this.addAsyncEntry(entry),
                err => {},
                ()  => {
                    observer.next(term);
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
                    !this.instance.isPopupOpen() && !this.asyncDataSource
                )).pipe(mapTo('_CLICK_'))
            ),

            // mergeMap coalesces an observable into our stream.
            mergeMap(term => this.addAsyncEntries(term)),
            map((term: string) => {

                if (term === '' || term === '_CLICK_') {
                    // Avoid displaying the existing entries on-click
                    // for async sources, becuase that implies we have
                    // the full data set. (setting?)
                    if (this.asyncDataSource) {
                        return [];
                    } else {
                        // In sync mode, a post-focus empty search or
                        // click event displays the whole list.
                        return this.entrylist;
                    }
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
}


