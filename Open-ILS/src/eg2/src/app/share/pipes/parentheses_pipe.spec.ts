import { ParenthesesPipe } from './parentheses_pipe';

describe('ParenthesesPipe', () => {
    it('wraps the string in parentheses', () => {
        expect(new ParenthesesPipe().transform('walrus')).toEqual('(walrus)');
    });
    it('displays an empty string if null is provided', () => {
        expect(new ParenthesesPipe().transform(null)).toEqual('');
    });
});
