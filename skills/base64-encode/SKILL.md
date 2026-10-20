---
name: base64-encode
description: Encodes plain text into its Base64 representation. Use this skill whenever the user asks to encode text as base64, convert a string into base64 format, b64-encode some content, or produce a base64 string from raw text.
---

# Base64 Encode

Encode the input text to Base64.

## Rules
- Use the standard Base64 alphabet (A-Z, a-z, 0-9, +, /) with '=' padding.
- Encode the exact input bytes as UTF-8.

## Output
Report the result with exactly one XML tool call:

<function name="b64_report">
<param name="base64">BASE64_STRING</param>
</function>