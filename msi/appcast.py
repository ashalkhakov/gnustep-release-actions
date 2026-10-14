#!/usr/bin/env python3
"""The Windows appcast WinSparkle reads, for a release (the counterpart of
sparkle-appcast for the Mac): the release's installer, its download URL on
the release and its EdDSA signature by the same key as the Mac's
(SPARKLE_PRIVATE_KEY, as Sparkle's generate_keys -x exports it). WinSparkle
checks signatures the way Sparkle does, so one key serves both.

  appcast.py <msi> <output.xml>

The environment: TAG, APP_VERSION, BUILD_NUMBER (version.sh's),
SPARKLE_PRIVATE_KEY, NAME, and optionally PLIST (the app's
Info-gnustep.plist, whose SUPublicEDKey the private key must match) and
DOWNLOAD_URL_PREFIX.
A tag that is not a release's (none, or a pre-release's) writes nothing, as
does a missing key, with a warning. Ed25519 is RFC 8032's, in Python, so that
nothing else is installed and the key goes nowhere but into this process.
"""
import base64
import email.utils
import hashlib
import os
import re
import sys
from xml.sax.saxutils import escape, quoteattr

# RFC 8032, section 6: Ed25519, the reference algorithm.
P = 2 ** 255 - 19
L = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
GY = 4 * pow(5, P - 2, P) % P


def _recover_x(y, sign):
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P)
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P != 0:
        x = x * pow(2, (P - 1) // 4, P) % P
    if (x & 1) != sign:
        x = P - x
    return x


G = (_recover_x(GY, 0), GY, 1, _recover_x(GY, 0) * GY % P)


def _add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % P
    b = (p[1] + p[0]) * (q[1] + q[0]) % P
    c = 2 * p[3] * q[3] * D % P
    d = 2 * p[2] * q[2] % P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def _mul(s, p):
    q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            q = _add(q, p)
        p = _add(p, p)
        s >>= 1
    return q


def _compress(p):
    zinv = pow(p[2], P - 2, P)
    x, y = p[0] * zinv % P, p[1] * zinv % P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _secret(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:]


def public_key(seed):
    a, _ = _secret(seed)
    return _compress(_mul(a, G))


def sign(seed, message):
    a, prefix = _secret(seed)
    pub = _compress(_mul(a, G))
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % L
    big_r = _compress(_mul(r, G))
    k = int.from_bytes(hashlib.sha512(big_r + pub + message).digest(), "little") % L
    return big_r + int.to_bytes((r + k * a) % L, 32, "little")


def seed_of(exported):
    """The 32-byte seed in what generate_keys -x exports: the seed itself,
    or (older Sparkle) the 64-byte secret key, seed then public key, or
    that and the public key again (96)."""
    raw = base64.b64decode(exported.strip())
    if len(raw) in (32, 64, 96):
        return raw[:32]
    raise ValueError("SPARKLE_PRIVATE_KEY is %d bytes, not an Ed25519 key" % len(raw))


def main():
    msi, output = sys.argv[1], sys.argv[2]
    tag = os.environ.get("TAG", "")
    if not tag or "-" in tag:
        print("not a release (tag '%s'): no appcast; a pre-release is offered to no one" % tag)
        return 0
    key = os.environ.get("SPARKLE_PRIVATE_KEY", "")
    if not key:
        print("::warning::SPARKLE_PRIVATE_KEY not set; no appcast, so the Windows app will not be offered this release")
        return 0
    seed = seed_of(key)
    pub = base64.b64encode(public_key(seed)).decode()
    expected = ""
    plist = os.environ.get("PLIST", "")
    if plist and os.path.exists(plist):
        text = open(plist, encoding="utf-8").read()
        m = (re.search(r"<key>SUPublicEDKey</key>\s*<string>([^<]*)</string>", text)
             or re.search(r"SUPublicEDKey\s*=\s*\"?([^\";]*)", text))
        expected = m.group(1).strip() if m else ""
    if expected and expected != pub:
        print("::error::SPARKLE_PRIVATE_KEY's public half is %s, not the app's SUPublicEDKey %s: every installed copy would refuse the update" % (pub, expected))
        return 1

    data = open(msi, "rb").read()
    signature = base64.b64encode(sign(seed, data)).decode()
    name = os.environ["NAME"]
    version = os.environ["APP_VERSION"]
    build = os.environ["BUILD_NUMBER"]
    prefix = os.environ.get("DOWNLOAD_URL_PREFIX") or "https://github.com/%s/releases/download/%s/" % (os.environ["GITHUB_REPOSITORY"], tag)
    url = prefix + os.path.basename(msi)
    xml = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>%s</title>
    <item>
      <title>%s</title>
      <pubDate>%s</pubDate>
      <sparkle:version>%s</sparkle:version>
      <sparkle:shortVersionString>%s</sparkle:shortVersionString>
      <enclosure url=%s sparkle:os="windows" length="%d" type="application/octet-stream"
                 sparkle:installerArguments="/passive" sparkle:edSignature="%s"/>
    </item>
  </channel>
</rss>
""" % (escape(name), escape(version), email.utils.formatdate(usegmt=True), escape(build),
       escape(version), quoteattr(url), len(data), signature)
    open(output, "w", encoding="utf-8").write(xml)
    print(xml)
    print("signed by the key whose public half is %s" % pub)
    return 0


if __name__ == "__main__":
    sys.exit(main())
