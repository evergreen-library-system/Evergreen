/* eslint-disable no-magic-numbers, @angular-eslint/component-selector */
import {Component, Input, OnInit, AfterViewInit, QueryList, ViewChildren, inject, NgZone, OnDestroy, Renderer2} from '@angular/core';
import {DOCUMENT} from '@angular/common';
import {GridContext, GridColumn} from './grid';
import {GridFilterControlComponent} from './grid-filter-control.component';
import {takeUntil, switchMap, map, tap, Subject, fromEvent} from 'rxjs';

@Component({
    selector: 'thead.eg-grid-header',
    templateUrl: './grid-header.component.html'
})

export class GridHeaderComponent implements OnInit, OnDestroy, AfterViewInit {

    @Input() context: GridContext;

    dragColumn: GridColumn;
    resizeStart: any;
    charWidth = 8; // 1ch == .5rem and browser default font size is 16; see setCharWidth()
    tempWidth: any;

    batchRowCheckbox: boolean;
    private readonly destroy$$ = new Subject<void>();
    private readonly ngZone = inject(NgZone);
    private readonly document = inject(DOCUMENT);

    @ViewChildren(GridFilterControlComponent) filterControls: QueryList<GridFilterControlComponent>;
    @ViewChildren('colResizeButton') colResizeControls: QueryList<any>;

    constructor( private renderer: Renderer2 ) {
    }

    ngOnInit() {
        this.context.selectRowsInPageEmitter.subscribe(
            () => this.batchRowCheckbox = true
        );

    }

    ngOnDestroy() {
        // when the components gets destroyed, next the destroy$$
        // subject so the subscriptions get cleaned up
        this.destroy$$.next();
    }

    ngAfterViewInit() {
        this.context.filterControls = this.filterControls;

        this.setCharWidth();

        // fromEvent will cause addEventListener that would normally trigger tick()
        // based on https://blog.simplified.courses/angular-performant-drag-and-drop-with-rxjs/
        this.ngZone.runOutsideAngular(() => {

            const mouseDown$ = fromEvent(this.document.querySelectorAll('.col-resize'), 'mousedown').pipe(
                takeUntil(this.destroy$$) // clear subscription
            );
            const mouseMove$ = fromEvent(this.document, 'mousemove').pipe(
                takeUntil(this.destroy$$) // clear subscription
            );
            const mouseUp$ = fromEvent(this.document, 'mouseup').pipe(
                takeUntil(this.destroy$$) // clear subscription
            );

            const dragMove$ = mouseDown$.pipe(
                switchMap((startEvent: MouseEvent) =>
                    mouseMove$.pipe(
                        map((moveEvent: MouseEvent) => {
                        // return both events
                            return {
                                startEvent,
                                moveEvent,
                            };
                        }),
                        takeUntil(mouseUp$)
                    )
                ),
                tap(({ startEvent, moveEvent }) => {
                    const x = moveEvent.clientX - startEvent.clientX;
                    // console.debug('Delta: ', x);
                    if (this.context.currentResizeTarget) {
                        this.context.currentResizeTarget.closest('th').style.width = this.tempWidth + x + 'px';
                    }
                }),
                takeUntil(this.destroy$$) // clear subscription
            );
            dragMove$.subscribe();

            mouseUp$.subscribe(() => {
                if (this.context.currentResizeTarget) {
                    this.context.currentResizeTarget.classList.remove('resizing');
                }

                if (this.context.currentResizeTarget && this.context.currentResizeCol) {
                    const width = this.context.currentResizeTarget.closest('th').style.width;
                    // if set in px due to user drag, convert to ch
                    if (width && width.includes('px')) {
                        this.context.currentResizeCol.size = Math.ceil(Number(width.replace('px', '')) / this.charWidth);
                        // immediately reset the size in px to avoid visual bobble
                        this.context.currentResizeTarget.closest('th').style.width = width;
                        // console.debug("Saving width as ", width);
                    }

                    this.context.currentResizeTarget = null;
                    this.resizeStart = null;
                    this.context.currentResizeCol = null;
                }
            });
            mouseDown$.subscribe(($event) => {
                const btn = $event.target as HTMLElement;
                this.context.currentResizeTarget = btn;
                btn.classList.add('resizing');

                // mouseMove$ is going to report clientX,
                // which is viewport based rather than offset based,
                // so original right border = getBoundingClientRect().left + width
                this.resizeStart = btn.getBoundingClientRect().left + btn.offsetWidth;
                this.tempWidth = btn.closest('th').offsetWidth;
            });
        });
    }

    /**
     * Find the width of the ch unit in CSS with the user's font settings.
     * ch is defined as the width of a zero.
     */

