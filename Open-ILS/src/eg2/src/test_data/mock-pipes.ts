/**
 * Mock Pipes in case you don't want to include the original in your test
 */

import { Pipe, PipeTransform } from '@angular/core';
import { IdlObject } from '@eg/core/idl.service';

@Pipe({
    name: 'egDueDate'
})
export class MockDueDatePipe implements PipeTransform {
    transform(circ: IdlObject): string {
        return 'DATE';
    }
}

