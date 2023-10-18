# debian-openssl-fipsmodule

Builds FIPS 140 validated provider module for Debian containers running OpenSSL
3+ and demonstrates how the module can be integrated onto various Debian-based
images.

## Build

Build the image:
```
docker build -t debian-openssl-fipsmodule:3.0.8 .
```

I have not published this image to any public registries. Even if I did, you
should build it yourself since there are no guarantees I did not tamper with
the cryptographic provider in the image I published.

This approach is demonstrated using Docker, but could be used on a regular
virtual machines as well (i.e. build the FIPS provider module, copy it to the
correct location on a target VM, run `openssl fipsinstall`).

## Usage

You _could_ build images based off of the image in this repository. This is not
recommended.  Alternatively (and recommended), you can configure many
Debian-based images to use the binaries in this image instead. The basic idea
is to copy in the FIPS validated cryptographic module, run its self-tests, and
set the OpenSSL configuration so that the module can be used. In each of the
examples, I assume that FIPS should be enabled by default; see OpenSSL's
[manpage](https://www.openssl.org/docs/man3.0/man7/fips_module.html) for
alternative configurations. In each example, note that the self-tests are
re-run rather than copying `fipsmodule.cnf` (see OpenSSL's [FIPS
README](https://github.com/openssl/openssl/blob/master/README-FIPS.md)
for details.

Verification that a process is running in a FIPS-compliant mode typically
follows several steps:

1. Directly interrogate the process (if possible)
2. Confirm that a FIPS-compliant algorithm (typically SHA256) is available
   through the cryptographic module
3. Confirm that a non-FIPS-compliant algorithm (typically MD5) is _not_
   available through the cryptographic module. In some cases, the process will
   provide a fallback implementation.
4. Confirm that the available ciphers only contain FIPS-compliant ciphers
   (e.g. no `chacha20_poly1305`).

### Node.js

Node.js requires the environment variable `OPENSSL_MODULES` be set and the
flags `--openssl-shared-config` and `--enable-fips` be passed to the node
command.

Sample Dockerfile:
```dockerfile
FROM node:18-bookworm

ENV OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

COPY --from=debian-openssl-fipsmodule:3.0.8 $OPENSSL_MODULES/fips.so $OPENSSL_MODULES/fips.so
RUN openssl fipsinstall -module $OPENSSL_MODULES/fips.so -out /usr/lib/ssl/fipsmodule.cnf
COPY --from=debian-openssl-fipsmodule:3.0.8 /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf

CMD [ "node", "--openssl-shared-config", "--enable-fips" ]
```

Build the image and run:
```bash
docker run -it --rm $(docker build -q .)
```

Confirm that node is running in FIPS mode:
```
> crypto.fips;
1
```

Confirm that SHA256 (a FIPS-compliant algorithm) is available:
```
> crypto.createHash('sha256');
Hash {
  _options: undefined,
  [Symbol(kHandle)]: Hash {},
  [Symbol(kState)]: { [Symbol(kFinalized)]: false }
}
```

Confirm that MD5 (a non-FIPS-compliant algorithm) is unavailable:
```
> crypto.createHash('md5')
Uncaught Error: error:0308010C:digital envelope routines::unsupported
    at new Hash (node:internal/crypto/hash:69:19)
    at Object.createHash (node:crypto:133:10) {
  opensslErrorStack: [ 'error:03000086:digital envelope routines::initialization error' ],
  library: 'digital envelope routines',
  reason: 'unsupported',
  code: 'ERR_OSSL_EVP_UNSUPPORTED'
}
```

Confirm that `ecdhe-rsa-chacha20-poly1305` (a non-FIPS-compliant cipher) is unavailable:
```
> tls.getCiphers().includes('ecdhe-rsa-chacha20-poly1305');
false
```
Note that `tls_chacha20_poly1305_sha256` appears in `tls.getCiphers()` because
all of the TLSv1.3 ciphers are [hard-coded](https://github.com/nodejs/node/blob/8a01b3dcb7d08a48bfd3e6bf85ef49faa1454839/src/crypto/crypto_cipher.cc#L212-L222)
in the list.

### Python

Sample Dockerfile:
```dockerfile
FROM python:3.12-bookworm

ARG OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

COPY --from=debian-openssl-fipsmodule:3.0.8 $OPENSSL_MODULES/fips.so $OPENSSL_MODULES/fips.so
RUN openssl fipsinstall -module $OPENSSL_MODULES/fips.so -out /usr/lib/ssl/fipsmodule.cnf
COPY --from=debian-openssl-fipsmodule:3.0.8 /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf
```

Build the image and run:
```bash
docker run -it --rm $(docker build -q .)
```

Confirm that SHA256 (a FIPS-compliant algorithm) is available:
```
>>> import hashlib
>>> hashlib.new('sha256')
<sha256 _hashlib.HASH object @ 0x7fc4c806b7f0>
```

Python 3.12+ includes a fallback implementation of MD5:

> For any of the MD5, SHA1, SHA2, or SHA3 algorithms that the linked OpenSSL
> does not provide we fall back to a verified implementation from the HACL*
> project.

Previous versions with throw an exception, 3.12+ will return an object from a
different module than `hashlib`:
```
>>> import hashlib
>>> hashlib.new('md5')
<_md5.md5 object at 0x7fc4c8026590>
```

Confirm that `TLS_CHACHA20_POLY1305_SHA256` is unavailable:
```
>>> import ssl
>>> ctx = ssl.create_default_context()
>>> 'TLS_CHACHA20_POLY1305_SHA256' in [cipher['name'] for cipher in ctx.get_ciphers()]
False
```

### Ruby

Sample Dockerfile:
```dockerfile
FROM ruby:3.2-bookworm

ARG OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

COPY --from=debian-openssl-fipsmodule:3.0.8 $OPENSSL_MODULES/fips.so $OPENSSL_MODULES/fips.so
RUN openssl fipsinstall -module $OPENSSL_MODULES/fips.so -out /usr/lib/ssl/fipsmodule.cnf
COPY --from=debian-openssl-fipsmodule:3.0.8 /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf
```

Ruby 3.2 uses Ruby/OpenSSL 3.1.0, which doesn't support the concept of FIPS providers ([added](https://github.com/ruby/openssl/commit/c5b2bc1268bcb946ff2eb52904a85278a1dac12c)
in Ruby/OpenSSL 3.2.0). As a result `OpenSSL.fips` doesn't work.

Confirm that SHA256 is available through OpenSSL's digest:
```
irb(main):002:0> OpenSSL::Digest::SHA256.new
=> #<OpenSSL::Digest::SHA256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855>
```

Confirm that MD5 is unavailable throught OpenSSL's digest:
```
irb(main):001:0> require "openssl"
=> true
irb(main):002:0> OpenSSL::Digest::MD5.new
/usr/local/lib/ruby/3.2.0/openssl/digest.rb:35:in `initialize': Digest initialization failed: initialization error (OpenSSL::Digest::DigestError)
	from /usr/local/lib/ruby/3.2.0/openssl/digest.rb:35:in `block (3 levels) in <class:Digest>'
	from (irb):2:in `new'
	from (irb):2:in `<main>'
	from /usr/local/lib/ruby/gems/3.2.0/gems/irb-1.6.2/exe/irb:11:in `<top (required)>'
	from /usr/local/bin/irb:25:in `load'
	from /usr/local/bin/irb:25:in `<main>'
```
Ruby's `Digest` also doesn't use OpenSSL (it contains its own [C implementation](https://github.com/ruby/ruby/tree/e51014f9c05aa65cbf203442d37fef7c12390015/ext/digest)
), so `Digest::MD5` will continue to work.

Confirm that `TLS_AES_256_GCM_SHA384` is available, but
`TLS_CHACHA20_POLY1305_SHA256` is unavailable:
```
irb(main):001:0> require "openssl"
=> true
irb(main):002:0> ctx = OpenSSL::SSL::SSLContext.new
=> #<OpenSSL::SSL::SSLContext:0x00007ffb5d296430 @verify_hostname=false, @verify_mode=0>
irb(main):003:0> ctx.ciphers.any? { |name, version, bits, alg_bits| name == "TLS_AES_256_GCM_SHA384" }
=> true
irb(main):004:0> ctx.ciphers.any? { |name, version, bits, alg_bits| name == "TLS_CHACHA20_POLY1305_SHA256" }
=> false
```

### Apache httpd

Create a custom `httpd.conf` file, ensure that it contains `SSLFIPS on`.

Sample Dockerfile:
```dockerfile
FROM httpd:2.4-bookworm

ARG OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

COPY --from=debian-openssl-fipsmodule:3.0.8 $OPENSSL_MODULES/fips.so $OPENSSL_MODULES/fips.so
RUN openssl fipsinstall -module $OPENSSL_MODULES/fips.so -out /usr/lib/ssl/fipsmodule.cnf
COPY --from=debian-openssl-fipsmodule:3.0.8 /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf

COPY httpd.conf /usr/local/apache2/conf/httpd.conf

EXPOSE 443
```

Generate localhost keys for testing:
```
openssl req -x509 -out server.crt -keyout server.key \
    -newkey rsa:2048 -nodes -sha256 \
    -subj '/CN=localhost' -extensions EXT -config <( \
         printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
```

Build the image and run:
```
docker run --security-opt label=disable \
    --mount type=bind,src=server.crt,target=/usr/local/apache2/conf/server.crt \
    --mount type=bind,src=server.key,target=/usr/local/apache2/conf/server.key \
    -it --rm -p 8443:443 $(docker build -q .)
```

Observe a log message of the form `AH01884: OpenSSL has FIPS mode enabled`. Confirm that the site returns data by visiting <https://localhost:443>.

Confirm that the site connects with a FIPS cipher `TLS_AES_256_GCM_SHA384`:
```
echo | openssl s_client -connect localhost:8443 -ciphersuites TLS_AES_256_GCM_SHA384
```

Confirm that the site does not connect with a non-FIPS cipher `TLS_CHACHA20_POLY1305_SHA256`:
```
echo | openssl s_client -connect localhost:8443 -ciphersuites TLS_CHACHA20_POLY1305_SHA256
```

## License

[MIT License](LICENSE.txt).
