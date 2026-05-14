import { customAlphabet } from 'nanoid';

// Unambiguous alphabet — no 0/O/1/l/I — so links are easy to read and retype.
// 7 characters from a 31-char alphabet ≈ 27.5 billion combinations.
const nanoid = customAlphabet('23456789abcdefghijkmnpqrstuvwxyz', 7);

export function newShortId() {
  return nanoid();
}
