import {normalizeDigits} from './money';

export function normalizeEgyptianPhone(value:string):string {
  const digits=normalizeDigits(value).replace(/[^0-9+]/g,'');
  if(/^01[0125]\d{8}$/.test(digits)) return `+2${digits}`;
  if(/^201[0125]\d{8}$/.test(digits)) return `+${digits}`;
  if(/^\+201[0125]\d{8}$/.test(digits)) return digits;
  throw new Error('INVALID_PHONE');
}

// Supabase password auth uses a private, non-deliverable identifier so this
// closed system never sends email or SMS during login.
export function phoneLoginEmail(value:string):string {
  return `${normalizeEgyptianPhone(value).slice(1)}@binaa.invalid`;
}
