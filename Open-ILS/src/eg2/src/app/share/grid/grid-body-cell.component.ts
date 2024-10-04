import {Component, Input} from '@angular/core';
import {GridContext, GridColumn} from './grid';

@Component({
    selector: 'eg-grid-body-cell',
    templateUrl: './grid-body-cell.component.html',
    // eslint-disable-next-line max-len
    styles: ['.eg-grid-body-row.selected .user-favorite { text-shadow: 0 0 1em var(--bs-primary), 0 0 0.2em var(--bs-primary); -webkit-text-stroke: 1px var(--star-stroke); }']
})

export class GridBodyCellComponent {

    @Input() context: GridContext;
    @Input() row: any;
    @Input() column: GridColumn;

    initDone: boolean;

    constructor() {}

    breakWords(val?: string): string {
        if (!val || typeof val !== 'string') {return val;}

        const doubleSlash = val.split('//');
        return doubleSlash.map(str =>
        /**
         *  Insert a word break opportunity after a colon, period, single slash,
         *  tilde, comma, hyphen, underscore, question mark, or percent symbol
        */
            str.replace(/(?<after>[:./@,\-_?%])/giu, '$1<wbr>')
            // Before and after an equals sign, number sign, or ampersand
                .replace(/(?<beforeAndAfter>[=#&])/giu, '<wbr>$1<wbr>')
        // Reconnect the strings with word break opportunities after double slashes
        ).join('//<wbr>');
    }
}

