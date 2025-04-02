import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {filter} from 'rxjs/operators';
import {IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {TagTableService} from './tagtable.service';
import {MarcRecord, MarcField, MarcSubfield} from './marcrecord';
import {MarcEditContext} from './editor-context';
import {AuthorityLinkingDialogComponent} from './authority-linking-dialog.component';
import {PhysCharDialogComponent} from './phys-char-dialog.component';
import {CharMapDialogComponent} from './charmap/charmap-dialog.component';


/**
 * MARC Record rich editor interface.
 */

@Component({
    selector: 'eg-marc-rich-editor',
    templateUrl: './rich-editor.component.html',
    styleUrls: ['rich-editor.component.css', 'rich-editor-colors.css']
})

export class MarcRichEditorComponent implements OnInit {

    @Input() context: MarcEditContext;
    get record(): MarcRecord { return this.context.record; }

    dataLoaded: boolean;
    // eslint-disable-next-line no-magic-numbers
    randId = Math.floor(Math.random() * 100000);
    stackSubfields: boolean;
    controlledBibTags: string[] = [];
    dragRow: MarcField;

    // number of characters that forces a multiline input
    sizeThreshold: number;

    @ViewChild('authLinker', {static: false})
        authLinker: AuthorityLinkingDialogComponent;

    @ViewChild('physCharDialog', {static: false})
        physCharDialog: PhysCharDialogComponent;

    @ViewChild('charMapDialog', {static: false})
        CharMapDialog: CharMapDialogComponent;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private store: ServerStoreService,
        private tagTable: TagTableService
    ) {}

    ngOnInit() {

        const threshold = 85;
        this.sizeThreshold = threshold;

        this.store.getItem('cat.marcedit.stack_subfields')
            .then(stack => this.stackSubfields = stack);

        this.init().then(_ =>
            this.context.recordChange.subscribe(__ => this.init()));

        // Changing the Type fixed field means loading new meta-metadata.
        this.record.fixedFieldChange.pipe(filter(code => code === 'Type'))
            .subscribe(_ => this.init());
    }

    init(): Promise<any> {
        this.dataLoaded = false;

        if (!this.record) { return Promise.resolve(); }

        return Promise.all([
            this.tagTable.loadTags({
                marcRecordType: this.context.recordType,
                ffType: this.record.recordType()
            }).then(table => this.context.tagTable = table),
            this.tagTable.getControlledBibTags().then(
                tags => this.controlledBibTags = tags),
            this.fetchSettings()
        ]).then(_ =>
            // setTimeout forces all of our sub-components to rerender
            // themselves each time init() is called.  Without this,
            // changing the record Type would only re-render the fixed
            // fields editor when data had to be fetched from the
            // network.  (Sometimes the data is cached).
            setTimeout(() => this.dataLoaded = true)
        );
    }

    fetchSettings(): Promise<any> {
        // Fetch at rich editor load time to cache.
        return this.org.settings(['cat.marc_control_number_identifier']);
    }

    stackSubfieldsChange() {
        if (this.stackSubfields) {
            this.store.setItem('cat.marcedit.stack_subfields', true);
        } else {
            this.store.removeItem('cat.marcedit.stack_subfields');
        }
    }

    undoCount(): number {
        return this.context.undoCount();
    }

    redoCount(): number {
        return this.context.redoCount();
    }

    undo() {
        this.context.requestUndo();
    }

    redo() {
        this.context.requestRedo();
    }

    deleteField(field: MarcField) {
        this.context.deleteField(field);
    }

    copyField(field: MarcField) {
        this.context.insertField(field, this.record.cloneField(field));
    }

    addField(field: MarcField, before = false) {
        this.context.insertStubField(field, before);
    }

    // Keyboard alternatives to drag and drop
    upField(field: MarcField, $event?: any) {
        $event.preventDefault();
        const prev = this.context.record.getPreviousField(field.fieldId);
        if (prev) {
            const current = this.context.record.fields.indexOf(field);
            this.context.record.fields[current] = this.context.record.fields.splice(current - 1, 1, this.context.record.fields[current])[0];
            this.context.trackMoveUndo(field, current - 1);
        }
        // setTimeout() prevents random loss of focus during DOM updates
        setTimeout(() => this.context.focusAfterMove(field.fieldId, $event));
    }

    downField(field: MarcField, $event?: any) {
        $event.preventDefault();
        const next = this.context.record.getNextField(field.fieldId);
        if (next) {
            const current = this.context.record.fields.indexOf(field);
            this.context.record.fields[current] = this.context.record.fields.splice(current + 1, 1, this.context.record.fields[current])[0];
            this.context.trackMoveUndo(field, current + 1);
        }
        setTimeout(() => this.context.focusAfterMove(field.fieldId, $event));
    }

    onRowDragEnter($event: any, field: any) {
        if ($event.target.tagName.toLowerCase === 'input' || $event.target.tagName.toLowerCase === 'textarea') {return;}

        if (field === 'END') {
            $event.target.closest('tr').classList.add('isDragTarget');
        } else {
            if (this.dragRow && this.dragRow.fieldId !== field.fieldId) {
                field.isDragTarget = true;
            }
        }
        $event.preventDefault();
    }

    onRowDragLeave($event: any, field: any) {
        if (field === 'END') {
            $event.target.closest('tr').classList.remove('isDragTarget');
        } else {field.isDragTarget = false;}
        $event.preventDefault();
    }

    onRowDrop($event: any, dropTarget: any) {
        $event.preventDefault();

        /* put the dragged row in a temp var so we can clear it from the record
        context immediately, even if we later find that it was dropped in an
        invalid location, or back on itself */
        const movingField = this.dragRow;
        this.dragRow = null;

        // remove isDragTarget class from all field rows
        this.context.record.fields.forEach(f => f.isDragTarget = false);

        // remove isDragTarget class from end row if necessary
        if (dropTarget === 'END') {
            // the row itself might not be the event target if the move button was grabbed
            $event.target.closest('tr').classList.remove('isDragTarget');
        }

        const moveFrom = this.context.record.fields.indexOf(movingField);
        // move to the end by default
        let moveTo = this.context.record.fields.length + 1;
        if (dropTarget !== 'END') {
            moveTo = this.context.record.fields.indexOf(dropTarget);
        }

        if ( moveFrom !== moveTo ) {
            this.context.moveField(moveFrom, moveTo, movingField);
        }

        // focus back on the Move button of the dragged row
        this.context.focusAfterMove(movingField.fieldId, $event);
    }

    onKeyDown(evt: KeyboardEvent, field: MarcField, subfield?: MarcSubfield) {
        switch (evt.key) {
            case 'ArrowLeft':
            case 'ArrowRight':
                // console.debug("ArrowRight: ", evt, field, subfield);
                let el = evt.target as HTMLElement;
                // do nothing if we are in a text input
                if (el.nodeName && (el.nodeName.toLowerCase() === 'input' || el.nodeName.toLowerCase() === 'textarea')) {
                    return;
                }
                // otherwise, move focus from the group to its first input (the subfield code)
                evt.preventDefault();
                evt.stopPropagation();
                this.context.focusSubfield(field, subfield[2], false);
                break;

            // all remaining shortcuts duplicated from editable-content.component.ts
            // minus combobox shortcuts
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

                if (evt.ctrlKey && !evt.shiftKey) {
                    // ctrl+down == copy current field down one
                    this.context.insertField(
                        field, this.record.cloneField(field));
                }

                // down == move focus to tag of next field
                // but not in a combobox or textarea
                if (!evt.ctrlKey && !(subfield && this.context.subfieldHasFocus(field, subfield))) {
                    this.context.focusNextTag(field);
                }
                break;

            case 'ArrowUp':

                if (evt.ctrlKey && !evt.shiftKey) {
                    // ctrl+up == copy current field up one
                    this.context.insertField(
                        field, this.record.cloneField(field), true);
                }

                // up == move focus to tag of previous field
                // but not in a subfield
                if (!evt.ctrlKey && !(subfield && this.context.subfieldHasFocus(field, subfield))) {
                    this.context.focusPreviousTag(field);
                }
                break;

            case 'Enter':
                if (evt.ctrlKey) {
                    // ctrl+enter == insert stub field after focused field
                    // ctrl+shift+enter == insert stub field before focused field
                    this.context.insertStubField(field, evt.shiftKey);
                }

                // this is not needed outside editable-content
                // and it breaks button (click) functions
                // evt.preventDefault(); // Bare newlines not allowed.
                break;

            case 'Delete':

                if (evt.ctrlKey) {
                    // ctrl+delete == delete whole field
                    this.context.deleteField(field);
                    evt.preventDefault();
                    evt.stopPropagation();
                } else if (evt.shiftKey) {

                    if (subfield) {
                        // shift+delete == delete subfield

                        this.context.deleteSubfield(field, subfield);
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
                    const pos = subfield ? subfield[2] + 1 : 0;
                    this.context.insertStubSubfield(field, pos);
                    evt.preventDefault();
                    evt.stopPropagation();
                }
                break;
        }
        evt.stopPropagation();
    }

    getSubfieldDomId(field, subfield) {
        return 'subfield-' + field.tag+subfield[0] + '-' + subfield[2];
    }

    getSubfieldTabindex(field, subfield) {
        const subfieldGroupElement = document.getElementById(this.getSubfieldDomId(field, subfield)) as HTMLElement;
        if (subfieldGroupElement?.contains(document.activeElement)) {
            return -1;
        }
        return 0;
    }

    focusSubfieldGroup(field: MarcField, subfield: MarcSubfield) {
        // set lastFocused to subfield group for undo/redo purposes,
        // but do not emit a focus request
        this.context.lastFocused = {fieldId: field.fieldId, target: 'group', sfOffset: subfield[2]};
    }

    focusButton(field: MarcField, $event: any, button?: string,) {
        if (button && button === 'move') {
            field.isDraggable = true;
        }
        field.hasFocus = true;
    }

    blurButton(field: MarcField, $event: any, button?: string,) {
        if (button && button === 'move') {
            field.isDraggable = false;
        }
        field.hasFocus = false;
    }

    getPreviousTag(fieldId: number) {
        const prev = this.context.record.getPreviousField(fieldId);
        if (!prev || !prev.tag) {return null;}
        return prev.tag;
    }

    getNextTag(fieldId: number) {
        const next = this.context.record.getNextField(fieldId);
        if (!next || !next.tag) {return null;}
        return next.tag;
    }

    addSubfield(field: MarcField, position: number) {
        // field.subfields.length + 1
        this.context.insertStubSubfield(field, position);
    }

    deleteSubfield(field: MarcField, subfield: any) {
        this.context.deleteSubfield(field, subfield);
    }

    controlFields(): MarcField[] {
        return this.record.fields.filter(f => f.isCtrlField);
    }

    dataFields(): MarcField[] {
        return this.record.fields.filter(f => !f.isCtrlField);
    }

    validate() {
        const fields = [];

        this.record.fields.filter(f => this.isControlledBibTag(f.tag))
            .forEach(f => {
                f.authValid = false;
                fields.push({
                    id: f.fieldId, // ignored and echoed by server
                    tag: f.tag,
                    ind1: f.ind1,
                    ind2: f.ind2,
                    subfields: f.subfields.map(sf => [sf[0], sf[1]])
                });
            });

        this.net.request('open-ils.cat',
            'open-ils.cat.authority.validate.bib_field', fields)
            .subscribe(checkedField => {
                const bibField = this.record.fields
                    .filter(f => f.fieldId === +checkedField.id)[0];

                bibField.authChecked = true;
                bibField.authValid = checkedField.valid;
            });
    }

    isControlledBibTag(tag: string): boolean {
        return this.controlledBibTags && this.controlledBibTags.includes(tag);
    }

    openLinkerDialog(field: MarcField) {
        this.authLinker.bibField = field;
        this.authLinker.open({size: 'xl'}).subscribe(newField => {

            // The presence of newField here means the linker wants to
            // replace the field with a new field from the authority
            // record.  Otherwise, the original field may have been
            // directly modified or the dialog canceled.
            if (!newField) { return; }

            // Performs an insert followed by a delete, so the two
            // fields can be tracked separately for undo/redo actions.
            const marcField = this.record.newField(newField);
            this.context.insertField(field, marcField);
            this.context.deleteField(field);

            // Mark the insert and delete as an atomic undo/redo action.
            this.context.setUndoGroupSize(2);
        });
    }

    // 007 Physical characteristics wizard.
    openPhysCharDialog(field: MarcField) {
        this.physCharDialog.fieldData = field.data;

        this.physCharDialog.open({size: 'lg'}).subscribe(
            newData => {
                if (newData) {
                    this.context.requestFieldFocus({
                        fieldId: field.fieldId,
                        target: 'cfld',
                        newText: newData
                    });
                }
            }
        );
    }

    showCharMap($event) {
        // prevent S key from being picked up by the modal's keydown listener
        $event.preventDefault();
        this.CharMapDialog.open({size: 'xl'}).subscribe();
    }

    showHelp(field) {
        /* Conditions where help should not be shown:
         - if the showHelp toggle is off
         - if the user is typing a new tag and hasn't reached 3 characters
         - if the tag is 999 (the dummy value for adding a new field)
         - if this tag is the same as the next field's; we show help only once
           per group of adjacent repeated fields
        */
        const length = 3;
        const tag = 999;
        if (this.context.showHelp &&
        field.tag.length === length &&
        field.tag !== tag &&
        field.tag !== this.getNextTag(field.fieldId)) {
            return true;
        }

        return false;
    }

    // Set field height and width properties based on content length.
    // This is used as a preferred size, but CSS max-height and max-width may override.

    fieldSize(contents: string) {
        let styles = {};
        if ( contents.length < this.sizeThreshold ) {
            const roomForCursor = 3;
            styles = { 'width': (contents.length + roomForCursor) + 'ch' };
        } else {
            const minHeight = 3;
            const minWidth = 30;
            const height = Math.max(minHeight, Math.ceil(contents.length / this.sizeThreshold));
            const width = Math.max(minWidth, Math.ceil(contents.length / height));
            styles = {
                'height': height + 'lh',
                'width': width + 'ch'
            };
        }

        return styles;
    }
}



