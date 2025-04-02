import {EventEmitter} from '@angular/core';
import {MarcRecord, MarcField, MarcSubfield} from './marcrecord';
import {NgbPopover} from '@ng-bootstrap/ng-bootstrap';
import {TagTable} from './tagtable.service';

const MARC_RECORD_TYPES: 'biblio' | 'authority' | 'serial' | 'lineitem' = null;

export type MARC_RECORD_TYPE = typeof MARC_RECORD_TYPES;

/* Per-instance MARC editor context. */

const STUB_DATA_00X = '                                        ';

export type MARC_EDITABLE_FIELD_TYPE =
    'ldr' | 'tag' | 'cfld' | 'ind1' | 'ind2' | 'sfc' | 'sfv' | 'ffld';

export interface FieldFocusRequest {
    fieldId: number;
    target: MARC_EDITABLE_FIELD_TYPE | 'group' | 'move';
    sfOffset?: number; // focus a specific subfield by its offset
    ffCode?: string; // fixed field code

    // If set, an external source wants to modify the text content
    // of an editable component (in a way that retains undo/redo
    // functionality).
    newText?: string;
}

export class UndoRedoAction {
    // Which point in the record was modified.
    position: FieldFocusRequest;

    // Which stack do we toss this on once it's been applied?
    isRedo: boolean;

    // Grouped actions are tracked as multiple undo / redo actions, but
    // are done and un-done as a unit.
    groupSize?: number;

    // Was the action just a move?
    wasMove: boolean;
}

export class TextUndoRedoAction extends UndoRedoAction {
    textContent: string;
}

export class StructUndoRedoAction extends UndoRedoAction {
    /* Add or remove a part of the record (field, subfield, etc.) */

    // Does this action track an addition or deletion.
    wasAddition: boolean;

    // Field to add/delete or field to modify for subfield adds/deletes
    field: MarcField;

    // If this is a subfield modification.
    subfield: MarcSubfield;

    // Position preceding the modified position to mark the position
    // of deletion recovery.
    prevPosition: FieldFocusRequest;

    // Location of the cursor at time of initial action.
    prevFocus: FieldFocusRequest;

    // Previous index of the field in the record (for field moves)
    prevIndex: number;
}


export class MarcEditContext {

    recordChange: EventEmitter<MarcRecord>;
    fieldFocusRequest: EventEmitter<FieldFocusRequest>;
    textUndoRedoRequest: EventEmitter<TextUndoRedoAction>;
    recordType: MARC_RECORD_TYPE;

    lastFocused: FieldFocusRequest = null;

    undoStack: UndoRedoAction[] = [];
    redoStack: UndoRedoAction[] = [];

    tagTable: TagTable;

    // True if any changes have been made.
    // For the 'rich' editor, this is any un-do-able actions.
    // For the text editor it's any text change.
    changesPending: boolean;

    showHelp = false;

    private _record: MarcRecord;
    set record(r: MarcRecord) {
        if (r !== this._record) {
            this._record = r;
            this._record.stampFieldIds();
            this.recordChange.emit(r);
        }
    }

    get record(): MarcRecord {
        return this._record;
    }

    constructor() {
        this.recordChange = new EventEmitter<MarcRecord>();
        this.fieldFocusRequest = new EventEmitter<FieldFocusRequest>();
        this.textUndoRedoRequest = new EventEmitter<TextUndoRedoAction>();
    }

    requestFieldFocus(req: FieldFocusRequest) {
        // timeout allows for new components to be built before the
        // focus request is emitted.
        if (req) {
            if (req.target === 'group') {
                setTimeout(() => {
                    const sfGroup = document.getElementById('subfield-'+req.sfOffset) as HTMLElement;
                    if (sfGroup) {
                        sfGroup.focus();
                    }
                });
            }
            if (req.target === 'move') {
                this.focusAfterMove(req.fieldId);
            }
            setTimeout(() => this.fieldFocusRequest.emit(req));
        }
    }

    // Move fields via drag and drop
    moveField(moveFrom: number, moveTo: number, field: MarcField, skipTracking?: boolean) {
        if (moveTo > this.record.fields.length) {
            moveTo = this.record.fields.length;
        }
        // TODO: change this to ARIA announcement
        console.debug('Moving ' + moveFrom + ' to ' + moveTo);
        this.record.fields.splice(moveTo, 0, this.record.fields.splice(moveFrom, 1)[0]);
        if (!skipTracking) {
            this.trackMoveUndo(field, moveFrom);
        }

    }

    resetUndos() {
        this.undoStack = [];
        this.redoStack = [];
    }

    requestUndo() {
        let remaining = null;

        do {
            const action = this.undoStack.shift();
            if (!action) { return; }

            if (remaining === null) {
                remaining = action.groupSize || 1;
            }
            remaining--;

            action.isRedo = false;
            this.distributeUndoRedo(action);

        } while (remaining > 0);
    }

