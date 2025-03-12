import {ElementRef, TemplateRef, Component, Input, Output, OnInit, OnDestroy,
    ViewChild, EventEmitter, AfterViewInit, ViewEncapsulation} from '@angular/core';
import {Subscription, from, Observable, Subject, merge, OperatorFunction} from 'rxjs';
import {filter, debounceTime, distinctUntilChanged, map} from 'rxjs/operators';
import {MarcRecord, MarcField, MarcSubfield} from './marcrecord';
import {MarcEditContext, FieldFocusRequest, MARC_EDITABLE_FIELD_TYPE,
    TextUndoRedoAction} from './editor-context';
import {StringComponent} from '@eg/share/string/string.component';
import {TagTable} from './tagtable.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {NgbTypeahead, NgbTypeaheadModule} from '@ng-bootstrap/ng-bootstrap';

/**
 * MARC Editable Content Component
 */

@Component({
    selector: 'eg-marc-editable-content',
    templateUrl: './editable-content.component.html',
    styleUrls: ['./editable-content.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class EditableContentComponent
implements OnInit, AfterViewInit, OnDestroy {

    static idGen = 0;
    @Input() domId: any = 'editable-content-' + EditableContentComponent.idGen++;

    @Input() context: MarcEditContext;
    @Input() field: MarcField;
    @Input() fieldType: MARC_EDITABLE_FIELD_TYPE = null;
    @Input() bigText = false;

    // array of subfield code and subfield value
    @Input() subfield: MarcSubfield;

    @Input() fixedFieldCode: string;

    // space-separated list of additional CSS classes to append
    @Input() moreClasses: string;

    // aria-label text.  This will not be visible in the UI.
    @Input() ariaLabel: string;

    get record(): MarcRecord { return this.context.record; }

    // If true, the typeahead only matches values that start with
    // the value typed as opposed to a 'contains' match.
    @Input() startsWith = false;
    // If true, matches either the ID or the label in the combobox result
    @Input() searchInId = false;

    IAmFocused = false;


    inputContent: string;
    suggest = true;
    editInput: any; // <input/> or <div contenteditable/>
    maxLength: number | null = null;

    // Track the load-time content so we know what text value to
    // track on our undo stack.
    undoBackToText: string;

    focusSub: Subscription;
    undoRedoSub: Subscription;
    isLeader: boolean; // convenience

    // Cache of fixed field menu options
    ffValues: ComboboxEntry[] = [];

    // Cache of tag combobox entries
    tagComboListEntries: ComboboxEntry[] = [];

    // Track the fixed field value locally since extracting the value
    // in real time from the record, which adds padding to the text,
    // causes usability problems.
    ffValue: string;
    @Input() tabindex = null;

    @ViewChild('add006', {static: false}) add006Str: StringComponent;
    @ViewChild('add007', {static: false}) add007Str: StringComponent;
    @ViewChild('add008', {static: false}) add008Str: StringComponent;
    @ViewChild('insertBefore', {static: false}) insertBeforeStr: StringComponent;
    @ViewChild('insertAfter', {static: false}) insertAfterStr: StringComponent;
    @ViewChild('deleteField', {static: false}) deleteFieldStr: StringComponent;
    @ViewChild('MARCCombo', { static: false }) TagComboBox: ComboboxComponent;
    @ViewChild('instance', { static: true }) instance: NgbTypeahead;
    @ViewChild('marcTagDisplayTemplate', { static: false }) marcTagDisplayTemplateRef: TemplateRef<any>;

    tt(): TagTable { // for brevity
        return this.context.tagTable;
    }

    ngOnInit() {
        this.setupFieldType();
        this.inputContent = this.getContent();
    }

    ngOnChange() {
        this.checkSize();
    }

    checkSize(field?: string, subfield?:string): boolean {
        // switch from <input> to <textarea> if existing content is long
        const threshold = 85;
        if (this.inputContent && this.inputContent.length > threshold) {
            this.bigText = true;
        } else {
            this.bigText = this.context.isFullWidth(field, subfield);
        }

        return this.bigText;
    }

    ngOnDestroy() {
        if (this.focusSub) { this.focusSub.unsubscribe(); }
        if (this.undoRedoSub) { this.undoRedoSub.unsubscribe(); }
    }

    watchForFocusRequests() {
        this.focusSub = this.context.fieldFocusRequest.pipe(
            filter((req: FieldFocusRequest) => this.focusRequestIsMe(req)))
            .subscribe((req: FieldFocusRequest) => this.selectText(req));
    }

    watchForUndoRedoRequests() {
        this.undoRedoSub = this.context.textUndoRedoRequest.pipe(
            filter((action: TextUndoRedoAction) => this.focusRequestIsMe(action.position)))
            .subscribe((action: TextUndoRedoAction) => this.processUndoRedo(action));
    }

    focusRequestIsMe(req: FieldFocusRequest): boolean {
        if (req.target !== this.fieldType) { return false; }

        if (this.field) {
            if (req.fieldId !== this.field.fieldId) { return false; }
        } else if (req.target === 'ldr') {
            return this.isLeader;
        } else if (req.target === 'ffld' &&
            req.ffCode !== this.fixedFieldCode) {
            return false;
        }

        if (req.sfOffset !== undefined &&
            req.sfOffset !== this.subfield[2]) {
            // this is not the subfield you are looking for.
            return false;
        }

        return true;
    }

    selectText(req?: FieldFocusRequest) {
        if (this.field && typeof this.field == 'object') {
            this.field.hasFocus = true;
            this.field.isDraggable = false;
        }

        if (!this.bigText) {
            this.editInput?.select();
        }

        if (req) {
            if (req.newText) {
                this.setContent(req.newText);
            }
        } else {

            // Focus request may have come from keyboard navigation,
            // clicking, etc.  Model the event as a focus request
            // so it can be tracked the same.
            req = {
                fieldId: this.field ? this.field.fieldId : -1,
                target: this.fieldType,
                sfOffset: this.subfield ? this.subfield[2] : undefined,
                ffCode: this.fixedFieldCode
            };
        }

        this.context.lastFocused = req;
    }

    setupFieldType() {
        const content = this.getContent();
        this.undoBackToText = content;

        this.watchForFocusRequests();
        this.watchForUndoRedoRequests();

        switch (this.fieldType) {
            case 'ldr':
                this.isLeader = true;
                this.suggest = false;
                break;

            case 'tag':
                this.maxLength = 3;
                break;

            case 'cfld':
                this.suggest = false;
                break;

            case 'ffld': {
                this.applyFFOptions();
                // these fixed fields can include multiple values (which doesn't work well with combobox) or free text
                // TODO: remove check for AUT when authorities fixed field data is populated
                const complexFields = ['AccM','Cont','Date1','Date2','Ills','LTxt','Relf','SpFm','Time'];
                if (complexFields.includes(this.fixedFieldCode) || this.record.recordType() === 'AUT' ) {
                    this.suggest = false;
                }
                break;
            }

            case 'ind1':
            case 'ind2':
                this.maxLength = 1;
                break;

            case 'sfc':
                this.maxLength = 1;
                break;

            case 'sfv':
                this.suggest = false;
                this.maxLength = null;
                break;

            default:
                /* */
        }
    }

    applyFFOptions() {
        return this.tt().getFfFieldMeta(this.fixedFieldCode)
            .then(fieldMeta => {
                if (fieldMeta) {
                    this.maxLength = fieldMeta.length || 1;
                }
            });
    }

    asyncComboMenuEntries(dummyTerm: string) : Observable<ComboboxEntry> {
        return from(this.comboMenuEntries(dummyTerm).map(e => {
            return { id: e.id, label: e.id, userdata: e };
        }));
    }

    // These are served dynamically to handle cases where a tag or
    // subfield is modified in place.
    comboMenuEntries(currentUserValue?: string): ComboboxEntry[] {
        if (this.isLeader) { return; }

        let haystack = [];
        const needle = this.getContent();

        console.debug(`comboMenuEntries: type ${this.fieldType}, term ${currentUserValue}, current content ${needle}`);

        switch (this.fieldType) {
            case 'tag':
                haystack = this.tt().getFieldTags();
                break;

            case 'sfc':
                haystack = this.tt().getSubfieldCodes(this.field.tag);
                break;

            case 'sfv':
                haystack = this.tt().getSubfieldValues(
                    this.field.tag, this.subfield[0]);
                break;

            case 'ind1':
            case 'ind2':
                haystack = this.tt().getIndicatorValues(
                    this.field.tag, this.fieldType);
                break;

            case 'ffld':
                haystack = this.tt().getFfValues(this.fixedFieldCode);
                break;
        }

        haystack ??= [{id:null,label:'',disabled:true}]; // dummy entry if undefined, must have at least one extra. thanks, combobox

        // makin' copies ... so others' filter()s don't break the future
        haystack = haystack.map(h => { return { id: h.id, label: h.label, disabled: h.disabled }; });

        let input_source = 'current content';
        let input_value = needle;

        if (currentUserValue.length > 0) { // term isn't empty (user didn't backspace it out)
            input_source = 'user input';
            input_value = currentUserValue;
            this.setContent(input_value); // this works in concert with selectOnExact to let ngbTypeahead choose a dummy entry
        }

        const new_entry = haystack.findIndex(e => e.id === input_value); // look for a "valid" entry in list based on source
        if (new_entry > -1) { // if we find one, push to the front and return the full list
            const to_front = haystack.splice(new_entry,1);
            to_front[0].class = 'initial_value';
            const list = to_front.concat(haystack);
            console.debug(`comboMenuEntries: found entry matching ${input_source} "${input_value}"`);
            console.debug('comboMenuEntries: returning haystack with chosen entry at the front', list);
            return list;
        }

        // if we get here, there is no source-driven valid entry. we construct one and return the rest of the list after
        const list = [{
            id: input_value,
            label: $localize`Input value "${input_value}" unknown`,
            class: {
                // if the haystack has entries, we could mark this as "bad" in the dropdown, via the template
                'unknown': !!(haystack.filter(h => h.id !== null).length > 0)
            }
        }].concat(haystack);

        console.debug(`comboMenuEntries: did NOT find entry matching ${input_source} "${input_value}"`);
        console.debug('comboMenuEntries: returning constructed entry, with any valid options following', list);
        return list;
    }

    tagComboMenuEntries(): ComboboxEntry[] {

        // string components may not yet be loaded.
        if (this.tagComboListEntries.length > 0 || !this.add006Str) {
            return this.tagComboListEntries;
        }

        this.tt().getFieldTags().forEach(e => this.tagComboListEntries.push(e));

        return this.tagComboListEntries;
    }

    initialEntryList(): ComboboxEntry[] {
        return [{ id: this.getContent(), label: this.getContent() } as ComboboxEntry];
        // return [{id: this.getContent(), label: this.getComboboxEntryLabel()} as ComboboxEntry]
    }

    getComboboxEntryLabel(): string {

        switch (this.fieldType) {
            case 'ldr':
                return $localize`Leader`;
            case 'cfld':
                return $localize`Control Field Data`;
            case 'tag':
                return this.tt().getFieldLabel(this.getContent());
            case 'sfc':
                return this.tt().getSubfieldLabel(this.field.tag, this.getContent());
            case 'sfv':
                return this.tt().getSubfieldValueLabel(this.field.tag, this.subfield[0], this.getContent());
            case 'ind1':
            case 'ind2':
                return this.tt().getIndicatorValueLabel(this.field.tag, this.fieldType, this.getContent());

            case 'ffld':
                return this.tt().getFfValueLabel(this.fixedFieldCode, this.getContent());
        }

        return null;
    }

    getContent(): string {

        switch (this.fieldType) {
            case 'ldr': return this.record.leader;
            case 'cfld': return this.field.data;
            case 'tag': return this.field.tag;
            case 'sfc': return this.subfield[0];
            case 'sfv': return this.subfield[1];
            case 'ind1': return this.field.ind1;
            case 'ind2': return this.field.ind2;

            case 'ffld':
                // When actively editing a fixed field, track its value
                // in a local variable instead of pulling the value
                // from record.extractFixedField(), which applies
                // additional formattting, causing usability problems
                // (e.g. unexpected spaces).  Once focus is gone, the
                // view will be updated with the correctly formatted
                // value.

                if ( this.ffValue === undefined ||
                    !this.context.lastFocused ||
                    !this.focusRequestIsMe(this.context.lastFocused)) {

                    this.ffValue =
                        this.record.extractFixedField(this.fixedFieldCode);
                }
                return this.ffValue;
        }
        return 'X';
    }

    setContent(passed_value: any, skipUndoTrack?: boolean) {

        let value = passed_value;
        if (typeof passed_value === 'object') { // got a ComboboxEntry-alike
            value = passed_value.id;
        }


        switch (this.fieldType) {
            case 'ldr': this.record.leader = value; break;
            case 'cfld': this.field.data = value; break;
            case 'tag': this.field.tag = value; break;
            case 'sfc': this.subfield[0] = value; break;
            case 'sfv': this.subfield[1] = value; break;
            case 'ind1': this.field.ind1 = value; break;
            case 'ind2': this.field.ind2 = value; break;
            case 'ffld':
                // Track locally and propagate to the record.
                this.ffValue = value;
                this.record.setFixedField(this.fixedFieldCode, value);
                break;
        }

        if (!skipUndoTrack) {
            this.trackTextChangeForUndo(value);
        }

    }

    trackTextChangeForUndo(value: string) {

        // Human-driven changes invalidate the redo stack.
        this.context.redoStack = [];

        const lastUndo = this.context.undoStack[0];

        if (lastUndo
            && lastUndo instanceof TextUndoRedoAction
            && lastUndo.textContent === this.undoBackToText
            && this.focusRequestIsMe(lastUndo.position)) {
            // Most recent undo entry was a text change event within the
            // current atomic editing (focused) session for the input.
            // Nothing else to track.
            return;
        }

        const undo = new TextUndoRedoAction();
        undo.position = this.context.lastFocused;
        undo.textContent =  this.undoBackToText;

        this.context.addToUndoStack(undo);
    }

    // Apply the undo or redo action and track its opposite
    // action on the necessary stack
    processUndoRedo(action: TextUndoRedoAction) {

        // Undoing a text change
        const recoverContent = this.getContent();
        this.setContent(action.textContent, true);

        action.textContent = recoverContent;
        const moveTo = action.isRedo ?
            this.context.undoStack : this.context.redoStack;

        moveTo.unshift(action);
    }

    inputBlurred() {
        // If the text content changed during this focus session,
        // track the new value as the value the next session of
        // text edits should return to upon undo.
        this.undoBackToText = this.getContent();
        this.field.hasFocus = false;
    }

    // Propagate textarea content into our record
    bigTextValueChange() {
        this.setContent(this.editInput.value);
    }

    ngAfterViewInit() {
        this.editInput = document.getElementById(this.domId + '');

        // Initialize the textarea
        if (this.bigText) {
            this.editInput.value = this.getContent();
        }

        if (this.TagComboBox) {
            this.TagComboBox.asyncDataSource = (_: string) => this.asyncComboMenuEntries(_);
        }
    }

    inputSize(): number {
        /* eslint-disable no-magic-numbers */
        switch (this.fieldType) {
            case 'ind1':
            case 'ind2':
            case 'sfc': return 1;
            case 'tag': return 3;
            default:
                // give some breathing room
                if (this.maxLength && this.maxLength >= 0) {
                    return this.maxLength + 1;
                }

                // grow with the content
                if (this.getContent()) {return this.getContent().length + 3;}

                // default if nothing is set
                return 5;
        }
        /* eslint-enable no-magic-numbers */
    }

    // Route keydown events to the appropriate handler
    inputKeyDown(evt: KeyboardEvent) {

        switch (evt.key) {
            case 'y':
                if (evt.ctrlKey) { // redo
                    this.context.requestRedo();
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;

            case 'z':
                if (evt.ctrlKey) { // undo
                    this.context.requestUndo();
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;

            case 'F6':
                if (evt.shiftKey) {
                    // shift+F6 => add 006
                    this.context.add00X('006');
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;

            case 'F7':
                if (evt.shiftKey) {
                    // shift+F7 => add 007
                    this.context.add00X('007');
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;

            case 'F8':
                if (evt.shiftKey) {
                    // shift+F8 => add/replace 008
                    this.context.insertReplace008();
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;

            case 'ArrowDown':

                if (evt.ctrlKey && !evt.shiftKey && !(this.fieldType === 'ldr' || this.fieldType === 'ffld')) {
                    // ctrl+down == copy current field down one
                    this.context.insertField(
                        this.field, this.record.cloneField(this.field));
                }

                // ctrl+shift+down = open combobox
                if (evt.ctrlKey && evt.shiftKey && this.TagComboBox) {
                    this.TagComboBox.openMe(evt);
                }

                // down == move focus to tag of next field
                // but not in an open combobox or textarea
                if (!evt.ctrlKey && !this.TagComboBox?.instance.isPopupOpen() && !this.bigText) {
                    evt.preventDefault();
                    evt.stopPropagation();
                    // avoid dupe focus requests during copy
                    this.context.focusNextTag(this.field);
                }
                break;

            case 'ArrowUp':

                if (evt.ctrlKey && !evt.shiftKey && !(this.fieldType === 'ldr' || this.fieldType === 'ffld')) {
                    // ctrl+up == copy current field up one
                    this.context.insertField(
                        this.field, this.record.cloneField(this.field), true);
                }
                // ctrl+shift+up = close combobox
                if (evt.ctrlKey && evt.shiftKey && this.TagComboBox) {
                    this.TagComboBox.closeMe(evt);
                }

                // up == move focus to tag of previous field
                // but not in an open combobox or textarea
                if (!evt.ctrlKey && !this.TagComboBox?.instance.isPopupOpen() && !this.bigText) {
                    evt.preventDefault();
                    evt.stopPropagation();
                    // avoid dupe focus requests
                    this.context.focusPreviousTag(this.field);
                }
                break;

        }

        // None of the remaining key combos are supported by the LDR
        // or fixed field editor.
        if (this.fieldType === 'ldr' || this.fieldType === 'ffld') { return; }

        switch (evt.key) {

            case 'Enter':
                if (evt.ctrlKey) {
                    // ctrl+enter == insert stub field after focused field
                    // ctrl+shift+enter == insert stub field before focused field
                    this.context.insertStubField(this.field, evt.shiftKey);
                }

                evt.preventDefault(); // Bare newlines not allowed.
                evt.stopPropagation();
                break;

            case 'Delete':

                if (evt.ctrlKey) {
                    // ctrl+delete == delete whole field
                    this.context.deleteField(this.field);
                    evt.preventDefault();
                    evt.stopPropagation();

                } else if (evt.shiftKey) {

                    if (this.subfield) {
                        // shift+delete == delete subfield

                        this.context.deleteSubfield(this.field, this.subfield);
                    }
                    // prevent any shift-delete from bubbling up becuase
                    // unexpected stuff will be deleted.
                    evt.preventDefault();
                    evt.stopPropagation();
                }

                break;

            case 'd': // thunk
            case 'i':
                if (evt.ctrlKey) {
                    // ctrl+i / ctrl+d == insert subfield
                    const pos = this.subfield ? this.subfield[2] + 1 : 0;
                    this.context.insertStubSubfield(this.field, pos);
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;
        }

    }

    // if the user has added the max number of characters for the field, advance focus to the next input
    // NOT USED
    // TODO: to use, add (input)="inputEvent(inputSize (), $event)" to eg-combobox
    skipToNext(max: number, $event?: InputEvent) {
        if ($event.data.length === max) {
            switch (this.fieldType) {
                case 'tag':
                    this.context.requestFieldFocus({fieldId: this.field.fieldId, target: 'ind1'});
                    break;
                case 'ind1':
                    this.context.requestFieldFocus({fieldId: this.field.fieldId, target: 'ind2'});
                    break;
                case 'ind2':
                    this.context.requestFieldFocus({fieldId: this.field.fieldId, target: 'sfc', sfOffset: 0});
                    break;
                case 'sfc':
                    this.context.requestFieldFocus({fieldId: this.field.fieldId, target: 'sfv', sfOffset: this.subfield[2]});
                    break;
                default:
                    break;
            }
        }
    }

    insertField(before: boolean) {

        const newField = this.record.newField(
            {tag: '999', subfields: [[' ', '', 0]]});

        if (before) {
            this.record.insertFieldsBefore(this.field, newField);
        } else {
            this.record.insertFieldsAfter(this.field, newField);
        }

        this.context.requestFieldFocus(
            {fieldId: newField.fieldId, target: 'tag'});
    }

    deleteField() {
        if (!this.context.focusNextTag(this.field)) {
            this.context.focusPreviousTag(this.field);
        }

        this.record.deleteFields(this.field);
    }

    deleteSubfield() {
        // If subfields remain, focus the previous subfield.
        // otherwise focus our tag.
        const sfpos = this.subfield[2] - 1;

        this.field.deleteExactSubfields(this.subfield);

        const focus: FieldFocusRequest = {
            fieldId: this.field.fieldId, target: 'tag'};

        if (sfpos >= 0) {
            focus.target = 'sfv';
            focus.sfOffset = sfpos;
        }

        this.context.requestFieldFocus(focus);
    }

    isAuthInvalid(): boolean {
        return (
            this.fieldType === 'sfv' &&
            this.field.authChecked &&
            !this.field.authValid
        );
    }

    isAuthValid(): boolean {
        return (
            this.fieldType === 'sfv' &&
            this.field.authChecked &&
            this.field.authValid
        );
    }

    isLastSubfieldValue(): boolean {
        if (this.fieldType === 'sfv') {
            const myIdx = this.subfield[2];
            for (let idx = 0; idx < this.field.subfields.length; idx++) {
                if (idx > myIdx) {
                    return false;
                }
            }
            return true;
        }

        return false;
    }

}


