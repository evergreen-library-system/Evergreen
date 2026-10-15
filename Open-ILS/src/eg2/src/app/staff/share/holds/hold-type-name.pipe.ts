import { Pipe, PipeTransform } from '@angular/core';

@Pipe({
    name: 'holdTypeName',
    standalone: true
})
export class HoldTypeNamePipe implements PipeTransform {
    transform(value: string): string {
        switch(value) {
            case 'M': return $localize`Metarecord`;
            case 'T': return $localize`Title`;
            case 'V': return $localize`Call Number`;
            case 'F': return $localize`Force Item`;
            case 'C': return $localize`Item`;
            case 'R': return $localize`Recall`;
            case 'I': return $localize`Issuance`;
            case 'P': return $localize`Parts`;
            default: return value;
        }
    }
}
