/**
 * Collection of grid related classses and interfaces.
 */
import {TemplateRef, EventEmitter} from '@angular/core';
import {Observable, Subscription} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {FormatService} from '@eg/core/format.service';
import {Pager} from '@eg/share/util/pager';

const MAX_ALL_ROW_COUNT = 10000;

export class GridColumn {
    name: string;
    path: string;
    label: string;
    flex: number;
    align: string;
    hidden: boolean;
    visible: boolean;
    sort: number;
    // IDL class of the object which contains this field.
    // Not to be confused with the class of a linked object.
    idlClass: string;
    idlFieldDef: any;
    datatype: string;
    datePlusTime: boolean;
    cellTemplate: TemplateRef<any>;
    cellContext: any;
    isIndex: boolean;
    isDragTarget: boolean;
    isSortable: boolean;
    isMultiSortable: boolean;
    comparator: (valueA: any, valueB: any) => number;

    // True if the column was automatically generated.
    isAuto: boolean;

    flesher: (obj: any, col: GridColumn, item: any) => any;

    getCellContext(row: any) {
        return {
          col: this,
          row: row,
          userContext: this.cellContext
        };
    }
}

export class GridColumnSet {
    columns: GridColumn[];
    idlClass: string;
    indexColumn: GridColumn;
    isSortable: boolean;
    isMultiSortable: boolean;
    stockVisible: string[];
    idl: IdlService;
    defaultHiddenFields: string[];
    defaultVisibleFields: string[];

    constructor(idl: IdlService, idlClass?: string) {
        this.idl = idl;
        this.columns = [];
        this.stockVisible = [];
        this.idlClass = idlClass;
    }

    add(col: GridColumn) {

        this.applyColumnDefaults(col);

        if (!this.insertColumn(col)) {
            // Column was rejected as a duplicate.
            return;
        }

        if (col.isIndex) { this.indexColumn = col; }

        // track which fields are visible on page load.
        if (col.visible) {
            this.stockVisible.push(col.name);
        }

        this.applyColumnSortability(col);
    }

    // Returns true if the new column was inserted, false otherwise.
    // Declared columns take precedence over auto-generated columns
    // when collisions occur.
    // Declared columns are inserted in front of auto columns.
    insertColumn(col: GridColumn): boolean {

        if (col.isAuto) {
            if (this.getColByName(col.name)) {
                // New auto-generated column conflicts with existing
                // column.  Skip it.
                return false;
            } else {
                // No collisions.  Add to the end of the list
                this.columns.push(col);
                return true;
            }
        }

        // Adding a declared column.

        // Check for dupes.
        for (let idx = 0; idx < this.columns.length; idx++) {
            const testCol = this.columns[idx];
            if (testCol.name === col.name) { // match found
                if (testCol.isAuto) {
                    // new column takes precedence, remove the existing column.
                    this.columns.splice(idx, 1);
                    break;
                } else {
                    // New column does not take precedence.  Avoid
                    // inserting it.
                    return false;
                }
            }
        }

        // Delcared columns are inserted just before the first auto-column
        for (let idx = 0; idx < this.columns.length; idx++) {
            const testCol = this.columns[idx];
            if (testCol.isAuto) {
                if (idx === 0) {
                    this.columns.unshift(col);
                } else {
                    this.columns.splice(idx - 1, 0, col);
                }
                return true;
            }
        }

        // No insertion point found.  Toss the new column on the end.
        this.columns.push(col);
        return true;
    }

    getColByName(name: string): GridColumn {
        return this.columns.filter(c => c.name === name)[0];
    }

