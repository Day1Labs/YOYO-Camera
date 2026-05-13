const SHARE_CODE_LENGTH = 6;
const SHARE_CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const SHARE_CODE_DIGITS = "0123456789";

function randomInt(maxExclusive: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % maxExclusive;
}

function randomChar(chars: string): string {
  return chars[randomInt(chars.length)]!;
}

export function generateShareCode(attempt: number): string {
  const letterCount = Math.max(0, Math.min(SHARE_CODE_LENGTH, attempt));
  const digitCount = SHARE_CODE_LENGTH - letterCount;

  let code = "";
  for (let i = 0; i < letterCount; i++) code += randomChar(SHARE_CODE_LETTERS);
  for (let i = 0; i < digitCount; i++) code += randomChar(SHARE_CODE_DIGITS);
  return code;
}
