#!/usr/bin/env python3
"""
XXTEA for the mu77 game.

Scheme (verified empirically against the APK):
  * Lua scripts:   "gclR3cu9" magic + XXTEA body
  * CSV files:     bare XXTEA body (no magic)
  * Both: the plaintext is padded with zero bytes to a multiple of 4, then a
    4-byte little-endian length word is appended; the whole thing is XXTEA
    encrypted. Decryption reads the last word as the true plaintext length
    and truncates.
"""
import os
import struct
import sys

MAGIC = b'gclR3cu9'
KEY = b'10cc4fdee2fcd047'

DELTA = 0x9E3779B9
MASK = 0xFFFFFFFF


def to_uint32_list(data):
    n = (len(data) + 3) // 4
    return [struct.unpack('<I', data[i * 4:(i + 1) * 4].ljust(4, b'\x00'))[0] for i in range(n)]


def from_uint32_list(v):
    return b''.join(struct.pack('<I', x & MASK) for x in v)


def xxtea_decrypt(v, key):
    if not v:
        return v
    n = len(v)
    k = to_uint32_list(key)[:4]
    while len(k) < 4:
        k.append(0)
    z = v[n - 1]
    y = v[0]
    q = 6 + 52 // n
    s = (q * DELTA) & MASK
    while s != 0:
        e = (s >> 2) & 3
        p = n - 1
        while p > 0:
            z = v[p - 1]
            v[p] = (v[p] - ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((s ^ y) + (k[(p & 3) ^ e] ^ z)))) & MASK
            y = v[p]
            p -= 1
        z = v[n - 1]
        v[0] = (v[0] - ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((s ^ y) + (k[0 ^ e] ^ z)))) & MASK
        y = v[0]
        s = (s - DELTA) & MASK
    return v


def xxtea_encrypt(v, key):
    # Mirrors the game's xxtea-c variant: the LAST word is the plaintext
    # length. The encrypt loop runs p = 0..n-1 (so the length word feeds the
    # final data word) and then updates the length word itself.
    # Note: MX must use ((y >> 3) ^ (z << 4)) exactly like the decrypt side.
    if not v:
        return v
    n = len(v) - 1
    k = to_uint32_list(key)[:4]
    while len(k) < 4:
        k.append(0)
    z = v[n]
    s = 0
    q = 6 + 52 // len(v)
    while q > 0:
        s = (s + DELTA) & MASK
        e = (s >> 2) & 3
        p = 0
        while p < n:
            y = v[p + 1]
            z = v[p] = (v[p] + ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((s ^ y) + (k[(p & 3) ^ e] ^ z)))) & MASK
            p += 1
        y = v[0]
        z = v[n] = (v[n] + ((((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((s ^ y) + (k[(n & 3) ^ e] ^ z)))) & MASK
        q -= 1
    return v


def decrypt_body(body, key=KEY):
    """Decrypt an XXTEA body (no magic), trimming the trailing length word."""
    if not body:
        return b''
    v = to_uint32_list(body)
    dec = xxtea_decrypt(list(v), key)
    length = dec[-1] & MASK
    out = from_uint32_list(dec)
    if 0 < length <= len(out):
        return out[:length]
    return out


def encrypt_body(plain, key=KEY):
    """Encrypt plaintext with the length-word scheme (no magic)."""
    padded = plain + b'\x00' * ((4 - len(plain) % 4) % 4)
    data = padded + struct.pack('<I', len(plain) & MASK)
    v = to_uint32_list(data)
    return from_uint32_list(xxtea_encrypt(v, key))


def decrypt_file(data):
    """Decrypt a Lua file: magic + body."""
    assert data[:8] == MAGIC, 'bad magic: %r' % data[:8]
    return decrypt_body(data[8:])


def encrypt_file(plain, with_magic=True):
    body = encrypt_body(plain)
    return (MAGIC + body) if with_magic else body


if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else None
    data = open(src, 'rb').read()
    if data[:8] == MAGIC:
        out = decrypt_file(data)
    else:
        out = decrypt_body(data)
    if dst:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, 'wb').write(out)
        print('wrote', dst, len(out), 'bytes')
    else:
        sys.stdout.buffer.write(out)
