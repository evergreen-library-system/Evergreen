import {Component, ViewEncapsulation} from '@angular/core';
import { CharMapDialogComponent } from './charmap-dialog.component';

/**
 * Special Character Set: Canadian Syllabics
 */

@Component({
    selector: 'eg-chars-canadian',
    templateUrl: './chars-canadian.component.html',
    styleUrls: ['charmap-dialog.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class CharsCanadianComponent {
    constructor( private charmap: CharMapDialogComponent ) { }

    copyChar(char: string): void {
        this.charmap.copyChar(char);
    }
}
