import { Component, ViewEncapsulation, inject } from '@angular/core';
import { CharMapDialogComponent } from './charmap-dialog.component';

/**
 * Special Character Set: Punctuation
 */

@Component({
    selector: 'eg-chars-punctuation',
    templateUrl: './chars-punctuation.component.html',
    styleUrls: ['charmap-dialog.component.css'],
    encapsulation: ViewEncapsulation.None
})

export class CharsPunctuationComponent {
    private charmap = inject(CharMapDialogComponent);


    copyChar(char: string): void {
        this.charmap.copyChar(char);
    }
}
