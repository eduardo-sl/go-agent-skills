# Cryptography and Randomness

Choosing primitives with the standard library. The SKILL.md "Cryptography
and Randomness" section states the rules; this file has the code.

## Contents

- Randomness
- Comparing secrets
- Passwords
- Encrypting data
- Hashes, MACs and key derivation
- Signatures and key exchange
- FIPS 140-3 mode

## Randomness

```go
// ✅ Tokens, session IDs, reset links, API keys
token := rand.Text() // crypto/rand, Go 1.24+: 26 base32 chars, 128+ bits

// ✅ Raw key material
key := make([]byte, 32)
rand.Read(key) // crypto/rand: Go 1.24+ never returns an error

// ❌ Predictable: math/rand and math/rand/v2 are for simulations and jitter
id := fmt.Sprint(mathrand.Int64())
```

Anything that grants access or must not be guessed comes from
`crypto/rand`, including nonces, salts and invitation codes.

## Comparing secrets

```go
// ✅ Constant time: no early exit on the first differing byte
if subtle.ConstantTimeCompare([]byte(got), []byte(want)) != 1 {
    return errUnauthorized
}

// ✅ MAC tags
if !hmac.Equal(gotMAC, wantMAC) { ... }

// ❌ Timing leak
if got == want { ... }
```

## Passwords

```go
// ✅ Argon2id — OWASP minimum: 19 MiB memory, 2 iterations, 1 thread
salt := make([]byte, 16)
rand.Read(salt)
hash := argon2.IDKey([]byte(password), salt, 2, 19*1024, 1, 32)
// store salt + parameters + hash; compare with subtle.ConstantTimeCompare

// ✅ bcrypt — simpler; rejects passwords over 72 bytes
hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
err = bcrypt.CompareHashAndPassword(hash, []byte(password))
```

Never a plain or salted SHA-256/MD5: fast hashes are the wrong property
for passwords.

## Encrypting data

```go
block, err := aes.NewCipher(key) // 32-byte key: AES-256
if err != nil {
    return nil, err
}
// Go 1.24+: generates a random nonce per Seal and prepends it,
// removing the classic nonce-reuse mistake.
aead, err := cipher.NewGCMWithRandomNonce(block)
if err != nil {
    return nil, err
}
ciphertext := aead.Seal(nil, nil, plaintext, associatedData)
plaintext, err = aead.Open(nil, nil, ciphertext, associatedData)
```

- Reusing a nonce with the same GCM key leaks the authentication key and
  XOR of plaintexts — with plain `cipher.NewGCM`, every `Seal` needs a
  fresh 12-byte random nonce.
- No ECB, no unauthenticated CBC/CFB/OFB (CFB and OFB are deprecated).
- For public-key encryption, use `crypto/hpke` (Go 1.26+) or RSA-OAEP;
  RSA PKCS #1 v1.5 encryption is deprecated.

## Hashes, MACs and key derivation

| Need | Use |
|---|---|
| Integrity, content addressing | SHA-256 / SHA-512, `crypto/sha3` (1.24+) |
| Authenticate a message with a shared key | HMAC-SHA256 (`crypto/hmac`) |
| Derive several keys from one secret | `crypto/hkdf` (1.24+) |
| Legacy password interop only | `crypto/pbkdf2` (1.24+) |
| Never for security | MD5, SHA-1 |

## Signatures and key exchange

- Signatures: Ed25519 by default; ECDSA P-256 when interop requires it;
  RSA-PSS with 2048+ bit keys when RSA is mandated. ML-DSA (`crypto/mldsa`,
  Go 1.27) for post-quantum signatures.
- Key exchange: X25519 (`crypto/ecdh`); ML-KEM (`crypto/mlkem`, Go 1.24)
  for post-quantum.
- TLS already negotiates hybrid post-quantum key exchange by default
  (X25519MLKEM768 since Go 1.24) — do not pin `CurvePreferences` without
  a reason.

## FIPS 140-3 mode

Go 1.24+ ships a native Go Cryptographic Module:

```bash
GOFIPS140=v1.0.0 go build ./cmd/api   # link a specific module version, FIPS mode on by default
GODEBUG=fips140=on ./api              # enable at run time without rebuilding
```

`GODEBUG=fips140=only` makes non-approved algorithms fail; it is meant
for testing and assessment, not production.
