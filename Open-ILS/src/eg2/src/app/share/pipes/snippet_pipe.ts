import { Pipe, PipeTransform } from '@angular/core';

const DEFAULT_LENGTH = 20;

@Pipe({
    name: 'snippet',
    standalone: true
})
export class SnippetPipe implements PipeTransform {
    transform(value: string, maxCharacters = DEFAULT_LENGTH): string {
        const truncationPoint = value.lastIndexOf(' ', maxCharacters);
        if (truncationPoint < 1) {
            return value;
        }
        return value.slice(0, truncationPoint) + '…';
    }
}
