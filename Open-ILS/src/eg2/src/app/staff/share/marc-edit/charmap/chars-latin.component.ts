import {Component, ViewEncapsulation} from '@angular/core';
import { CharMapDialogComponent } from './charmap-dialog.component';

/**
 * Special Character Set: Latin Extended
 */

@Component({
    selector: 'eg-chars-latin',
    templateUrl: './chars-latin.component.html',
    styleUrls: ['charmap-dialog.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class CharsLatinComponent {
    constructor( private charmap: CharMapDialogComponent ) { }

    copyChar(char: string): void {
        this.charmap.copyChar(char);
    }
}
