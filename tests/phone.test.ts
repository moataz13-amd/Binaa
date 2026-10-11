import {describe,it,expect} from 'vitest';
import {normalizeEgyptianPhone} from '../src/lib/phone';

describe('Egyptian phone login',()=>{
  it('normalizes a local mobile number',()=>expect(normalizeEgyptianPhone('01012345678')).toBe('+201012345678'));
  it('accepts Arabic digits',()=>expect(normalizeEgyptianPhone('٠١١١٢٣٤٥٦٧٨')).toBe('+201112345678'));
  it('accepts country code formats',()=>expect(normalizeEgyptianPhone('201212345678')).toBe('+201212345678'));
  it('rejects landlines and malformed numbers',()=>expect(()=>normalizeEgyptianPhone('0212345678')).toThrow('INVALID_PHONE'));
});
