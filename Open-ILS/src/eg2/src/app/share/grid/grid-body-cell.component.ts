import {Component, Input} from '@angular/core';
import {GridContext, GridColumn} from './grid';

@Component({
    selector: 'eg-grid-body-cell',
    templateUrl: './grid-body-cell.component.html'
})

export class GridBodyCellComponent {

    @Input() context: GridContext;
    @Input() row: any;
    @Input() column: GridColumn;

    initDone: boolean;

    constructor() {}

    breakWords(val?: string): string {
        if (!val) {return;}

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

