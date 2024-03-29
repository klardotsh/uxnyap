**WARNING: THIS PROJECT IS ABANDONED.**

It's retained here for documentation purposes, but please don't attempt to
actually use this. The protocol needs serious work (eg. a better data structure
for fixed-length transmissions such that a double-null sequence isn't required
    to end the stream), and I almost guarantee none of this runs on modern
    Uxn/Varvara implementations. Use this as inspiration, fork it, whatever,
    but it doesn't do anything useful of its own, and I haven't really had the
    time to dig back into the Uxn ecosystem.

- klardotsh, Dec 2023

---

# uxnyap

> a hack so bad I felt the need to write a protocol definition for it

If [uxn has file access](https://merveilles.town/@neauoire/107091120383910458),
it occurred to me that you could hack something on top of this interface to
talk to the network on systems providing a helper binary (or, since this is
basically just a plan9-style solution to the problem space, systems that are
plan9). I guess I'll nerd-snipe myself and prove the concept. This
implementation and its specification are public domain or your locality's
closest equivalent via
[CC0](https://creativecommons.org/publicdomain/zero/1.0/), see `COPYING` in
this repo.

This protocol could *in theory* be better served by something like cap'n proto
or protobufs, but since this is pure hackery for now and just a tech demo,
we'll use this hacked up encoding instead. Besides, it's an easier format for
humans to hand-write, which is valuable in the land of uxn.

In its current form, `uxnyap` is not technically `uxn` specific - it could just
as well be a generic network abstraction tool for any VM or OS. That may change
in the future when and if Uxn were to get a `Network` device natively.

## Protocol

### Request

| Byte |    Name |          Type | Commentary |
|------|---------|---------------|------------|
|  1+2 | VERSION |         u16be | Protocol version tag, a simple monotonic counter of breaking changes. The special value `0`, currently the only supported value, denotes no promises about stability whatsoever. In the future, this value will use the latest supported protocol (including unstable ones), meaning `0` is _never_ a stable protocol and should not be depended upon for API stability. |
|    3 |   PROTO |  enum `Proto` | |
|    4 |      ID |            u8 | An identifier for this request, echoed back at response time. Need not be unique or monotonic, and thus could have application-defined meanings (perhaps a pointer to a context object) |
|  5+6 |    PORT |         u16be | Target port number. Special port `0` uses the protocol-specific default if available |
|  7-x |  TARGET |          []u8 | Null-terminated UTF-8 stream denoting the target as a resolvable address (eg. IP or DNS) |
|  x-y | VARARGS |          []u8 | Protocol-specified varargs. By convention, varargs is a 1-dimensional list, null separated. The list ends with two null bytes. Thus, the shortest VARARGS (and thus its overhead) is two bytes long. |
|  y-z |    BODY |          []u8 | Body of the request. Also ends with a double null byte sequence. |


### Response

| Byte | Name    |          Type | Commentary |
|------|---------|---------------|------------|
|  1+2 | VERSION |         u16be | Protocol version tag, a simple monotonic counter of breaking changes. The special value `0`, currently the only supported value, denotes no promises about stability whatsoever. In the future, this value will use the latest supported protocol (including unstable ones), meaning `0` is _never_ a stable protocol and should not be depended upon for API stability. |
|    3 |   PROTO |  enum `Proto` | |
|    4 |      ID |            u8 | The ID from the request that triggered this response |
|  5+6 |  STATUS |         u16be | Protocol-specific response status, if applicable (otherwise, both bytes are null). For example, HTTP status codes go here. Special values `65000` and above represent an internal error in processing the request (perhaps a malformed sequence, missing port number, etc), which are not yet enumerated in this example |
|  7-x | VARARGS |          []u8 | Protocol-specified varargs. By convention, varargs is a 1-dimensional list, null separated. The list ends with two null bytes. Thus, the shortest VARARGS (and thus its overhead) is two bytes long. |
|  x-y |    BODY |          []u8 | Body of the response. If the protocol is encrypted or secured, this will have been stripped by this point. Also ends with a double null byte sequence. |

### Enums

#### Proto (u8)

| Name      | Value | Commentary |
|-----------|-------|------------|
| MALFORMED |     0 | Placeholder to be used in responses where the request was so malformed the protocol can't reply with the protocol used. Implicitly invalid for use in requests. |
| UDP       |     1 | Raw UDP stream, unused in this example repo |
| TCP       |     2 | Raw TCP stream, unused in this example repo |
| HTTP      |     3 | An HTTP(s) request, first vararg is a port (required), remaining varargs are null-separated key-value pairs to become request headers (optional). TLS termination must be provided by backing implementation. HTTP version (eg. 1.0, 1.1, 2.0) is implementation's choice. |
| GEMINI    |     4 | A Gemini request, unused in this example repo |
| ...       |     5 | ... what other protocols are useful here? |

## TODO

- Stream cancellation
- Change BODY to be binary safe
