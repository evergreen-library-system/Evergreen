import { Pipe, PipeTransform } from '@angular/core';

@Pipe({
    name: 'parentheses',
    standalone: true
})
export class ParenthesesPipe implements PipeTransform {
    transform(value: string): string {
        return value ? `(${value})` : '';
    }
}