    idlInfoFromDotpath(dotpath: string): any {
        if (!dotpath || !this.idlClass) { return null; }

        let idlParent;
        let idlField;
        let idlClass = this.idl.classes[this.idlClass];

        const pathParts = dotpath.split(/\./);

        for (let i = 0; i < pathParts.length; i++) {
            const part = pathParts[i];
            idlParent = idlField;
            idlField = idlClass.field_map[part];

            if (idlField) {
                if (idlField['class'] && (
                    idlField.datatype === 'link' ||
                    idlField.datatype === 'org_unit')) {
                    idlClass = this.idl.classes[idlField['class']];
                }
            } else {
                return null;
            }
        }

        return {
            idlParent: idlParent,
            idlField : idlField,
            idlClass : idlClass
        };
    }


    reset() {
        this.columns.forEach(col => {
            col.flex = 2;
            col.sort = 0;
            col.align = 'left';
            col.visible = this.stockVisible.includes(col.name);
        });
    }

    applyColumnDefaults(col: GridColumn) {

        if (!col.idlFieldDef && col.path) {
            const idlInfo = this.idlInfoFromDotpath(col.path);
            if (idlInfo) {
                col.idlFieldDef = idlInfo.idlField;
                col.idlClass = idlInfo.idlClass.name;
                if (!col.label) {
                    col.label = col.idlFieldDef.label || col.idlFieldDef.name;
                    col.datatype = col.idlFieldDef.datatype;
                }
            }
        }

        if (!col.name) { col.name = col.path; }
        if (!col.flex) { col.flex = 2; }
        if (!col.align) { col.align = 'left'; }
        if (!col.label) { col.label = col.name; }
        if (!col.datatype) { col.datatype = 'text'; }

        col.visible = !col.hidden;
    }

    applyColumnSortability(col: GridColumn) {
        // column sortability defaults to the sortability of the column set.
        if (col.isSortable === undefined && this.isSortable) {
            col.isSortable = true;
        }

        if (col.isMultiSortable === undefined && this.isMultiSortable) {
            col.isMultiSortable = true;
        }

        if (col.isMultiSortable) {
            col.isSortable = true;
        }
    }

    displayColumns(): GridColumn[] {
        return this.columns.filter(c => c.visible);
    }

    insertBefore(source: GridColumn, target: GridColumn) {
        let targetIdx = -1;
        let sourceIdx = -1;
        this.columns.forEach((col, idx) => {
            if (col.name === target.name) { targetIdx = idx; }});

        this.columns.forEach((col, idx) => {
            if (col.name === source.name) { sourceIdx = idx; }});

        if (sourceIdx >= 0) {
            this.columns.splice(sourceIdx, 1);
        }

        this.columns.splice(targetIdx, 0, source);
    }

    // Move visible columns to the front of the list.
    moveVisibleToFront() {
        const newCols = this.displayColumns();
        this.columns.forEach(col => {
            if (!col.visible) { newCols.push(col); }});
        this.columns = newCols;
    }

    moveColumn(col: GridColumn, diff: number) {
        let srcIdx, targetIdx;

        this.columns.forEach((c, i) => {
          if (c.name === col.name) { srcIdx = i; }
        });

        targetIdx = srcIdx + diff;
        if (targetIdx < 0) {
            targetIdx = 0;
        } else if (targetIdx >= this.columns.length) {
            // Target index follows the last visible column.
            let lastVisible = 0;
            this.columns.forEach((c, idx) => {
                if (c.visible) { lastVisible = idx; }
            });

            // When moving a column (down) causes one or more
            // visible columns to shuffle forward, our column
            // moves into the slot of the last visible column.
            // Otherwise, put it into the slot directly following
            // the last visible column.
            targetIdx = srcIdx <= lastVisible ? lastVisible : lastVisible + 1;
        }

        // Splice column out of old position, insert at new position.
        this.columns.splice(srcIdx, 1);
        this.columns.splice(targetIdx, 0, col);
    }

    compileSaveObject(): GridColumnPersistConf[] {
        // only store information about visible columns.
        // scrunch the data down to just the needed info.
        return this.displayColumns().map(col => {
            const c: GridColumnPersistConf = {name : col.name};
            if (col.align !== 'left') { c.align = col.align; }
            if (col.flex !== 2) { c.flex = Number(col.flex); }
            if (Number(col.sort)) { c.sort = Number(c.sort); }
            return c;
        });
    }

