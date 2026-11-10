import { upcaseFirst } from './letter-case';

describe('upcaseFirst', () => {
    it('works', () => {
        expect(upcaseFirst('dog')).toEqual('Dog');
        expect(upcaseFirst('Dog')).toEqual('Dog');
        expect(upcaseFirst('')).toEqual('');
        expect(upcaseFirst('DOG')).toEqual('DOG');
        expect(upcaseFirst('my favorite Dog')).toEqual('My favorite Dog');
    });
});
