import {concat, of, toArray} from 'rxjs';
import { memoizeRetrieveByKeyFn } from './memoize';

describe('memoizeRetrieveByKeyFn', () => {
    it('avoids repeated calls to the function', () => {
        let calls = 0;
        const myFunction = (id: number) => {
            calls++;
            return of(`Hello ${id}`);
        };
        const myMemoizedFunction = memoizeRetrieveByKeyFn(myFunction);

        concat(
            myMemoizedFunction(1),
            myMemoizedFunction(2),
            myMemoizedFunction(3),
            myMemoizedFunction(1),
            myMemoizedFunction(1)
        ).pipe(toArray()
        ).subscribe((results) => {
            expect(results).toEqual([
                'Hello 1',
                'Hello 2',
                'Hello 3',
                'Hello 1',
                'Hello 1',
            ]);
            // Expect the original function to only have been called 3
            // times, since 1 is memoized
            expect(calls).toEqual(3);
        });

    });
});