    requestRedo() {
        let remaining = null;

        do {
            const action = this.redoStack.shift();
            if (!action) { return; }

            if (remaining === null) {
                remaining = action.groupSize || 1;
            }
            remaining--;

            action.isRedo = true;
            this.distributeUndoRedo(action);

        } while (remaining > 0);
    }

    // Calculate stack action count taking groupSize (atomic action
    // sets) into consideration.
    stackCount(stack: UndoRedoAction[]): number {
        let size = 0;
        let skip = 0;

        stack.forEach(action => {
            if (action.groupSize > 1) {
                if (skip) { return; }
                skip = 1;
            } else {
                skip = 0;
            }
            size++;
        });

        return size;
    }

    undoCount(): number {
        return this.stackCount(this.undoStack);
    }

    redoCount(): number {
        return this.stackCount(this.redoStack);
    }

    // Stamp the most recent 'size' entries in the undo stack
    // as being an atomic undo/redo set.
    setUndoGroupSize(size: number) {
        for (let idx = 0; idx < size; idx++) {
            if (this.undoStack[idx]) {
                this.undoStack[idx].groupSize = size;
            }
        }
    }

    distributeUndoRedo(action: UndoRedoAction) {
        if (action instanceof TextUndoRedoAction) {
            // Let the editable content component handle it.
            this.textUndoRedoRequest.emit(action);
        } else {
            // Manage structural changes within
            this.handleStructuralUndoRedo(action as StructUndoRedoAction);
        }
    }

    addToUndoStack(action: UndoRedoAction) {
        this.changesPending = true;
        this.undoStack.unshift(action);
    }

    handleStructuralUndoRedo(action: StructUndoRedoAction) {

        // Handle moves first, since they don't involve adding or deleting anything
        if (action.wasMove) {
            const currentIndex = this.record.fields.indexOf(action.field);
            this.moveField(currentIndex, action.prevIndex, action.field, true);
            this.focusAfterMove(action.field.fieldId);
        } else {
            if (action.wasAddition) {
                // Remove the added field

                if (action.subfield) {
                    const prevPos = action.subfield[2] - 1;
                    action.field.deleteExactSubfields(action.subfield);
                    this.focusSubfield(action.field, prevPos, true);

                } else {
                    this.record.deleteFields(action.field);
                }

                // When deleting chunks, always return focus to the
                // pre-insert position.
                this.requestFieldFocus(action.prevFocus);

            } else {
                // Re-insert the removed field and focus it.

                if (action.subfield) {

                    this.insertSubfield(action.field, action.subfield, true);
                    this.focusSubfield(action.field, action.subfield[2]);

                } else {

                    const fieldId = action.position.fieldId;
                    const prevField =
                        this.record.getField(action.prevPosition.fieldId);

                    this.record.insertFieldsAfter(prevField, action.field);

                    // Recover the original fieldId, which gets re-stamped
                    // in this.record.insertFields* calls.
                    action.field.fieldId = fieldId;

                    // Focus the newly recovered field.
                    this.requestFieldFocus(action.position);
                }

                // When inserting chunks, track the location where the
                // insert was requested so we can return the cursor so we
                // can return the cursor to the scene of the crime if the
                // undo is re-done or vice versa.  This is primarily useful
                // when performing global inserts like add00X, which can be
                // done without the 00X field itself having focus.
                action.prevFocus = this.lastFocused;
            }

            action.wasAddition = !action.wasAddition;
        }

        const moveTo = action.isRedo ? this.undoStack : this.redoStack;

        moveTo.unshift(action);
    }

    trackMoveUndo(field: MarcField, prevIndex: number) {
        const position: FieldFocusRequest = {fieldId: field?.fieldId, target: 'move'};

        const action = new StructUndoRedoAction();
        action.field = field;
        action.wasMove = true;
        action.prevIndex = prevIndex;
        action.wasAddition = null;
        action.position = position;

        this.addToUndoStack(action);
    }

    trackStructuralUndo(field: MarcField, isAddition: boolean, subfield?: MarcSubfield) {

        // Human-driven changes invalidate the redo stack.
        this.redoStack = [];

        const position: FieldFocusRequest = {fieldId: field.fieldId, target: 'tag'};

        let prevPos: FieldFocusRequest = null;

        if (subfield) {
            position.target = 'sfc';
            position.sfOffset = subfield[2];

        } else {
            // No need to track the previous field for subfield mods.

            const prevField = this.record.getPreviousField(field.fieldId);
            if (prevField) {
                prevPos = {fieldId: prevField.fieldId, target: 'tag'};
            }
        }

        const action = new StructUndoRedoAction();
        action.field = field;
        action.subfield = subfield;
        action.wasAddition = isAddition;
        action.position = position;
        action.prevPosition = prevPos;

        // For bulk adds (e.g. add a whole row) the field focused at
        // time of action will be different than the added field.
        action.prevFocus = this.lastFocused;

        this.addToUndoStack(action);
    }

