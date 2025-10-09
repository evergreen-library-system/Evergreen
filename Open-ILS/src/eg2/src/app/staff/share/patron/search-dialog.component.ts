import {Component, ViewChild, Input} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {PatronSearchComponent} from './search.component';

/**
 * Dialog container for patron search component
 *
 * <eg-patron-search-dialog (patronsSelected)="process($event)">
 * </eg-patron-search-dialog>
 */

@Component({
    selector: 'eg-patron-search-dialog',
    templateUrl: 'search-dialog.component.html'
})

export class PatronSearchDialogComponent
    extends DialogComponent {

    @Input() dialogTitle: string;

    // If set, load a batch of patrons by ID.
    @Input() patronIds?: number[];

    // Pass-through autofocus option for the embedded patron search.
    // Allowed values align with DOM ids that are visible on load.
    @Input() autofocusField: 'card' | 'family_name' | 'first_given_name' | 'profile_group' | 'home_ou' = 'family_name';

    @ViewChild('searchForm', {static: false})
        searchForm: PatronSearchComponent;

    constructor(private modal: NgbModal) { super(modal); }

    // Fired when a row in the search grid is dbl-clicked / activated
    patronsSelected(patrons: IdlObject[]) {
        this.close(patrons);
    }
}



