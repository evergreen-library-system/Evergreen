import {Component, Input, OnInit} from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {GridColumn, GridColumnSet, GridContext} from './grid';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

@Component({
  selector: 'eg-grid-column-config',
  templateUrl: './grid-column-config.component.html'
})

/**
 */
export class GridColumnConfigComponent extends DialogComponent implements OnInit {
    @Input() gridContext: GridContext;
    columnSet: GridColumnSet;
    changesPending = false;

    open(ops: NgbModalOptions): Observable<any> {
        this.changesPending = false;
        this.columnSet = this.gridContext.columnSet;
        return super.open(ops);
    }

    toggleVisibility(col: GridColumn) {
        col.visible = !col.visible;
        this.changesPending = true;
    }

    // Avoid reloading on each column change and instead reload the
    // data if needed after all changes are complete.
    // Override close() so we can reload data if needed.
    // NOTE: ng-bootstrap v 8.0.0 has a 'closed' emitter, but
    // we're not there yet.
    close(value?: any) {
        if (this.modalRef) { this.modalRef.close(); }
        this.finalize();

        if (this.changesPending && this.gridContext.reloadOnColumnChange) {
            this.gridContext.reloadWithoutPagerReset();
        }
    }
}