    setCharWidth() {
        const zeroSize = this.renderer.createElement('span');
        const text = this.renderer.createText('0');
        this.renderer.appendChild(zeroSize, text);
        this.renderer.appendChild(document.body, zeroSize);
        this.charWidth = zeroSize.offsetWidth;
        this.renderer.removeChild(document.body, zeroSize);
    }

    /**
     * Width style is set once initially in ch units, then may be updated in
     * pixels via user dragging. We do not want to bind this value. Size needs
     * to be saved in ch for readability in the column manager, but mouse drag
     * is measured in pixels. We will convert, round to the nearest whole
     * character, and save on mouseup, but we do not want to update the style
     * when we do.
     */
    colWidthInit(col: GridColumn) {
        return col.size ? 'width: ' + col.size + 'ch' : null;
    }

    columnResizeInit($event: any, col: GridColumn) {
        this.context.currentResizeTarget = $event.target;
        this.context.currentResizeCol = col;
        this.context.currentResizeCol.resizeStart = $event.clientX;
    }

    blurHandler($event: any) {
        // blur fires on any loss of focus; we want only keyboard
        if ($event.key && this.context.currentResizeTarget) {
            if (!this.context.currentResizeCol || !this.context.currentResizeTarget) {return;}

            // remove pseudo-focus class
            this.context.currentResizeTarget.classList.remove('resizing');

            // save new width in grid config
            const newWidth = this.context.currentResizeTarget.closest('th').offsetWidth;
            // console.debug("New width: ", newWidth);

            // Recalculate button height in case cells reflowed
            // this.setColumnHandleHeight($event.target);

            // clear resize vars
            this.context.currentResizeCol.resizeStart = this.context.currentResizeTarget.clientX;
            this.context.currentResizeTarget = null;
            this.tempWidth = null;
        }
    }

    columnStepMove($event: any, col: GridColumn) {
        if (!$event.key) {return;}

        this.context.currentResizeTarget = $event.target;
        const th = $event.target.closest('th');

        if ($event.key === 'ArrowLeft') {
            if (!col.size) {
                col.size = Math.round(th.offsetWidth / this.charWidth);
            }
            col.size--;
            $event.preventDefault();
            $event.stopPropagation();
        }
        if ($event.key === 'ArrowRight') {
            if (!col.size) {
                col.size = Math.round(th.offsetWidth / this.charWidth);
            }
            col.size++;
            $event.preventDefault();
            $event.stopPropagation();
        }

        /* Recalculate button height in case cells reflowed */
        // this.setColumnHandleHeight($event.target);
    }

    /*  When the user has changed a column size, we need to resize all the
        buttons; otherwise the inactive ones will retain their original
        heights even if the table has reflowed
    /**/
    setColumnHandleHeight(target: any) {
        const table = target.closest('table');
        table.querySelectorAll('th button.col-resize').forEach((resizer) => {
            resizer.style.height = table.offsetHeight + 'px';
        });
    }

    onColumnDragEnter($event: any, col: any) {
        if (this.dragColumn && this.dragColumn.name !== col.name) {
            col.isDragTarget = true;
        }
        $event.preventDefault();
    }

    onColumnDragLeave($event: any, col: any) {
        col.isDragTarget = false;
        $event.preventDefault();
    }

    onColumnDrop(col: GridColumn) {
        this.context.columnSet.insertBefore(this.dragColumn, col);
        this.context.columnSet.columns.forEach(c => c.isDragTarget = false);
    }

    sortOneColumn(col: GridColumn) {
        let dir = 'ASC';
        const sort = this.context.dataSource.sort;

        if (sort.length && sort[0].name === col.name && sort[0].dir === 'ASC') {
            dir = 'DESC';
        }

        this.context.dataSource.sort = [{name: col.name, dir: dir}];

        if (this.context.useLocalSort) {
            this.context.sortLocal();
        } else {
            this.context.reload();
        }
    }

    // Returns sorting direction in ARIA's required format
    ariaSortDirection(col: GridColumn): string {
        const sort = this.context.dataSource.sort.filter(c => c.name === col.name)[0];

        if (sort && sort.dir === 'ASC') {return 'ascending';}
        if (sort && sort.dir === 'DESC') {return 'descending';}

        return null;
    }

    handleBatchSelect($event) {
        if ($event.target.checked) {
            if (this.context.rowSelector.isEmpty() || !this.allRowsAreSelected()) {
                // clear selections from other pages to avoid confusion.
                this.context.rowSelector.clear();
                this.selectAll();
            }
        } else {
            this.context.rowSelector.clear();
        }
    }

    selectAll() {
        this.context.selectRowsInPage();
    }

    allRowsAreSelected(): boolean {
        const rows = this.context.dataSource.getPageOfRows(this.context.pager);
        const indexes = rows.map(r => this.context.getRowIndex(r));
        return this.context.rowSelector.contains(indexes);
    }
}

