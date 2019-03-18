import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy, HostListener, ViewEncapsulation} from '@angular/core';
import {Subscription} from 'rxjs';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {FormatService} from '@eg/core/format.service';
import {GridContext, GridColumn, GridDataSource, GridRowFlairEntry} from './grid';

/**
 * Main grid entry point.
 */

@Component({
  selector: 'eg-grid',
  templateUrl: './grid.component.html',
  styleUrls: ['grid.component.css'],
  // share grid css globally once imported so all grid component CSS
  // can live in grid.component.css and to avoid multiple copies of
  // the CSS when multiple grids are displayed.
  encapsulation: ViewEncapsulation.None
})

export class GridComponent implements OnInit, AfterViewInit, OnDestroy {

    // Source of row data.
    @Input() dataSource: GridDataSource;

    // IDL class for auto-generation of columns
    @Input() idlClass: string;

    // True if any columns are sortable
    @Input() sortable: boolean;

    // True if the grid supports sorting of multiple columns at once
    @Input() multiSortable: boolean;

    // If true, grid sort requests only operate on data that
    // already exists in the grid data source -- no row fetching.
    // The assumption is all data is already available.
    @Input() useLocalSort: boolean;

    // Storage persist key / per-grid-type unique identifier
    // The value is prefixed with 'eg.grid.'
    @Input() persistKey: string;

    @Input() disableSelect: boolean;

    // Prevent selection of multiple rows
    @Input() disableMultiSelect: boolean;

    // Show an extra column in the grid where the caller can apply
    // row-specific flair (material icons).
    @Input() rowFlairIsEnabled: boolean;

    // Returns a material icon name to display in the flar column
    // (if enabled) for the given row.
    @Input() rowFlairCallback: (row: any) => GridRowFlairEntry;

    // Returns a space-separated list of CSS class names to apply to
    // a given row
    @Input() rowClassCallback: (row: any) => string;

    // Returns a space-separated list of CSS class names to apply to
    // a given cell or all cells in a column.
    @Input() cellClassCallback: (row: any, col: GridColumn) => string;

    // comma-separated list of fields to show by default.
    // This field takes precedence over hideFields.
    // When a value is applied, any field not in this list will
    // be hidden.
    @Input() showFields: string;

    // comma-separated list of fields to hide.
    // This does not imply all other fields should be visible, only that
    // the selected fields will be hidden.
    @Input() hideFields: string;

    // Allow the caller to jump directly to a specific page of
    // grid data.
    @Input() pageOffset: number;
    // Pass in a default page size.  May be overridden by settings.
    @Input() pageSize: number;

    // If true and an idlClass is specificed, the grid assumes
    // datatype=link fields that link to classes which define a selector
    // are fleshed with the linked object.  And, instead of displaying
    // the raw field value, displays the selector value from the linked
    // object.  The caller is responsible for fleshing the appropriate
    // fields in the GridDataSource getRows handler.
    //
    // This only applies to auto-generated columns.
    //
    // For example, idlClass="aou" and field="ou_type", the display
    // value will be ou_type().name() since "name" is the selector
    // field on the "aout" class.
    @Input() showLinkSelectors: boolean;

    @Input() disablePaging: boolean;

    context: GridContext;

    // These events are emitted from our grid-body component.
    // They are defined here for ease of access to the caller.
    @Output() onRowActivate: EventEmitter<any>;
    @Output() onRowClick: EventEmitter<any>;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private store: ServerStoreService,
        private format: FormatService
    ) {
        this.context =
            new GridContext(this.idl, this.org, this.store, this.format);
        this.onRowActivate = new EventEmitter<any>();
        this.onRowClick = new EventEmitter<any>();
    }

    ngOnInit() {

        if (!this.dataSource) {
            throw new Error('<eg-grid/> requires a [dataSource]');
        }

        this.context.idlClass = this.idlClass;
        this.context.dataSource = this.dataSource;
        this.context.persistKey = this.persistKey;
        this.context.isSortable = this.sortable === true;
        this.context.isMultiSortable = this.multiSortable === true;
        this.context.useLocalSort = this.useLocalSort === true;
        this.context.disableSelect = this.disableSelect === true;
        this.context.showLinkSelectors = this.showLinkSelectors === true;
        this.context.disableMultiSelect = this.disableMultiSelect === true;
        this.context.rowFlairIsEnabled = this.rowFlairIsEnabled  === true;
        this.context.rowFlairCallback = this.rowFlairCallback;
        this.context.disablePaging = this.disablePaging === true;
        if (this.showFields) {
            this.context.defaultVisibleFields = this.showFields.split(',');
        }
        if (this.hideFields) {
            this.context.defaultHiddenFields = this.hideFields.split(',');
        }

        if (this.pageOffset) {
            this.context.pager.offset = this.pageOffset;
        }

        if (this.pageSize) {
            this.context.pager.limit = this.pageSize;
        }

        // TS doesn't seem to like: let foo = bar || () => '';
        this.context.rowClassCallback =
            this.rowClassCallback || function () { return ''; };
        this.context.cellClassCallback =
            this.cellClassCallback || function() { return ''; };

        this.context.init();
    }

    ngAfterViewInit() {
        this.context.initData();
    }

    ngOnDestroy() {
        this.context.destroy();
    }

    reload() {
        this.context.reload();
    }
}