    applyColumnSettings(conf: GridColumnPersistConf[]) {

        if (!conf || conf.length === 0) {
            // No configuration is available, but we have a list of
            // fields to show or hide by default

            if (this.defaultVisibleFields) {
                this.columns.forEach(col => {
                    if (this.defaultVisibleFields.includes(col.name)) {
                        col.visible = true;
                    } else {
                        col.visible = false;
                    }
                });

            } else if (this.defaultHiddenFields) {
                this.defaultHiddenFields.forEach(name => {
                    const col = this.getColByName(name);
                    if (col) {
                        col.visible = false;
                    }
                });
            }

            return;
        }

        const newCols = [];

        conf.forEach(colConf => {
            const col = this.getColByName(colConf.name);
            if (!col) { return; } // no such column in this grid.

            col.visible = true;
            if (colConf.align) { col.align = colConf.align; }
            if (colConf.flex)  { col.flex = Number(colConf.flex); }
            if (colConf.sort)  { col.sort = Number(colConf.sort); }

            // Add to new columns array, avoid dupes.
            if (newCols.filter(c => c.name === col.name).length === 0) {
                newCols.push(col);
            }
        });

        // columns which are not expressed within the saved
        // configuration are marked as non-visible and
        // appended to the end of the new list of columns.
        this.columns.forEach(c => {
            if (conf.filter(cf => cf.name === c.name).length === 0) {
                c.visible = false;
                newCols.push(c);
            }
        });

        this.columns = newCols;
    }
}


export class GridRowSelector {
    indexes: {[string: string]: boolean};

    constructor() {
        this.clear();
    }

    // Returns true if all of the requested indexes exist in the selector.
    contains(index: string | string[]): boolean {
        const indexes = [].concat(index);
        for (let i = 0; i < indexes.length; i++) { // early exit
            if (!this.indexes[indexes[i]]) {
                return false;
            }
        }
        return true;
    }

    select(index: string | string[]) {
        const indexes = [].concat(index);
        indexes.forEach(i => this.indexes[i] = true);
    }

    deselect(index: string | string[]) {
        const indexes = [].concat(index);
        indexes.forEach(i => delete this.indexes[i]);
    }

    // Returns the list of selected index values.
    // in some contexts (template checkboxes) the value for an index is
    // set to false to deselect instead of having it removed (via deselect()).
    selected() {
        return Object.keys(this.indexes).filter(
            ind => Boolean(this.indexes[ind]));
    }

    isEmpty(): boolean {
        return this.selected().length === 0;
    }

    clear() {
        this.indexes = {};
    }
}

export interface GridRowFlairEntry {
    icon: string;   // name of material icon
    title?: string;  // tooltip string
}

export class GridColumnPersistConf {
    name: string;
    flex?: number;
    sort?: number;
    align?: string;
}

export class GridPersistConf {
    version: number;
    limit: number;
    columns: GridColumnPersistConf[];
}

export class GridContext {

    pager: Pager;
    idlClass: string;
    isSortable: boolean;
    isMultiSortable: boolean;
    useLocalSort: boolean;
    persistKey: string;
    disableMultiSelect: boolean;
    disableSelect: boolean;
    dataSource: GridDataSource;
    columnSet: GridColumnSet;
    rowSelector: GridRowSelector;
    toolbarButtons: GridToolbarButton[];
    toolbarCheckboxes: GridToolbarCheckbox[];
    toolbarActions: GridToolbarAction[];
    lastSelectedIndex: any;
    pageChanges: Subscription;
    rowFlairIsEnabled: boolean;
    rowFlairCallback: (row: any) => GridRowFlairEntry;
    rowClassCallback: (row: any) => string;
    cellClassCallback: (row: any, col: GridColumn) => string;
    defaultVisibleFields: string[];
    defaultHiddenFields: string[];
    overflowCells: boolean;
    showLinkSelectors: boolean;

