import { Pipe, PipeTransform } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';

@Pipe({
    name: 'volEditPartDedupe'
})
export class VolEditPartDedupePipe implements PipeTransform {
    // In: key-value pair, where the value is an array of monographic parts. -- VolCopyService.bibParts.
    // Out: An array of monographic parts, where none have the same label.
    transform(bibParts: {[bibId: number]: IdlObject[]} ) : IdlObject[] {
        if (!bibParts) {
            return [];
        }
        const uniqueParts = [];
        const seenLabels = [];

        Object.values(bibParts).forEach(bib => {
            bib.forEach(part => {
                if (!seenLabels.find(label => label === part.label())){
                    seenLabels.push(part.label());
                    uniqueParts.push(part);
                }
            });
        });
        return uniqueParts;
    }
}
