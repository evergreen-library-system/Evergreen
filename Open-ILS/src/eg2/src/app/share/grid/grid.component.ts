import {Component, Input, Output, OnInit, AfterViewInit, EventEmitter,
    OnDestroy, ViewChild, ViewEncapsulation} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {FormatService} from '@eg/core/format.service';
import {GridContext, GridColumn, GridDataSource,
    GridCellTextGenerator, GridRowFlairEntry} from './grid';
import {GridToolbarComponent} from './grid-toolbar.component';

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
    //
    // If persistKey is set to "disabled", or does not exist,
    // the grid will not display a Save button to the user
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

    // When true, only display columns that are declared in the markup
    // and leave all auto-generated fields hidden.
    @Input() showDeclaredFieldsOnly: boolean;

    // Allow the caller to jump directly to a specific page of
    // grid data.
    @Input() pageOffset: number;
    // Pass in a default page size.  May be overridden by settings.
    @Input() pageSize: number;

    @Input() showLinkSelectors: boolean;

    @Input() disablePaging: boolean;

    // result filtering
    //
    // filterable: true if the result filtering controls
    // should be displayed
    @Input() filterable: boolean;

    // sticky grid header
    //
    // stickyHeader: true of the grid header should be
    // "sticky", i.e., remain visible if if the table is long
    // and the user has scrolled far enough that the header
    // would go out of view
    @Input() stickyHeader: boolean;

    @Input() cellTextGenerator: GridCellTextGenerator;

    context: GridContext;

    // These events are emitted from our grid-body component.
    // They are defined here for ease of access to the caller.
    @Output() onRowActivate: EventEmitter<any>;
    @Output() onRowClick: EventEmitter<any>;

    @ViewChild('toolbar', { static: true }) toolbar: GridToolbarComponent;

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
        this.context.isFilterable = this.filterable === true;
        this.context.stickyGridHeader = this.stickyHeader === true;
        this.context.isMultiSortable = this.multiSortable === true;
        this.context.useLocalSort = this.useLocalSort === true;
        this.context.disableSelect = this.disableSelect === true;
        this.context.disableMultiSelect = this.disableMultiSelect === true;
        this.context.rowFlairIsEnabled = this.rowFlairIsEnabled  === true;
        this.context.showDeclaredFieldsOnly = this.showDeclaredFieldsOnly;
        this.context.rowFlairCallback = this.rowFlairCallback;
        this.context.disablePaging = this.disablePaging === true;
        this.context.cellTextGenerator = this.cellTextGenerator;

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

        if (this.showLinkSelectors) {
            console.debug(
                'showLinkSelectors is deprecated and no longer has any effect');
        }

        this.context.init();
    }

    ngAfterViewInit() {
        this.context.initData();
    }

    ngOnDestroy() {
        this.context.destroy();
    }

    print = () => {
        this.toolbar.printHtml();
    }

    reload() {
        this.context.reload();
    }
    reloadWithoutPagerReset() {
        this.context.reloadWithoutPagerReset();
    }


}