    // Services injected by our grid component
    idl: IdlService;
    org: OrgService;
    store: ServerStoreService;
    format: FormatService;

    constructor(
        idl: IdlService,
        org: OrgService,
        store: ServerStoreService,
        format: FormatService) {

        this.idl = idl;
        this.org = org;
        this.store = store;
        this.format = format;
        this.pager = new Pager();
        this.pager.limit = 10;
        this.rowSelector = new GridRowSelector();
        this.toolbarButtons = [];
        this.toolbarCheckboxes = [];
        this.toolbarActions = [];
    }

    init() {
        this.columnSet = new GridColumnSet(this.idl, this.idlClass);
        this.columnSet.isSortable = this.isSortable === true;
        this.columnSet.isMultiSortable = this.isMultiSortable === true;
        this.columnSet.defaultHiddenFields = this.defaultHiddenFields;
        this.columnSet.defaultVisibleFields = this.defaultVisibleFields;
        this.generateColumns();
    }

    // Load initial settings and data.
    initData() {
        this.applyGridConfig()
        .then(ok => this.dataSource.requestPage(this.pager))
        .then(ok => this.listenToPager());
    }

    destroy() {
        this.ignorePager();
    }

    applyGridConfig(): Promise<void> {
        return this.getGridConfig(this.persistKey)
        .then(conf => {
            let columns = [];
            if (conf) {
                columns = conf.columns;
                if (conf.limit) {
                    this.pager.limit = conf.limit;
                }
            }

            // This is called regardless of the presence of saved
            // settings so defaults can be applied.
            this.columnSet.applyColumnSettings(columns);
        });
    }

    reload() {
        // Give the UI time to settle before reloading grid data.
        // This can help when data retrieval depends on a value
        // getting modified by an angular digest cycle.
        setTimeout(() => {
            this.pager.reset();
            this.dataSource.reset();
            this.dataSource.requestPage(this.pager);
        });
    }

    // Sort the existing data source instead of requesting sorted
    // data from the client.  Reset pager to page 1.  As with reload(),
    // give the client a chance to setting before redisplaying.
    sortLocal() {
        setTimeout(() => {
            this.pager.reset();
            this.sortLocalData();
            this.dataSource.requestPage(this.pager);
        });
    }

    // Subscribe or unsubscribe to page-change events from the pager.
    listenToPager() {
        if (this.pageChanges) { return; }
        this.pageChanges = this.pager.onChange$.subscribe(
            val => this.dataSource.requestPage(this.pager));
    }

    ignorePager() {
        if (!this.pageChanges) { return; }
        this.pageChanges.unsubscribe();
        this.pageChanges = null;
    }

    // Sort data in the data source array
    sortLocalData() {

        const sortDefs = this.dataSource.sort.map(sort => {
            const column = this.columnSet.getColByName(sort.name);

            const def = {
                name: sort.name,
                dir: sort.dir,
                col: column
            };

            if (!def.col.comparator) {
                switch (def.col.datatype) {
                    case 'id':
                    case 'money':
                    case 'int':
                        def.col.comparator = (a, b) => {
                            a = Number(a);
                            b = Number(b);
                            if (a < b) { return -1; }
                            if (a > b) { return 1; }
                            return 0;
                        };
                        break;
                    default:
                        def.col.comparator = (a, b) => {
                            if (a < b) { return -1; }
                            if (a > b) { return 1; }
                            return 0;
                        };
                }
            }

            return def;
        });

        this.dataSource.data.sort((rowA, rowB) => {

            for (let idx = 0; idx < sortDefs.length; idx++) {
                const sortDef = sortDefs[idx];

                const valueA = this.getRowColumnValue(rowA, sortDef.col);
                const valueB = this.getRowColumnValue(rowB, sortDef.col);

                if (valueA === '' && valueB === '') { continue; }
                if (valueA === '' && valueB !== '') { return 1; }
                if (valueA !== '' && valueB === '') { return -1; }

                const diff = sortDef.col.comparator(valueA, valueB);
                if (diff === 0) { continue; }

                return sortDef.dir === 'DESC' ? -diff : diff;
            }

            return 0; // No differences found.
        });
    }