    deleteField(field: MarcField) {
        this.trackStructuralUndo(field, false);

        if (!this.focusNextTag(field)) {
            this.focusPreviousTag(field);
        }

        this.record.deleteFields(field);
    }

    add00X(tag: string) {

        const field: MarcField =
            this.record.newField({tag : tag, data : STUB_DATA_00X});

        this.record.insertOrderedFields(field);

        this.trackStructuralUndo(field, true);

        this.focusTag(field);
    }

    insertReplace008() {

        // delete all of the 008s
        [].concat(this.record.field('008', true)).forEach(f => {
            this.trackStructuralUndo(f, false);
            this.record.deleteFields(f);
        });

        const field = this.record.newField({
            tag : '008', data : this.record.generate008()});

        this.record.insertOrderedFields(field);

        this.trackStructuralUndo(field, true);

        this.focusTag(field);
    }

    // Add stub field before or after the context field
    insertStubField(field: MarcField, before?: boolean) {

        const newField = this.record.newField(
            {tag: '999', subfields: [[' ', '', 0]]});

        this.insertField(field, newField, before);
    }

    insertField(contextField: MarcField, newField: MarcField, before?: boolean) {

        if (before) {
            this.record.insertFieldsBefore(contextField, newField);
            this.focusPreviousTag(contextField);

        } else {
            this.record.insertFieldsAfter(contextField, newField);
            this.focusNextTag(contextField);
        }

        this.trackStructuralUndo(newField, true);
    }

    // Adds a new empty subfield to the provided field at the
    // requested subfield position
    insertSubfield(field: MarcField,
        subfield: MarcSubfield, skipTracking?: boolean) {
        const position = subfield[2];


        // array index 3 contains that position of the subfield
        // in the MARC field.  When splicing a new subfield into
        // the set, be sure the any that come after the new one
        // have their positions bumped to reflect the shift.
        field.subfields.forEach(
            sf => {if (sf[2] >= position) { sf[2]++; }});

        field.subfields.splice(position, 0, subfield);

        if (!skipTracking) {
            this.focusSubfield(field, position);
            this.trackStructuralUndo(field, true, subfield);
        }
    }

    insertStubSubfield(field: MarcField, position: number) {
        const newSf: MarcSubfield = [' ', '', position];
        this.insertSubfield(field, newSf);
    }

    // Focus the requested subfield by its position.
    focusSubfield(field: MarcField, position: number, group?: boolean) {
        // console.debug("focusSubfield()", field, position, group);
        const focus: FieldFocusRequest = {fieldId: field.fieldId, target: 'sfv'};

        if (group) {
            focus.target = 'group';
        } else if (position < 0) {
            // Focus the code instead of the value
            focus.target = 'sfc';
        }

        focus.sfOffset = position;

        this.requestFieldFocus(focus);
    }

    deleteSubfield(field: MarcField, subfield: MarcSubfield) {
        const sfpos = subfield[2] - 1; // previous subfield

        this.trackStructuralUndo(field, false, subfield);

        field.deleteExactSubfields(subfield);

        this.focusSubfield(field, sfpos, true);
    }

    focusTag(field: MarcField) {
        this.requestFieldFocus({fieldId: field.fieldId, target: 'tag'});
    }

    // Returns true if the field has a next tag to focus
    focusNextTag(field: MarcField): boolean {
        const nextField = this.record.getNextField(field.fieldId);
        if (nextField) {
            this.focusTag(nextField);
            return true;
        }
        return false;
    }

    // Returns true if the field has a previous tag to focus
    focusPreviousTag(field: MarcField): boolean {
        const prevField = this.record.getPreviousField(field.fieldId);
        if (prevField) {
            this.focusTag(prevField);
            return true;
        }
        return false;
    }

    // focus on the Move button
    focusAfterMove(fieldId: number, $event?: any) {
        if ($event) {$event.preventDefault();}

        const move = document.getElementById('move-btn-'+fieldId) as HTMLElement;
        if (move) {
            // setTimeout() prevents random loss of focus during DOM updates
            setTimeout(() => move.focus());
        }
    }

    subfieldHasFocus(field: MarcField, subfield: MarcSubfield): boolean {
        if (!this.lastFocused) {return false;}

        if (this.lastFocused.fieldId === field.fieldId &&
            this.lastFocused.sfOffset === subfield[2]) {
            return true;
        }

        return false;
    }

    // forces full width layout for all 5xx fields
    // and a handful of other subfields
    isFullWidth(tag: string, subfieldCode: string): boolean {
        if (tag.substring(0,1) === '5') {return true;}

        let fullWidth = false;
        switch (subfieldCode) {
            case 'a':
                if (tag === '963') {fullWidth = true;}
                break;
            case 'n':
                if (['533','993'].includes(tag)) {fullWidth = true;}
                break;
            case 't':
                if (['780','787'].includes(tag)) {fullWidth = true;}
                break;
            /*
            case 'u':
                fullWidth = true;
                break;
            /**/
        }

        return fullWidth;
    }
}

