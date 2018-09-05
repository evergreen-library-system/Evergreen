import {Component, Input, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {GridColumnSet} from './grid';

@Component({
  selector: 'eg-grid-column-config',
  templateUrl: './grid-column-config.component.html'
})

/**
 */
export class GridColumnConfigComponent extends DialogComponent implements OnInit {
    @Input() columnSet: GridColumnSet;
}