    getRowIndex(row: any): any {
        const col = this.columnSet.indexColumn;
        if (!col) {
            throw new Error('grid index column required');
        }
        return this.getRowColumnValue(row, col);
    }

    // Returns position in the data source array of the row with
    // the provided index.
    getRowPosition(index: any): number {
        // for-loop for early exit
        for (let idx = 0; idx < this.dataSource.data.length; idx++) {
            const row = this.dataSource.data[idx];
            if (row !== undefined && index === this.getRowIndex(row)) {
                return idx;
            }
        }
    }

    // Return the row with the provided index.
    getRowByIndex(index: any): any {
        for (let idx = 0; idx < this.dataSource.data.length; idx++) {
            const row = this.dataSource.data[idx];
            if (row !== undefined && index === this.getRowIndex(row)) {
                return row;
            }
        }
    }

    // Returns all selected rows, regardless of whether they are
    // currently visible in the grid display.
    getSelectedRows(): any[] {
        const selected = [];
        this.rowSelector.selected().forEach(index => {
            const row = this.getRowByIndex(index);
            if (row) {
                selected.push(row);
            }
        });
        return selected;
    }

    getRowColumnValue(row: any, col: GridColumn): string {
        let val;

        if (col.path) {
            val = this.nestedItemFieldValue(row, col);
        } else if (col.name in row) {
            val = this.getObjectFieldValue(row, col.name);
        }

        return this.format.transform({
            value: val,
            idlClass: col.idlClass,
            idlField: col.idlFieldDef ? col.idlFieldDef.name : col.name,
            datatype: col.datatype,
            datePlusTime: Boolean(col.datePlusTime)
        });
    }

    getObjectFieldValue(obj: any, name: string): any {
        if (typeof obj[name] === 'function') {
            return obj[name]();
        } else {
            return obj[name];
        }
    }

    nestedItemFieldValue(obj: any, col: GridColumn): string {

        let idlField;
        let idlClassDef;
        const original = obj;
        const steps = col.path.split('.');

        for (let i = 0; i < steps.length; i++) {
            const step = steps[i];

            if (obj === null || obj === undefined || typeof obj !== 'object') {
                // We have run out of data to step through before
                // reaching the end of the path.  Conclude fleshing via
                // callback if provided then exit.
                if (col.flesher && obj !== undefined) {
                    return col.flesher(obj, col, original);
                }
                return obj;
            }

            const class_ = obj.classname;
            if (class_ && (idlClassDef = this.idl.classes[class_])) {
                idlField = idlClassDef.field_map[step];
            }

            obj = this.getObjectFieldValue(obj, step);
        }

        // We found a nested IDL object which may or may not have
        // been configured as a top-level column.  Flesh the column
        // metadata with our newly found IDL info.
        if (idlField) {
            if (!col.datatype) {
                col.datatype = idlField.datatype;
            }
            if (!col.idlFieldDef) {
                idlField = col.idlFieldDef;
            }
            if (!col.idlClass) {
                col.idlClass = idlClassDef.name;
            }
            if (!col.label) {
                col.label = idlField.label || idlField.name;
            }
        }

        return obj;
    }


    getColumnTextContent(row: any, col: GridColumn): string {
        if (col.cellTemplate) {
            // TODO
            // Extract the text content from the rendered template.
        } else {
            return this.getRowColumnValue(row, col);
        }
    }

    selectOneRow(index: any) {
        this.rowSelector.clear();
        this.rowSelector.select(index);
        this.lastSelectedIndex = index;
    }

    // selects or deselects an item, without affecting the others.
    // returns true if the item is selected; false if de-selected.
    toggleSelectOneRow(index: any) {
        if (this.rowSelector.contains(index)) {
            this.rowSelector.deselect(index);
            return false;
        }

        this.rowSelector.select(index);
        return true;
    }

    selectRowByPos(pos: number) {
        const row = this.dataSource.data[pos];
        if (row) {
            this.selectOneRow(this.getRowIndex(row));
        }
    }

    selectPreviousRow() {
        if (!this.lastSelectedIndex) { return; }
        const pos = this.getRowPosition(this.lastSelectedIndex);
        if (pos === this.pager.offset) {
            this.toPrevPage().then(ok => this.selectLastRow(), err => {});
        } else {
            this.selectRowByPos(pos - 1);
        }
    }

    selectNextRow() {
        if (!this.lastSelectedIndex) { return; }
        const pos = this.getRowPosition(this.lastSelectedIndex);
        if (pos === (this.pager.offset + this.pager.limit - 1)) {
            this.toNextPage().then(ok => this.selectFirstRow(), err => {});
        } else {
            this.selectRowByPos(pos + 1);
        }
    }

    selectFirstRow() {
        this.selectRowByPos(this.pager.offset);
    }

    selectLastRow() {
        this.selectRowByPos(this.pager.offset + this.pager.limit - 1);
    }

    toPrevPage(): Promise<any> {
        if (this.pager.isFirstPage()) {
            return Promise.reject('on first');
        }
        // temp ignore pager events since we're calling requestPage manually.
        this.ignorePager();
        this.pager.decrement();
        this.listenToPager();
        return this.dataSource.requestPage(this.pager);
    }

    toNextPage(): Promise<any> {
        if (this.pager.isLastPage()) {
            return Promise.reject('on last');
        }
        // temp ignore pager events since we're calling requestPage manually.
        this.ignorePager();
        this.pager.increment();
        this.listenToPager();
        return this.dataSource.requestPage(this.pager);
    }

    getAllRows(): Promise<any> {
        const pager = new Pager();
        pager.offset = 0;
        pager.limit = MAX_ALL_ROW_COUNT;
        return this.dataSource.requestPage(pager);
    }

    // Returns a key/value pair object of visible column data as text.
    getRowAsFlatText(row: any): any {
        const flatRow = {};
        this.columnSet.displayColumns().forEach(col => {
            flatRow[col.name] =
                this.getColumnTextContent(row, col);
        });
        return flatRow;
    }

    getAllRowsAsText(): Observable<any> {
        return Observable.create(observer => {
            this.getAllRows().then(ok => {
                this.dataSource.data.forEach(row => {
                    observer.next(this.getRowAsFlatText(row));
                });
                observer.complete();
            });
        });
    }

    gridToCsv(): Promise<string> {

        let csvStr = '';
        const columns = this.columnSet.displayColumns();

        // CSV header
        columns.forEach(col => {
            csvStr += this.valueToCsv(col.label),
            csvStr += ',';
        });

        csvStr = csvStr.replace(/,$/, '\n');

        return new Promise(resolve => {
            this.getAllRowsAsText().subscribe(
                row => {
                    columns.forEach(col => {
                        csvStr += this.valueToCsv(row[col.name]);
                        csvStr += ',';
                    });
                    csvStr = csvStr.replace(/,$/, '\n');
                },
                err => {},
                ()  => resolve(csvStr)
            );
        });
    }


    // prepares a string for inclusion within a CSV document
    // by escaping commas and quotes and removing newlines.
    valueToCsv(str: string): string {
        str = '' + str;
        if (!str) { return ''; }
        str = str.replace(/\n/g, '');
        if (str.match(/\,/) || str.match(/"/)) {
            str = str.replace(/"/g, '""');
            str = '"' + str + '"';
        }
        return str;
    }

    generateColumns() {
        if (!this.columnSet.idlClass) { return; }

        const pkeyField = this.idl.classes[this.columnSet.idlClass].pkey;

        // generate columns for all non-virtual fields on the IDL class
        this.idl.classes[this.columnSet.idlClass].fields
        .filter(field => !field.virtual)
        .forEach(field => {
            const col = new GridColumn();
            col.name = field.name;
            col.label = field.label || field.name;
            col.idlFieldDef = field;
            col.idlClass = this.columnSet.idlClass;
            col.datatype = field.datatype;
            col.isIndex = (field.name === pkeyField);
            col.isAuto = true;

            if (this.showLinkSelectors) {
                const selector = this.idl.getLinkSelector(
                    this.columnSet.idlClass, field.name);
                if (selector) {
                    col.path = field.name + '.' + selector;
                }
            }

            this.columnSet.add(col);
        });
    }

    saveGridConfig(): Promise<any> {
        if (!this.persistKey) {
            throw new Error('Grid persistKey required to save columns');
        }
        const conf = new GridPersistConf();
        conf.version = 2;
        conf.limit = this.pager.limit;
        conf.columns = this.columnSet.compileSaveObject();

        return this.store.setItem('eg.grid.' + this.persistKey, conf);
    }

    // TODO: saveGridConfigAsOrgSetting(...)

    getGridConfig(persistKey: string): Promise<GridPersistConf> {
        if (!persistKey) { return Promise.resolve(null); }
        return this.store.getItem('eg.grid.' + persistKey);
    }
}


// Actions apply to specific rows
export class GridToolbarAction {
    label: string;
    onClick: EventEmitter<any []>;
    action: (rows: any[]) => any; // DEPRECATED
    group: string;
    isGroup: boolean; // used for group placeholder entries
    disableOnRows: (rows: any[]) => boolean;
}

// Buttons are global actions
export class GridToolbarButton {
    label: string;
    onClick: EventEmitter<any []>;
    action: () => any; // DEPRECATED
    disabled: boolean;
}

export class GridToolbarCheckbox {
    label: string;
    isChecked: boolean;
    onChange: EventEmitter<boolean>;
}

export class GridDataSource {

    data: any[];
    sort: any[];
    allRowsRetrieved: boolean;
    getRows: (pager: Pager, sort: any[]) => Observable<any>;

    constructor() {
        this.sort = [];
        this.reset();
    }

    reset() {
        this.data = [];
        this.allRowsRetrieved = false;
    }

    // called from the template -- no data fetching
    getPageOfRows(pager: Pager): any[] {
        if (this.data) {
            return this.data.slice(
                pager.offset, pager.limit + pager.offset
            ).filter(row => row !== undefined);
        }
        return [];
    }

    // called on initial component load and user action (e.g. paging, sorting).
    requestPage(pager: Pager): Promise<any> {

        if (
            this.getPageOfRows(pager).length === pager.limit
            // already have all data
            || this.allRowsRetrieved
            // have no way to get more data.
            || !this.getRows
        ) {
            return Promise.resolve();
        }

        return new Promise((resolve, reject) => {
            let idx = pager.offset;
            return this.getRows(pager, this.sort).subscribe(
                row => this.data[idx++] = row,
                err => {
                    console.error(`grid getRows() error ${err}`);
                    reject(err);
                },
                ()  => {
                    this.checkAllRetrieved(pager, idx);
                    resolve();
                }
            );
        });
    }

    // See if the last getRows() call resulted in the final set of data.
    checkAllRetrieved(pager: Pager, idx: number) {
        if (this.allRowsRetrieved) { return; }

        if (idx === 0 || idx < (pager.limit + pager.offset)) {
            // last query returned nothing or less than one page.
            // confirm we have all of the preceding pages.
            if (!this.data.includes(undefined)) {
                this.allRowsRetrieved = true;
                pager.resultCount = this.data.length;
            }
        }
    }
}


